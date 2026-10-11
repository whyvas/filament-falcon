#!/usr/bin/env python3
"""Build the Filament Falcon project book (PDF) from the files in this repo.

    python3 docs/book/build_book.py                 # -> docs/Filament_Falcon_Project_Book.pdf
    python3 docs/book/build_book.py --html-only     # just write docs/book/_build/book.html
    python3 docs/book/build_book.py --run-tests --godot /path/to/godot
                                                    # re-run the game smoke + flight tests first
                                                    # and store them in docs/book/test_results.txt

Needs: Python 3.9+, weasyprint (>= 61), markdown, pillow, openpyxl
    pip install weasyprint markdown pillow openpyxl

Everything that can change in the project is read from the repo at build time:
docs/SPEC.md, frame/README.md, frame/BOM.md, frame/cut_list.csv, frame/generated/geometry.json,
docs/mechanical/*.md, shared/*.json, shared/led_protocol.md, docs/electronics/*.md, firmware/README.md,
docs/game/README.md, game/scripts/missions/*.gd, game/scripts/sim/ship_sim.gd,
cad/export/validation_report.json, bom/Filament_Falcon_BOM.xlsx (or .csv), all PNG/JPG renders,
drawings, diagrams and screenshots, and `git log` for the changelog. The narrative text that
ties it together lives in this file (search for the chapter functions ch_*).
Images are downscaled/recompressed into docs/book/_build/img (git-ignored) to keep the PDF small.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import re
import subprocess
import sys
from collections import OrderedDict, defaultdict
from datetime import datetime
from pathlib import Path
from string import Template
from zoneinfo import ZoneInfo

import markdown
from PIL import Image, ImageChops, ImageDraw, ImageFilter

BOOK_VERSION = "1.0"
TZ = ZoneInfo("America/Moncton")
ROOT = Path(__file__).resolve().parents[2]
BOOK = ROOT / "docs" / "book"
BUILD = BOOK / "_build"
IMGDIR = BUILD / "img"
OUT_PDF = ROOT / "docs" / "Filament_Falcon_Project_Book.pdf"
TEST_RESULTS = BOOK / "test_results.txt"

MISSING: list[str] = []       # things the book wanted but could not find (printed + on the back page)
TOC: list[tuple] = []         # (level, anchor, number, title)


# ----------------------------------------------------------------------------------------------
# small helpers
# ----------------------------------------------------------------------------------------------
def esc(s) -> str:
    return html.escape(str(s), quote=True)


def rd(rel: str) -> str:
    p = ROOT / rel
    if not p.exists():
        MISSING.append(f"file {rel}")
        return ""
    return p.read_text(encoding="utf-8")


def jload(rel: str):
    t = rd(rel)
    return json.loads(t) if t else {}


def ftin(mm: float) -> str:
    inch = mm / 25.4
    ft = int(inch // 12)
    rest = inch - 12 * ft
    if ft == 0:
        return f'{rest:.1f}"'
    return f"{ft}' {rest:.1f}\""


def L(mm: float) -> str:
    """length: metric with imperial in brackets"""
    if mm < 300:
        return f'{mm:.0f} mm ({mm / 25.4:.1f}")'
    return f"{mm:,.0f} mm ({ftin(mm)})".replace(",", " ")


def KG(kg: float) -> str:
    return f"{kg:.0f} kg ({kg * 2.20462:.0f} lb)"


def N(n: float) -> str:
    return f"{n:,.0f} N ({n * 0.224809:,.0f} lbf)".replace(",", " ")


def NM(nm: float) -> str:
    return f"{nm:+.0f} N·m ({nm * 0.737562:+.0f} lbf·ft)"


def cad(v: float) -> str:
    return f"${v:,.2f}"


PRETTY = [
    (re.compile(r" -&gt; "), " → "), (re.compile(r"-&gt;"), "→"), (re.compile(r"&lt;-"), "←"),
    (re.compile(r"=&gt;"), "⇒"), (re.compile(r"&gt;="), "≥"), (re.compile(r"&lt;="), "≤"),
    (re.compile(r"\+-(?=\s?\d)"), "±"),
    (re.compile(r"(\d) deg\b"), r"\1°"),
    (re.compile(r"(\d) x (\d)"), r"\1 × \2"),
]


def prettify(h: str) -> str:
    """typographic clean-up of rendered HTML, never inside <pre>/<code>"""
    parts = re.split(r"(<pre>.*?</pre>|<code>.*?</code>)", h, flags=re.S)
    for i in range(0, len(parts), 2):
        s = parts[i]
        for rx, rep in PRETTY:
            s = rx.sub(rep, s)
        parts[i] = s
    return "".join(parts)


def md_html(text: str, inline: bool = False) -> str:
    text = re.sub(r"^\s*!\[[^\]]*\]\([^)]*\)\s*$", "", text, flags=re.M)        # images: placed by the book
    text = re.sub(r"\[([^\]]+)\]\((?!https?:)[^)]*\)", r"\1", text)              # repo links -> plain text
    out = markdown.markdown(text, extensions=["tables", "fenced_code", "sane_lists"])
    out = prettify(out)
    if inline:
        out = re.sub(r"^<p>(.*)</p>$", r"\1", out.strip(), flags=re.S)
    return out


def md_section(rel: str, heading: str, keep_heading: bool = False) -> str:
    """Markdown text under the first heading that starts with `heading` (until the next heading
    of the same or a higher level)."""
    src = rd(rel)
    lines = src.splitlines()
    start, level = None, None
    in_code = False
    for i, ln in enumerate(lines):
        if ln.strip().startswith("```"):
            in_code = not in_code
        if in_code:
            continue
        m = re.match(r"^(#{1,6})\s+(.*)$", ln)
        if not m:
            continue
        if start is None:
            if m.group(2).strip().lower().startswith(heading.lower()):
                start, level = i, len(m.group(1))
        elif len(m.group(1)) <= level:
            body = lines[start if keep_heading else start + 1:i]
            return "\n".join(body).strip()
    if start is None:
        MISSING.append(f"section '{heading}' in {rel}")
        return ""
    return "\n".join(lines[start if keep_heading else start + 1:]).strip()


def md_table(text: str) -> list[list[str]]:
    """first markdown table in text -> rows (header first), cells as raw markdown"""
    rows = []
    for ln in text.splitlines():
        ln = ln.strip()
        if ln.startswith("|"):
            cells = [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", ln.strip().strip("|"))]
            if all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c):
                continue
            rows.append(cells)
        elif rows:
            break
    return rows


def md_bullets(text: str) -> list[str]:
    items, cur = [], None
    for ln in text.splitlines():
        m = re.match(r"^\s*(?:[-*]|\d+\.)\s+(.*)$", ln)
        if m and not ln.startswith("   "):
            if cur is not None:
                items.append(cur)
            cur = m.group(1)
        elif cur is not None and ln.strip():
            cur += " " + ln.strip()
        elif cur is not None and not ln.strip():
            items.append(cur)
            cur = None
    if cur is not None:
        items.append(cur)
    return items


def table(header, rows, cls="", num_cols=(), total=None) -> str:
    h = [f'<table class="{cls}"><thead><tr>']
    for i, c in enumerate(header):
        h.append(f'<th class="{"num" if i in num_cols else ""}">{c}</th>')
    h.append("</tr></thead><tbody>")
    for r in rows:
        h.append("<tr>" + "".join(f'<td class="{"num" if i in num_cols else ""}">{c}</td>' for i, c in enumerate(r)) + "</tr>")
    if total:
        h.append('<tr class="total">' + "".join(f'<td class="{"num" if i in num_cols else ""}">{c}</td>' for i, c in enumerate(total)) + "</tr>")
    h.append("</tbody></table>")
    return "".join(h)


def md_tbl(rows, cls="", num_cols=()) -> str:
    """render md_table() rows with inline markdown in the cells"""
    if not rows:
        return ""
    return table([md_html(c, True) for c in rows[0]], [[md_html(c, True) for c in r] for r in rows[1:]], cls, num_cols)


# ----------------------------------------------------------------------------------------------
# images
# ----------------------------------------------------------------------------------------------
def _trim(im: Image.Image, pad_frac: float) -> Image.Image:
    rgb = im.convert("RGB")
    corner = rgb.getpixel((2, 2))
    bg = Image.new("RGB", rgb.size, corner)
    diff = ImageChops.difference(rgb, bg).convert("L").point(lambda v: 255 if v > 14 else 0)
    bbox = diff.getbbox()
    if not bbox:
        return im
    w, h = rgb.size
    pad = int(max(bbox[2] - bbox[0], bbox[3] - bbox[1]) * pad_frac)
    box = (max(0, bbox[0] - pad), max(0, bbox[1] - pad), min(w, bbox[2] + pad), min(h, bbox[3] + pad))
    return im.crop(box)


def img(rel: str, maxw: int = 1500, trim: bool = False, q: int = 82, pad: float = 0.04,
        fmt: str = "jpg", crop: tuple | None = None) -> str | None:
    """downscale/compress a repo image into _build/img and return its file URI (None if missing)"""
    src = ROOT / rel
    if not src.exists():
        MISSING.append(f"image {rel}")
        return None
    key = hashlib.sha1(f"{rel}|{src.stat().st_mtime_ns}|{maxw}|{trim}|{q}|{pad}|{fmt}|{crop}".encode()).hexdigest()[:12]
    out = IMGDIR / f"{Path(rel).stem}_{key}.{fmt}"
    if not out.exists():
        im = Image.open(src)
        if im.mode in ("RGBA", "LA", "P"):
            im = im.convert("RGBA")
            white = Image.new("RGBA", im.size, (255, 255, 255, 255))
            im = Image.alpha_composite(white, im)
        im = im.convert("RGB")
        if crop:
            w, h = im.size
            im = im.crop((int(crop[0] * w), int(crop[1] * h), int(crop[2] * w), int(crop[3] * h)))
        if trim:
            im = _trim(im, pad)
        if im.width > maxw:
            im = im.resize((maxw, round(im.height * maxw / im.width)), Image.LANCZOS)
        if fmt == "png":
            im.save(out, optimize=True)
        else:
            im.save(out, quality=q, optimize=True, progressive=True)
    return out.as_uri()


def fig(rel: str, cap: str = "", cls: str = "h4i", paper: bool = False, **kw) -> str:
    uri = img(rel, **kw)
    c = f"{cls} {'paper' if paper else ''}"
    if not uri:
        return f'<figure class="{c}"><div class="card dim small">Missing image: {esc(rel)}</div></figure>'
    capt = f"<figcaption>{cap}</figcaption>" if cap else ""
    return f'<figure class="{c}"><img src="{uri}" alt="{esc(Path(rel).name)}">{capt}</figure>'


def make_starfield():
    """deterministic dark-space page background"""
    import random
    out = BUILD / "bg_stars.png"
    if out.exists():
        return
    rnd = random.Random(7)
    W, H = 2000, 1125
    im = Image.new("RGB", (W, H), (7, 11, 22))
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(glow)
    for (cx, cy, r, col) in [(1750, 120, 520, (10, 24, 50)), (150, 1050, 600, (18, 11, 38)), (1100, 1150, 420, (6, 20, 34))]:
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=col)
    glow = glow.filter(ImageFilter.GaussianBlur(220))
    im = ImageChops.add(im, glow)
    d = ImageDraw.Draw(im)
    for _ in range(1400):
        x, y = rnd.randrange(W), rnd.randrange(H)
        b = int(rnd.random() ** 3 * 150) + 30
        tint = rnd.choice([(0, 0, 0), (0, 10, 30), (25, 10, 0)])
        col = (min(255, b + tint[0]), min(255, b + tint[1]), min(255, b + tint[2]))
        if rnd.random() < 0.03:
            d.ellipse((x - 1, y - 1, x + 1, y + 1), fill=col)
        else:
            d.point((x, y), fill=col)
    im.save(out, optimize=True)


# ----------------------------------------------------------------------------------------------
# data from the repo
# ----------------------------------------------------------------------------------------------
class Data:
    def __init__(self):
        self.geom = jload("frame/generated/geometry.json")
        self.labels = jload("shared/panel_labels.json")
        self.segs = jload("shared/led_segments.json")
        self.imap = jload("shared/input_map.json")
        self.val = jload("cad/export/validation_report.json")
        self.filament = jload("bom/tools/filament_estimate.json")
        self.switch = self._switch_bom()
        self.bom = self._bom()
        self.missions = self._missions()
        self.hero = self._hero()
        self.tests = self._tests()
        self.git = self._git()
        self.cut = self._cut_list()

    def _switch_bom(self):
        """docs/mechanical/switch_bom.md -> {panel: {size, desc, rows}}"""
        src = rd("docs/mechanical/switch_bom.md")
        out = OrderedDict()
        for m in re.finditer(r"^## (\S+) \(([^)]*)\) - (.*?)\n(.*?)(?=^## |\Z)", src, flags=re.M | re.S):
            rows = md_table(m.group(4))
            out[m.group(1)] = {"size": m.group(2), "desc": m.group(3).strip(), "rows": rows[1:] if rows else []}
        return out

    def _bom(self):
        """per-category totals, recomputed from the editable spreadsheet (openpyxl does not cache
        formula results, so Qty-to-buy and line totals are recomputed exactly like the sheet does)"""
        cats = OrderedDict()
        status = defaultdict(float)
        stores = defaultdict(float)
        rows = []
        src = "bom/Filament_Falcon_BOM.xlsx"
        self.bom_sheets = []
        notes = []
        try:
            import openpyxl
            wb = openpyxl.load_workbook(ROOT / src)
            ws = wb["BOM"]
            hdr = [c.value for c in ws[1]]
            ix = {h: i for i, h in enumerate(hdr)}
            for r in ws.iter_rows(min_row=2, values_only=True):
                if not r[ix["Category"]]:
                    continue
                have = r[ix["Have it"]]
                have = (have is True) or (isinstance(have, str) and have.strip().upper() in ("TRUE", "=TRUE()"))
                qty = float(r[ix["Qty needed"]] or 0)
                buy = 0 if have else qty
                price = r[ix["Unit price CAD"]]
                price = float(price) if isinstance(price, (int, float)) else 0.0
                rows.append(dict(cat=r[ix["Category"]], item=r[ix["Item"]], buy=buy, total=buy * price,
                                 store=r[ix["Store"]] or "", status=r[ix["Price status"]] or ""))
            notes = [r[0] for r in wb["Notes"].iter_rows(values_only=True) if r[0]] if "Notes" in wb.sheetnames else []
            self.bom_sheets = wb.sheetnames
            self.bom_source = src
        except Exception as e:  # fall back to the CSV export
            MISSING.append(f"{src} not readable ({e}); used the CSV")
            src = "bom/Filament_Falcon_BOM.csv"
            for r in csv.DictReader((ROOT / src).open(encoding="utf-8")):
                rows.append(dict(cat=r["Category"], item=r["Item"], buy=float(r["Qty to buy"] or 0),
                                 total=float(r["Line total"] or 0), store=r["Store"], status=r["Price status"]))
            self.bom_source = src
        for r in rows:
            c = cats.setdefault(r["cat"], {"lines": 0, "buy_lines": 0, "total": 0.0})
            c["lines"] += 1
            c["buy_lines"] += 1 if r["buy"] > 0 else 0
            c["total"] += r["total"]
            if "ALTERNATIVE" not in r["cat"].upper():
                status[r["status"]] += r["total"]
                stores[r["store"]] += r["total"]
        return {"cats": cats, "rows": rows, "status": status, "stores": stores, "notes": notes,
                "grand": sum(v["total"] for k, v in cats.items() if "ALTERNATIVE" not in k.upper()),
                "alt": sum(v["total"] for k, v in cats.items() if "ALTERNATIVE" in k.upper())}

    def _missions(self):
        order = re.search(r"MISSION_ORDER := \[(.*?)\]", rd("game/scripts/autoload/game.gd"))
        order = re.findall(r'"(\w+)"', order.group(1)) if order else ["launch", "docking", "lunar", "asteroids", "reentry", "sandbox"]
        out = []
        for mid in order:
            src = rd(f"game/scripts/missions/m_{mid}.gd")

            def field(name):
                m = re.search(rf'^\s*{name} = "((?:[^"\\]|\\.)*)"', src, flags=re.M)
                return m.group(1).replace('\\"', '"') if m else ""
            objs = re.findall(r'\{"text": "((?:[^"\\]|\\.)*)", "role": "(\w+)"\}', src)
            out.append(dict(id=mid, title=field("title"), tagline=field("tagline"), briefing=field("briefing"),
                            pilot=field("pilot_job"), ops=field("ops_job"), objectives=objs))
        return out

    def _hero(self):
        rows = md_table(md_section("docs/game/README.md", "7. Crew guide").split("**Missions:**")[-1])
        return rows[1:] if rows else []

    def _tests(self):
        if not TEST_RESULTS.exists():
            MISSING.append("docs/book/test_results.txt (run with --run-tests --godot <path>)")
            return {}
        res = {"meta": {}, "smoke": [], "flight": [], "smoke_result": "", "flight_result": ""}
        sec = None
        for ln in TEST_RESULTS.read_text(encoding="utf-8").splitlines():
            if ln.startswith("# ") and ":" in ln:
                k, v = ln[2:].split(":", 1)
                res["meta"][k.strip()] = v.strip()
            elif ln.strip() in ("[smoke]", "[flight]"):
                sec = ln.strip()[1:-1]
            elif sec and re.match(r"^(PASS|FAIL) ", ln):
                d = dict(re.findall(r"(\w+)=(\S+)", ln))
                d["ok"] = ln.startswith("PASS")
                d["id"] = ln.split()[1]
                res[sec].append(d)
            elif sec and ln.startswith("RESULT:"):
                res[sec + "_result"] = ln[7:].strip()
        return res

    def _git(self):
        def g(*a):
            try:
                return subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
            except Exception:
                return ""
        log = []
        for ln in g("log", "-n", "14", "--date=iso-strict", "--format=%h\x1f%ad\x1f%s").splitlines():
            h, d, s = ln.split("\x1f")
            try:
                d = datetime.fromisoformat(d).astimezone(TZ).strftime("%Y-%m-%d %H:%M")
            except ValueError:
                pass
            log.append((h, d, s))
        dirty = g("status", "--porcelain", "--untracked-files=no")
        return {"head": g("rev-parse", "--short", "HEAD"), "branch": g("rev-parse", "--abbrev-ref", "HEAD"),
                "log": log, "dirty": bool(dirty), "count": g("rev-list", "--count", "HEAD")}

    def _cut_list(self):
        p = ROOT / "frame/cut_list.csv"
        if not p.exists():
            MISSING.append("frame/cut_list.csv")
            return []
        return list(csv.DictReader(p.open(encoding="utf-8")))


# ----------------------------------------------------------------------------------------------
# page builders
# ----------------------------------------------------------------------------------------------
CH = {"n": 0}


def chapter(title: str, inner: str, kicker: str = "", anchor: str | None = None) -> str:
    CH["n"] += 1
    n = f"{CH['n']:02d}"
    anchor = anchor or "ch" + n
    TOC.append((1, anchor, n, title))
    k = f'<div class="kicker">{kicker}</div>' if kicker else ""
    return f'<section class="page" id="{anchor}">{k}<h1><span class="num">{n}</span><span class="ct">{esc(title)}</span></h1>{inner}</section>'


def page(title: str, inner: str, sub: str = "", toc: bool = True, cls: str = "") -> str:
    anchor = "p" + hashlib.md5((title + sub + str(len(TOC)) + str(CH["n"])).encode()).hexdigest()[:8]
    if toc:
        TOC.append((2, anchor, "", title))
    s = f" <small>{sub}</small>" if sub else ""
    return f'<section class="page {cls}" id="{anchor}"><h2>{esc(title)}{s}</h2>{inner}</section>'


def stat(v, l) -> str:
    return f'<div class="stat"><div class="v">{v}</div><div class="l">{l}</div></div>'


def card(inner, cls="") -> str:
    return f'<div class="card {cls}">{inner}</div>'


# ----------------------------------------------------------------------------------------------
# chapters
# ----------------------------------------------------------------------------------------------
def cover(D: Data, now: datetime) -> str:
    hero = img("docs/game/screenshots/08_docking_chase.jpg", maxw=2200, q=84)
    inset = img("cad/export/png/overview_flight.png", maxw=1200, q=86)
    status = md_section("README.md", "Status")
    return f"""
<section class="cover"><div class="cover-wrap">
  <img class="cover-hero" src="{hero}">
  <div class="cover-shade"></div>
  <div class="cover-text">
    <div class="kicker">Project book · Fredericton, NB, Canada</div>
    <div class="cover-title">THE FILAMENT<br><span>FALCON</span></div>
    <div class="cover-sub">A home-built, three-seat spaceship cockpit simulator for a dad and his two kids:
      reclining launch seats, a drop-down instrument pod, 3D-printed backlit panels, three ESP32-S3
      joysticks and a Godot space game with six missions.</div>
    <div class="cover-crew"><span class="chip">PILOT · left seat</span><span class="chip">OPS · right seat</span><span class="chip">MISSION CONTROL · Dad</span></div>
  </div>
  <img class="cover-inset" src="{inset}">
  <div class="cover-inset-cap">CAD render: flight configuration · background: docking (in-game)</div>
  <div class="cover-meta"><b>Yves Daigle</b> · github.com/whyvas/filament-falcon<br>
    Book v{BOOK_VERSION} · generated {now.strftime('%Y-%m-%d %H:%M %Z')} (Atlantic time) · {esc(D.git['branch'])} @ {esc(D.git['head'])}{' + local changes' if D.git['dirty'] else ''}<br>
    Status: {md_html(status, True)}</div>
</div></section>"""


def toc_page() -> str:
    return '<section class="page" id="toc"><div class="bookver">%%BOOKVER%%</div><h2>Contents</h2><div class="toc">%%TOC%%</div></section>'


def render_toc() -> str:
    out = []
    for lvl, a, n, t in TOC:
        if lvl == 1:
            out.append(f'<a href="#{a}"><span class="n">{n}</span>{esc(t)}</a>')
        else:
            out.append(f'<a class="sub" href="#{a}">{esc(t)}</a>')
    return "".join(out)


def ch_vision(D: Data) -> str:
    g = D.geom
    dims = g.get("dims", {})
    nlab = len(D.labels.get("labels", []))
    npan = len(D.labels.get("panels", []))
    strip = D.segs.get("strip", {})
    stats = "".join([
        stat("3", "seats: two kids side by side in front, Dad behind on a 250 mm (9.8\") dais"),
        stat(f"{dims.get('W', 0):.0f}×{dims.get('L', 0):.0f}<small> mm</small>", f"footprint ({ftin(dims.get('W', 0))} × {ftin(dims.get('L', 0))})"),
        stat(f"{g['cradle']['recline_deg']:.0f}°", "seat recline, astronaut launch-style, then the pod drops down"),
        stat(f"{len(D.missions)}", "missions in the Godot game, each with a hero moment for both kids"),
        stat(f"{npan}", f"3D-printed backlit panels with {nlab} through-letter labels"),
        stat(f"{strip.get('total_leds', '?')}", "addressable LEDs on ONE WS2812B data line (placeholder map)"),
        stat("3", "ESP32-S3 boards, each a real USB joystick: Falcon Pilot, Ops, Command"),
        stat(cad(D.bom["grand"]).split(".")[0], "CAD still to buy (before tax), from the BOM spreadsheet"),
    ])
    intro = md_section("README.md", "The Filament Falcon").split("## What")[0]
    p1 = f"""
<div class="g-wide-r">
  <div>
    <p class="lead">{md_html(intro.split(chr(10) + chr(10))[0], True)}</p>
    <p>This book collects everything designed so far into one place: how the cockpit moves, how it is
    kept safe, how the wooden frame and printed panels go together, how the electronics talk to the PC,
    and what the game asks of each crew member. It is generated straight from the project files, so it can
    be rebuilt whenever the design changes.</p>
  </div>
  <div>{fig('cad/export/png/overview_flight.png', '<b>Flight configuration.</b> Kids reclined, pod lowered with both 27" window monitors, dash and overhead panels; Dad at Mission Control behind.', 'h28', trim=True, pad=0.02)}</div>
</div>
<div class="stats">{stats}</div>"""
    return chapter("Project vision", p1, "Why we are building a spaceship at home")


def ch_crew(D: Data) -> str:
    roles = md_bullets(md_section("docs/SPEC.md", "Roles"))

    def pick(prefix):
        for r in roles:
            if r.lower().startswith(prefix.lower()):
                return r
        MISSING.append(f"SPEC role '{prefix}'")
        return ""
    guide = md_bullets(md_section("docs/game/README.md", "7. Crew guide").split("**Before")[0])

    def gpick(word):
        for r in guide:
            if word in r:
                return r
        return ""

    def dev(name):
        d = D.imap.get("devices", {}).get(name, {})
        return f'<p class="tiny dim">USB device <code>{esc(name)}</code> · {len(d.get("axes", {}))} axes · {len(d.get("buttons", {}))} mapped buttons</p>'

    def strip_role(txt):
        return re.sub(r"^[^:]+:\s*", "", txt, count=1)
    cards = f"""
<div class="g3">
 {card(f'<h3>Pilot · left seat</h3><p class="small"><em>{md_html(gpick("PILOT"), True)}</em></p><p class="small">{md_html(strip_role(pick("Left seat")), True)}</p>{dev("Falcon Pilot")}', 'pilot')}
 {card(f'<h3>Ops · right seat</h3><p class="small"><em>{md_html(gpick("OPS"), True)}</em></p><p class="small">{md_html(strip_role(pick("Right seat")), True)}</p>{dev("Falcon Ops")}', 'ops')}
 {card(f'<h3>Mission Control · Dad</h3><p class="small"><em>{md_html(gpick("COMMANDER"), True)}</em></p><p class="small">{md_html(strip_role(pick("Rear seat")), True)}</p>{dev("Falcon Command")}', 'cmd')}
</div>
<div class="g3">
 {card('<h4>Shared overhead console</h4><p class="small">' + md_html(strip_role(pick("Overhead")), True) + '</p>')}
 {card('<h4>Kids\' console touchscreen</h4><p class="small">' + md_html(strip_role(pick("Kids' console touchscreen")), True) + '</p>')}
 {card('<h4>Commander screen</h4><p class="small">' + md_html(strip_role(pick("Commander screen")), True) + '</p>', 'cmd')}
</div>"""
    hero_rows = [[f"<b>{md_html(r[1], True)}</b><br><span class='dim'>{md_html(r[2], True)}</span>", md_html(r[3], True), md_html(r[4], True)] for r in D.hero]
    balanced = f"""
<div class="g-21">
  <div>{table(['Mission', 'Pilot hero moment', 'Ops hero moment'], hero_rows, '')}</div>
  <div>
   {card('<h4>Why the jobs are balanced</h4><p class="small">' + md_html(pick("Each mission"), True) + '</p>'
     '<p class="small">The two kids never fight over one stick: the Pilot owns <b>rotation and the main engine</b>, Ops owns <b>translation, systems and payload</b>. Most missions need both: docking needs the Pilot to hold the nose while Ops creeps in on RCS; the asteroid rescue needs the Pilot to laser the rocks while Ops tractor-beams the crystals and fires the jump drive.</p>'
     '<p class="small">Dad is deliberately <b>not a third player</b>: he runs the checklist, starts missions, injects failures (engine fire, cabin leak, power fault, sensor glitch) for the crew to fix, and is the safety observer who alone can move the seats and the pod.</p>', 'cmd')}
  </div>
</div>"""
    return page("Crew roles", cards, "three seats, three different jobs") + page("Why both kids get a hero moment", balanced, "from the game's crew guide")


def ch_layout(D: Data) -> str:
    g = D.geom
    c = g["clearances"]
    eyes = c["eyes"]
    key = md_bullets(md_section("frame/README.md", "Key numbers"))
    rows = [
        ["Footprint (W × L)", f"{L(g['dims']['W'])} × {L(g['dims']['L'])}"],
        ["Casing / tower height", L(g["dims"]["tower_top"])],
        ["Swept height (pod parked up)", f"{L(g['dims']['swept_height'])} → ceiling ≥ 1 950 mm (6' 4.8\")"],
        ["Pod lowest point when parked", f"{L(c['pod_up_lowest_z_over_seats'])} above the floor"],
        ["Kid seat centres", "x = ±460 mm, 920 mm (36.2\") apart, so the 559 mm (22\") TD2220 trim fits between"],
        ["Cradle pivot", f"{L(g['cradle']['pivot_dz'][0])} behind the nose, {L(g['cradle']['pivot_dz'][1])} up"],
        ["Pod pivot (reclined head centre)", f"{L(g['pod']['pivot_dz'][0])} behind the nose, {L(g['pod']['pivot_dz'][1])} up"],
        ["Screens from pod pivot", L(g["pod"]["r_screen"])],
        ["Eye → screen, Pilot (12 yr)", f"{L(eyes['PILOT']['eye_to_screen_mm'])}, gaze {eyes['PILOT']['gaze_elev_deg']:.0f}° up"],
        ["Eye → screen, Ops (6 yr)", f"{L(eyes['OPS']['eye_to_screen_mm'])}, gaze {eyes['OPS']['gaze_elev_deg']:.0f}° up (60-80 mm booster cushion recommended)"],
        ["Dad's dais", "250 mm (9.8\") high; fixed seat, no recline, no pod"],
    ]
    p1 = f"""
<div class="g-wide-l">
  <div>{fig('cad/export/png/overview_flight_front.png', '<b>Flight, from the front.</b> The pod (two monitors, four dash panels, three overhead panels) is down; the TD2220 touchscreen rides in the centre console between the kids.', 'h45', trim=True, pad=0.02)}</div>
  <div>{table(['Dimension', 'Value'], rows, 'kv compact')}
   <p class="tiny dim">Numbers read from <code>frame/generated/geometry.json</code> (written by <code>frame/frame_model.py</code>).</p></div>
</div>"""
    p2 = f"""
<div class="g2">
 {fig('cad/export/png/overview_boarding.png', '<b>1 · Boarding.</b> Seats upright, pod parked up over the kids.', 'h22', trim=True, pad=0.02)}
 {fig('cad/export/png/overview_reclined_pod_up.png', '<b>2 · Reclined.</b> The cradle has tipped back 35°; pod still locked up.', 'h22', trim=True, pad=0.02)}
 {fig('cad/export/png/overview_boarding_front.png', '<b>Boarding, from the front.</b> Side entry gaps in front of the casings.', 'h22', trim=True, pad=0.02)}
 {fig('cad/export/png/overview_dad_view.png', "<b>Dad's view.</b> From Mission Control he sees both kids, their hands and the pod gap, plus the front monitors.", 'h22', trim=True, pad=0.02)}
</div>"""
    p3 = f"""
<div class="g3">
 {fig('cad/export/png/overview_side_boarding.png', '<b>Side section · boarding</b>', 'h25', trim=True, pad=0.02)}
 {fig('cad/export/png/overview_side_reclined.png', '<b>Side section · reclined</b>', 'h25', trim=True, pad=0.02)}
 {fig('cad/export/png/overview_side_flight.png', '<b>Side section · flight</b>', 'h25', trim=True, pad=0.02)}
</div>
<div class="g2">
 {card('<h4>Key numbers (frame README)</h4><ul class="small">' + ''.join(f'<li>{md_html(k, True)}</li>' for k in key[:2]) + '</ul>')}
 {card('<h4>Clearances and sight lines</h4><ul class="small">' + ''.join(f'<li>{md_html(k, True)}</li>' for k in key[-2:]) + '</ul>')}
</div>"""
    return chapter("Cockpit layout and dimensions", p1, "Two kids in front, Dad behind") + page("The cockpit in its states", p2) + page("Side sections and key numbers", p3)


def ch_motion(D: Data) -> str:
    g = D.geom
    cr, pod = g["cradle"], g["pod"]
    move = md_section("frame/README.md", "How it moves")
    paras = [p for p in move.split("\n\n") if not p.strip().startswith("|")]
    p1 = f"""
{fig('cad/export/png/overview_motion_sequence.png', '<b>The flight sequence.</b> 1 boarding (seats upright, pod parked up) → 2 recline (cradle tips back 35°) → 3 flight (pod swings down in front of the crew). Exit is the exact reverse: pod up first, then seats upright.', 'h25', trim=True, pad=0.01)}
{md_tbl(md_table(move), 'compact')}
<p class="small">{md_html(paras[0] if paras else '', True)}</p>"""
    whyp = [p for p in paras[1:]]
    p2 = f"""
<div class="g-12">
  <div>{''.join(card('<p class="small">' + md_html(p, True) + '</p>', 'cmd' if i else '') for i, p in enumerate(whyp[:2]))}</div>
  <div>{fig('frame/drawings/02_side_motion_geometry.png', '<b>Drawing 02 · side view with both motions:</b> cradle and pod pivots, arcs, actuators, gas struts, eye-to-screen lines and clearances.', 'h53', paper=True, maxw=2000, q=88)}</div>
</div>"""
    ca, pa, st = cr["actuator"], pod["actuator"], pod["strut"]
    t_c = [
        ["Design load", f"{KG(cr['mass_kg_design'])}: 2 × 50 kg kids + frame + consoles"],
        ["Gravity torque", f"{NM(min(cr['torque_Nm']))} … {NM(max(cr['torque_Nm']))}: stable on both stops"],
        ["Actuators", f"2 × 12 V, {ca['act_stroke_in']}\" stroke, pin-to-pin {ca['Lmin']:.0f} → {ca['Lmax']:.0f} mm, PUSH to recline"],
        ["Peak force (model)", f"{N(ca['F_each_max'])} each → buy ≥ 1 500 N (330 lbf), self-locking"],
    ]
    t_p = [
        ["Mass / CG radius", f"{KG(pod['mass_kg'])} / {L(pod['cg_radius'])} from the pivot"],
        ["Swing", f"{pod['alpha_up']:.0f}° (parked up) → {pod['alpha_down']:.0f}° (flight)"],
        ["Gravity torque", f"{NM(min(pod['gravity_torque_Nm']))} … {NM(max(pod['gravity_torque_Nm']))}"],
        ["2 gas struts", f"F1 {N(st['F1'])}, progressive to {st['F2']:.0f} N, {st['stroke']:.0f} mm stroke used, ~{st['Lmax']:.0f} mm extended"],
        ["Net torque with struts", f"{NM(min(pod['net_torque_with_struts_Nm']))} … {NM(max(pod['net_torque_with_struts_Nm']))}: rests firmly on whichever stop it is at"],
        ["Actuators", f"2 × 12 V, {pa['act_stroke_in']}\" stroke, {pa['Lmin']:.0f} → {pa['Lmax']:.0f} mm, PULL to raise"],
        ["Force (model)", f"{N(pa['F_each_max'])} each, {N(pa['F_each_strut_failed'])} each if both struts fail → buy ≥ 1 000 N (225 lbf), self-locking"],
    ]
    pod_items = "".join(f"<li>{esc(n)}: {w:.1f} kg</li>" for n, w in pod.get("extra", []))
    p3 = f"""
<div class="g2">
 <div>
  <h3>Cradle · both kid seats</h3>{table(['', ''], t_c, 'kv compact')}
  <h3>Pod · monitors and panels</h3>{table(['', ''], t_p, 'kv compact')}
  <p class="tiny dim">All values from <code>frame/generated/geometry.json</code>. Speed ≤ 10 mm/s (0.4 in/s) at the actuators, ~35-40 s per motion.</p>
 </div>
 <div>{fig('frame/drawings/04_mechanism_interlock.png', '<b>Drawing 04 · mechanism sizing:</b> pod counterbalance (gravity vs. gravity + struts) and cradle torque vs. actuator capacity, plus hard stops, locks and the hardwired interlock.', 'h36', paper=True, maxw=2000, q=88)}
  {card('<h4>Pod mass budget (besides the wood)</h4><ul class="tiny">' + pod_items + '</ul>')}</div>
</div>"""
    drive = md_section("frame/BOM.md", "Motion drive")
    p4 = f"""{md_tbl(md_table(drive), 'compact')}
<div class="note"><h4>Before ordering actuators</h4><p class="small">The geometry only works if the retracted pin-to-pin lengths match: cradle ≈ 364 mm (14.3"), pod ≈ 415 mm (16.3"), ±10 mm. Otherwise move the anchor in <code>frame/frame_model.py</code>, re-run it and re-check the clearances. Insist on <b>self-locking</b> (acme / worm) actuators: they are what holds the pod if a strut fails.</p></div>"""
    return (chapter("Motion system", p1, "Recline, then drop the pod") + page("Geometry: why the pod pivots on the head", p2)
            + page("Forces, actuators and gas struts", p3) + page("Motion drive parts", p4, "from frame/BOM.md"))


def ch_safety(D: Data) -> str:
    g = D.geom
    sc = md_section("frame/README.md", "Safety concept")
    items = [i.strip() for i in re.split(r"\n(?=\d+\. )", "\n" + sc.strip()) if i.strip()]

    def item(n):
        for i in items:
            if i.startswith(f"{n}. "):
                return i[len(f"{n}. "):]
        MISSING.append(f"safety concept item {n} in frame/README.md")
        return ""

    def body(n):
        t = re.sub(r"^\*\*[^*]+\*\*:?\s*", "", item(n))
        return md_html(t[:1].upper() + t[1:])
    p1 = f"""
<p class="lead">A 44 kg (96 lb) pod swinging toward two children is the one part of this project that can really hurt someone.
The answer is layered: <b>steel decides where things stop, struts decide what is heavy, and a person decides when
anything moves</b>, with two hands, from the one seat that can see everyone. No microcontroller and no game code can move a seat or the pod.</p>
<div class="g2">
 {card('<h4>1 · Hard stops define the envelope</h4>' + body(1), 'cmd')}
 {card('<h4>2 · Near-neutral pod</h4>' + body(2), 'cmd')}
 {card('<h4>3 · Slow</h4>' + body(3), 'cmd')}
 {card('<h4>4 · Mechanical locks at both ends + two-hand control</h4>' + body(4), 'cmd')}
</div>"""
    il = item(5)
    il_bul = [re.sub(r"^\s*-\s+", "", x) for x in re.findall(r"^\s+- .*(?:\n\s{5,}(?!-).*)*", il, flags=re.M)]
    il_bul = [re.sub(r"\s+", " ", x) for x in il_bul]
    inter = [
        ["Cradle RECLINE", "FLT", "POD_UP_LOCKED (both pawls), not yet at the CRADLE_RECLINED limit"],
        ["Pod DOWN", "FLT <b>+ release lever</b>", "CRADLE_RECLINED (both sides), not at POD_DOWN; safety edge not pressed"],
        ["Pod UP", "BRD <b>+ release lever</b>", "not at the POD_UP limit"],
        ["Cradle UPRIGHT", "BRD", "POD_UP limit AND POD_UP_LOCKED, not at CRADLE_UPRIGHT"],
        ["Anything", "-", "MOTION key on, E-stop released, 20 A fuse intact"],
    ]
    p2 = f"""
<div class="g-wide-l">
 <div>
  <h3>Hardwired interlock: what may move, and when</h3>
  {table(['Motion', 'Dad holds', 'Only while (limit / lock switches)'], inter, 'compact')}
  <ul class="small">{''.join(f'<li>{md_html(b, True)}</li>' for b in il_bul)}</ul>
 </div>
 <div>
  {card("<h4>Controls at Dad's seat only (CMD_B + lever box)</h4><ul class='small'><li><b>MOTION key</b> (key removable in OFF only) drives a 30 A relay: key out = no motion.</li><li><b>22 mm mushroom E-stop</b>, NC, latching, twist-release.</li><li><b>CREW POS</b> heavy DPDT (ON)-OFF-(ON) toggle, ≥ 15 A at 12 V: FLT / BRD, hold-to-run. Let go = stop.</li><li><b>Pod release lever</b> (Bowden cable, left of the seat) lifts both pawls and closes a micro switch in series with the pod motors.</li><li><b>20 A blade fuse</b> at the 12 V 20 A supply; 4 × 30 A automotive relays as two H-bridges.</li></ul>", 'cmd')}
  <div class="note"><h4>Software only reads</h4><p class="small">Falcon Command reads separate dry contacts (cradle reclined, pod down) so the game can show the state. It never drives the actuators.</p></div>
 </div>
</div>"""
    clr = sorted(g["clearances"]["pod_vs_reclined_kids"], key=lambda r: r["gap_mm"])[:7]
    clr_rows = [[r["kid"], r["body"], r["pod_part"], f"{r['pod_alpha']:.0f}°", f"<b>{r['gap_mm']} mm</b> ({r['gap_mm'] / 25.4:.1f}\")"] for r in clr]
    crs = sorted(g["clearances"]["cradle_vs_structure"], key=lambda r: r["gap_mm"])[:5]
    crs_rows = [[esc(r["moving"]), esc(r["other"]), f"{r['recline_deg']:.1f}°", f"<b>{r['gap_mm']} mm</b>"] for r in crs]
    p3 = f"""
<div class="g-wide-l">
 <div>
  <h3>Smallest pod-to-child gaps over the whole swing</h3>
  {table(['Kid', 'Body part', 'Pod part', 'Pod angle', 'Min. gap'], clr_rows, 'compact', (4,))}
  <h3>Smallest cradle-to-structure gaps over the recline</h3>
  {table(['Moving', 'Fixed', 'Recline', 'Min. gap'], crs_rows, 'compact', (3,))}
  <p class="tiny dim">Worst case = 12-year-old manikin, checked by <code>frame/frame_model.py</code> at every pod and cradle angle.</p>
 </div>
 <div>
  {card('<h4>Pinch-point rules (ISO 13854 style)</h4><p class="small">' + md_html(re.sub(r"^\*\*[^*]+\*\*\s*(\([^)]*\))?:?\s*", "", item(6)), True) + '</p>')}
  {fig('frame/drawings/05_pinch_points_clearances.png', '<b>Drawing 05</b> · every gap that changes with motion, checked against finger 25 / head 120 mm.', 'h2i center', paper=True, maxw=1400, q=88)}
 </div>
</div>"""
    hub = md_section("docs/mechanical/README.md", "Harness hub")
    load = re.search(r"\*\*Load path.*?(?=\n\n)", hub, flags=re.S)
    warn = re.search(r"> \*\*SAFETY - read this\.\*\*(.*?)(?=\n\n|\Z)", hub, flags=re.S)
    warn_txt = re.sub(r"^>\s?", "", warn.group(1), flags=re.M) if warn else ""
    if not warn:
        MISSING.append("harness SAFETY note in docs/mechanical/README.md")
    printing = re.search(r"Print: \*\*PETG\*\*.*?(?=\n\n)", hub, flags=re.S)
    p4 = f"""
<div class="g-wide-r">
 <div>
  {fig('cad/export/png/parts/harness_hub_open.png', "<b>Harness hub, lid off.</b> The kit's own female buckle bodies sit in fixed pockets: shoulders 30° from vertical, lap straps from the sides, crotch/anchor strap out the bottom.", 'h28 center', trim=True, pad=0.03)}
  {card('<h4>Printing the hub</h4><p class="small">' + md_html(printing.group(0) if printing else '', True) + '</p>')}
 </div>
 <div>
  {card('<h4>Load path: the print carries no strap load</h4><p class="small">' + (md_html(re.sub(r'^\*\*Load path[^*]*\*\*:?\s*', '', load.group(0)), True) if load else '') + '</p>', 'ok')}
  <div class="warn"><h4>Plastic-buckle warning: positioning harness only</h4><div class="small">{md_html(warn_txt)}</div></div>
  <p class="tiny dim">A rated metal-buckle 4-point harness is listed as an ALTERNATIVE row in the BOM ({cad(D.bom['alt'])}, not in the totals). Anchor every harness with M10 (3/8") forged eye bolts through the cradle rails or seat-back frames, never plywood alone.</p>
 </div>
</div>"""
    rules = md_bullets(md_section("frame/README.md", "Safety rules"))
    p5 = f"""
<div class="g2">
 <div>
  <div class="warn"><h4>Safety rules · put a copy on the CMD console</h4><ul class="small">{''.join(f'<li>{md_html(r, True)}</li>' for r in rules)}</ul></div>
  {card('<h4>7 · Cables across pivots</h4><div class="small">' + body(7) + '</div>')}
  {card('<h4>First power-up of the motion system</h4><p class="small">Test with <b>nobody seated</b>: every limit, every lock, the E-stop, the key, lever released = no pod motion, safety edge = stop. Then re-check every gap on drawing 05 with a 25 mm (1") dowel and a 120 mm (4.7") ball at both ends of both motions.</p>', 'cmd')}
 </div>
 <div>
  {fig('docs/electronics/04_seat_actuator.png', '<b>Electronics diagram 04 · crew-position circuit v0.2.</b> 20 A fuse, key + E-stop drop the MOTION relay, CREW POS hold-to-run feeds the relay coils only through the interlock (pod up + locked, cradle reclined L + R, release lever, pod-chin safety edge), 4 relays as two H-bridges (cradle, pod), NC limit switches with 1N5408 drive-back diodes, and three isolated read-only senses (cradle reclined, pod down + locked, optional pod up + locked) for Falcon Command.', 'h33', paper=True, maxw=1800, q=88)}
 </div>
</div>"""
    return (chapter("Safety", p1, "Read this chapter before building anything that moves")
            + page("Interlock, key, E-stop and two-hand control", p2) + page("Clearances and pinch points", p3)
            + page("Harness and load path", p4) + page("Rules, checks and the hold-to-run circuit", p5))


def ch_frame(D: Data) -> str:
    intro = md_section("frame/README.md", "The Filament Falcon - wooden frame").split("![")[0]
    p1 = f"""
<p class="lead">{md_html(intro, True)}</p>
<div class="g2">
 {fig('frame/drawings/01_front_elevation.png', '<b>Drawing 01 · front elevation in FLIGHT:</b> casings, pod, seats and monitor positions.', 'h4i center', paper=True, maxw=1600, q=88)}
 {fig('frame/drawings/03_plan_view.png', "<b>Drawing 03 · plan:</b> seats at x = ±460 mm, consoles, casings, actuators, Dad's dais.", 'h4i center', paper=True, maxw=1600, q=88)}
</div>"""
    p2 = f"""
<div class="g-wide-l">
 {fig('frame/drawings/06_pod_cheek_template.png', '<b>Drawing 06 · pod cheek template</b>, full size (print tiled, trace onto plywood). Two layers of 18 mm ply per cheek, glued, with steel crank and latch plates bolted through.', 'h45', paper=True, maxw=1800, q=88)}
 {fig('frame/drawings/07_panel_bay_detail.png', '<b>Drawing 07 · panel bay detail:</b> how a printed panel bolts to the plywood rails on the 40 mm grid with M5 T-nuts.', 'h3i', paper=True, maxw=1600, q=88)}
</div>"""
    grp = OrderedDict()
    for r in D.cut:
        e = grp.setdefault((r["group"], r["material"]), {"n": 0, "len": 0.0, "area": 0.0})
        e["n"] += 1
        e["len"] += float(r["length_mm"] or 0)
        e["area"] += float(r["length_mm"] or 0) * float(r["width_mm"] or 0) / 1e6
    rows = [[g, esc(m), str(v["n"]), f"{v['len'] / 1000:.1f} m ({v['len'] / 304.8:.0f} ft) of 2x4" if v["area"] == 0 else
             f"{v['area']:.2f} m² ({v['area'] * 10.764:.0f} sq ft)"] for (g, m), v in grp.items()]
    cl = rd("frame/cut_list.md")
    boards = re.search(r"\*\*2x4 boards:\*\*(.*?)\n", cl)
    sheets = re.findall(r"^- (\d+ mm ply[^\n]*)$", cl, flags=re.M)
    lumber = md_section("frame/BOM.md", "Lumber and sheet goods")
    p3 = f"""
<div class="g2">
 <div>
  <h3>Cut list by group and material</h3>
  {table(['Group', 'Material', 'Pieces', 'Total length / area'], rows, 'compact', (2, 3), total=['All', '', str(len(D.cut)), ''])}
  <p class="small">{md_html('**2x4 boards:**' + boards.group(1), True) if boards else ''}</p>
  <ul class="small">{''.join(f'<li>{md_html(s, True)}</li>' for s in sheets)}</ul>
  <p class="tiny dim">Summarised from <code>frame/cut_list.csv</code>; every piece with its notes is in <code>frame/cut_list.md</code>. Groups: fixed = base, nose box, towers/casings, ramp, Dad's dais; cradle = reclining kid-seat frame; pod = rotating instrument pod.</p>
 </div>
 <div><h3>Lumber and sheet goods to buy</h3>{md_tbl(md_table(lumber), 'compact')}
  <div class="note"><h4>Measure your lumber first</h4><p class="small">2x4 = 38 × 89 mm (1.5" × 3.5") actual. Check real sizes and adjust <code>frame_model.py</code> before cutting; re-running it regenerates the cut list, the drawings and this book.</p></div></div>
</div>"""
    steps = md_bullets(md_section("frame/README.md", "Assembly steps"))
    half = (len(steps) + 1) // 2
    p4 = f"""
<div class="g2">
 <ol class="small">{''.join(f'<li>{md_html(s, True)}</li>' for s in steps[:half])}</ol>
 <ol class="small" start="{half + 1}">{''.join(f'<li>{md_html(s, True)}</li>' for s in steps[half:])}</ol>
</div>"""
    return (chapter("Wooden frame", p1, "2x4 lumber and plywood on a floor-level base") + page("Templates and panel bays", p2)
            + page("Cut list summary", p3) + page("Assembly steps", p4, "from frame/README.md"))


def ch_panels(D: Data) -> str:
    mech = "docs/mechanical/README.md"
    panels_txt = md_section(mech, "Panels")
    first = panels_txt.split("\n\n")[0]
    boxes = md_section(mech, "Back side: LED light boxes")
    bolt = md_section(mech, "How a panel bolts to the frame")
    bparts = boxes.split("\n\n")
    p1 = f"""
<div class="g-wide-r">
 <div>
  {card('<h4>Backlit through-letters</h4><p class="small">' + md_html(first, True) + ' Lettering is Barlow Condensed Black (SIL OFL), from <code>cad/fonts/</code>.</p>')}
  {card('<h4>LED light boxes on the back</h4><p class="small">' + md_html(bparts[0], True) + '</p>')}
  {card('<h4>Light-leak check</h4><p class="small">' + md_html(bparts[-1], True) + '</p>')}
 </div>
 <div>
  <div class="g2">
   {fig('cad/export/png/panels/OPS_DASH_A_front.png', '<b>Front:</b> dark body, white letters through the full 3 mm.', 'h2i center', trim=True, pad=0.04, maxw=1000)}
   {fig('cad/export/png/panels/OPS_DASH_A_back.png', '<b>Back:</b> one light box per label, strip ledges and wire notches.', 'h2i center', trim=True, pad=0.04, maxw=1000)}
  </div>
  {card('<h4>Mounting grid: how a panel bolts to the frame</h4><ol class="small">' + ''.join(f'<li>{md_html(s, True)}</li>' for s in md_bullets(bolt)) + '</ol>')}
 </div>
</div>"""
    ptab = md_table(panels_txt)
    files = panels_txt.split("Files per panel")[1].split("### Back side")[0] if "Files per panel" in panels_txt else ""
    fb = md_bullets(files)
    p2 = f"""
<div class="g-wide-l">
 <div>{md_tbl(ptab, 'compact')}
  <p class="small">{len(D.labels.get('labels', []))} backlit labels in total, each listed with id, panel, text, position and strip order in <code>shared/panel_labels.json</code>. The LED strip visits the panels in this order:</p>
  <p>{' → '.join(f'<span class="chip">{esc(p)}</span>' for p in D.labels.get('panel_order', []))}</p>
 </div>
 <div>
  <h3>Multi-material or inserts?</h3>
  {''.join(card('<p class="small">' + md_html(b, True) + '</p>') for b in fb[:3])}
 </div>
</div>"""
    out = chapter("3D-printed panels", p1, "Backlit lettering, light boxes, one mounting grid") + page("All eleven panels", p2, "and the two ways to print them")
    by_panel = defaultdict(list)
    for lab in D.labels.get("labels", []):
        by_panel[lab["panel"]].append(lab)
    seg_by_panel = defaultdict(int)
    for s in D.segs.get("segments", {}).values():
        seg_by_panel[s.get("panel")] += s.get("count", 0)

    def role_of(pid):
        return "pilot" if pid.startswith("PILOT") else "ops" if pid.startswith("OPS") else "cmd"
    for p in D.labels.get("panels", []):
        pid = p["id"]
        sb = D.switch.get(pid, {})
        rows = [[esc(r[0]), md_html(r[1], True), md_html(r[2], True)] for r in sb.get("rows", [])]
        chips = "".join(f'<span class="chip">{esc(l["text"])}<i>{l.get("est_leds_60_per_m", "")}</i></span>' for l in by_panel[pid])
        val = D.val.get("panels", {}).get(pid, [])
        vol = sum(e["volume_cm3"] for e in val if "multi-material body" in e["name"] or e["name"].endswith(" letters"))
        ok = all(e.get("watertight") and not e.get("problems") for e in val) if val else None
        check = '<span class="pass">watertight, no problems</span>' if ok else ('<span class="fail">see validation report</span>' if ok is False else 'n/a')
        loc = esc(p["location"])
        inner = f"""
<div class="g-wide-l">
 <div>
  {fig(f'cad/export/png/panels/{pid}_front.png', f'<b>{esc(pid)} · front.</b> {esc(p["title"])}.', 'h36 center', trim=True, pad=0.03, maxw=1300)}
  <div class="g2">
   {fig(f'cad/export/png/panels/{pid}_back.png', '<b>Back:</b> light boxes behind every label.', 'h15 center', trim=True, pad=0.03, maxw=900)}
   <table class="kv compact"><tbody>
     <tr><td>Nominal size</td><td>{p['nominal_w_mm']} × {p['nominal_h_mm']} mm ({p['nominal_w_mm'] / 25.4:.1f}" × {p['nominal_h_mm'] / 25.4:.1f}")</td></tr>
     <tr><td>Labels / LEDs</td><td>{len(by_panel[pid])} labels · {seg_by_panel.get(pid, 0)} LEDs (placeholder map)</td></tr>
     <tr><td>Print volume</td><td>{vol:.0f} cm³ (body + letters)</td></tr>
     <tr><td>3MF check</td><td>{check}</td></tr>
   </tbody></table>
  </div>
 </div>
 <div>
  {card(f'<h4>Where it goes</h4><p class="small">{loc[:1].upper() + loc[1:]}.</p>', role_of(pid))}
  <h3>Controls</h3>
  {table(['Qty', 'Part', 'Used for'], rows, 'compact') if rows else '<p class="dim small">No switch list found.</p>'}
  <h4>Backlit labels <span class="dim tiny">(LED estimate at 60/m)</span></h4>
  <p>{chips}</p>
 </div>
</div>"""
        out += page(f"Panel {pid}", inner, esc(p["title"]), toc=True)
    ps = md_section(mech, "Print settings")
    ps_parts = [x for x in ps.split("\n\n") if not x.strip().startswith("|")]
    tot = md_table(md_section("docs/mechanical/switch_bom.md", "Totals"))
    nparts = len(D.val.get("parts", {}))
    npanel = sum(len(v) for v in D.val.get("panels", {}).values())
    allok = all(e.get("watertight") and not e.get("problems") for v in D.val.get("panels", {}).values() for e in v) and \
        all(e.get("watertight") and not e.get("problems") for e in D.val.get("parts", {}).values())
    p_set = f"""
<div class="g-wide-l">
 <div>{md_tbl(md_table(ps), 'compact')}
  {card('<h4>Multi-material and bed size</h4><p class="small">' + ' '.join(md_html(x, True) for x in ps_parts) + '</p>')}
 </div>
 <div>
  <h3>Switches for all panels</h3>
  {md_tbl(tot, 'compact')}
  <div class="note ok"><h4>3MF validation</h4><p class="small">{npanel} panel meshes and {nparts} part files checked (watertight, volume, footprint, triangle counts, lib3mf read-back): {'<span class="pass">all pass</span>' if allok else '<span class="fail">some problems, see cad/export/validation_report.json</span>'}.</p></div>
 </div>
</div>"""
    out += page("Print settings and switch totals", p_set)
    return out


def ch_parts(D: Data) -> str:
    P = "cad/export/png/parts/"
    items = [
        ("throttle_quadrant.png", "Throttle quadrant", "10 k linear pot, M6 × 30 pivot, red grip; screws into the side-console rails."),
        ("gear_lever.png", "Landing-gear lever", "2 × KW11 micro switches, M4 × 40 pivot, wheel knob."),
        ("joystick_housing.png", "Joystick housing + adapter", "4 × M5 on the 120 mm grid; radial slots fit bolt circles 44-88 mm."),
        ("harness_hub.png", "Harness hub (closed)", "PETG, 6 perimeters; houses the buckle bodies and the steel load ring."),
        ("touchscreen_bezel.png", "TD2220 trim ring", "6 half-lapped pieces ≤ 200 mm; never overlaps the optical-touch glass."),
        ("monitor_mount.png", "Monitor standoff", "VESA 75 + 100 patterns, 4 × M6 through the pod back sheet, plus a steel safety cable."),
        ("toggle_guard.png", "Missile-switch guard", "ENG ARM, JUMP ARM, EJECT; hinge pin = 24 mm of 1.75 mm filament."),
        ("engage_button_collar.png", "ENGAGE button collar", "Raised ring around the 22 mm JUMP ENGAGE button."),
        ("esp32_enclosure.png", "ESP32-S3 enclosure", "70 × 90 mm perfboard carrier, USB-C slot, engraved lid per board."),
        ("pivot_cable_clamp.png", "Pivot cable clamp", "Strain relief on both sides of every pivot crossing (30 mm bore)."),
        ("cable_clips.png", "Cable clips", "6/10/16/24 mm bundle clips + flat LED-strip clip, one #8 screw each."),
        ("limit_switch_mount.png", "Limit-switch mount", "V-15 roller micro switch, slotted ±10 mm for adjustment."),
    ]

    def grid(sub):
        return '<div class="g3">' + "".join(fig(P + f, f"<b>{t}.</b> {d}", "h18 center", trim=True, pad=0.04, maxw=900) for f, t, d in sub) + "</div>"
    sec = md_section("docs/mechanical/README.md", "Other printed parts")
    tab = md_table(sec)
    notp = re.search(r"\*\*Not printed:\*\*.*?(?=\n\n|\Z)", sec, flags=re.S)
    fil = D.filament
    p3 = f"""{md_tbl(tab, 'compact')}
<div class="g2">
 {card('<p class="small">' + (md_html(notp.group(0), True) if notp else '') + '</p>')}
 {card(f'<h4>Filament estimate (bom/tools)</h4><p class="small">Black ≈ <b>{fil.get("black", {}).get("kg", "?")} kg</b> ({fil.get("black", {}).get("cm3", "?")} cm³) and white ≈ <b>{fil.get("white", {}).get("kg", "?")} kg</b> of PETG, incl. 15 % for purge, brims and failed prints. The BOM buys 6 × 1 kg black and 1 × 1 kg white.</p>')}
</div>"""
    return (chapter("Other printed parts", grid(items[:6]), "Levers, housings, mounts and the harness hub") + page("Small parts", grid(items[6:]))
            + page("Printed-parts list", p3, "from docs/mechanical/README.md"))


def ch_displays(D: Data) -> str:
    dm = "docs/mechanical/displays.md"
    t1 = md_table(rd(dm))
    mm_ = md_section(dm, "Monitor mounts").split("\n\n")
    td = md_section(dm, "TD2220 centre console").split("\n\n")
    gpu = md_section(dm, "GPU outputs and cabling")
    gp = [x for x in gpu.split("\n\n") if not x.strip().startswith("|")]
    p1 = f"""
{md_tbl(t1, 'compact')}
<div class="g3">
 {card('<h4>Monitor mounts (pod)</h4><p class="small">' + md_html(mm_[0], True) + '</p>')}
 {card('<h4>Parked face-down</h4><p class="small">' + md_html(mm_[1] if len(mm_) > 1 else '', True) + '</p>', 'cmd')}
 {card('<h4>TD2220 centre console</h4><p class="small">' + md_html(td[0], True) + '</p>')}
</div>"""
    p2 = f"""
<div class="g-wide-l">
 <div>
  <p class="small">{md_html(gp[0], True)}</p>
  {md_tbl(md_table(gpu), 'compact')}
  <p class="small">{md_html(gp[1] if len(gp) > 2 else '', True)}</p>
 </div>
 <div>
  {card('<h4>Cables across the pivots</h4><p class="small">' + md_html(gp[-1], True) + '</p>')}
  {card('<h4>Trim ring and touch</h4><p class="small">' + md_html(td[1] if len(td) > 1 else '', True) + '</p>')}
  {card('<h4>Fit between the kids</h4><p class="small">' + md_html(td[2] if len(td) > 2 else '', True) + '</p>')}
 </div>
</div>"""
    return chapter("Displays and cabling", p1, "Two curved window monitors, a touchscreen and the Commander monitor") + page("GPU outputs and cable routing", p2, "RX 6800 XT: 2 × DP, HDMI, USB-C")


def ch_electronics(D: Data) -> str:
    er = "docs/electronics/README.md"
    src = rd(er)
    why = re.search(r"Why ESP32-S3:.*?(?=\n\n)", src, flags=re.S)
    ctl = re.search(r"The control set matches.*?(?=\n\n)", src, flags=re.S)
    p1 = f"""
<div class="g-wide-l">
 <div>
  {md_tbl(md_table(src), 'compact')}
  {card('<h4>Controls as the CAD panels define them</h4><p class="small">' + (md_html(ctl.group(0), True) if ctl else '') + '</p>')}
 </div>
 <div>
  {card('<h4>Why the ESP32-S3?</h4><p class="small">' + (md_html(re.sub(r'^Why ESP32-S3:\s*', '', why.group(0)), True) if why else '') + '</p>', 'cmd')}
  {card('<h4>One firmware, three boards</h4><p class="small">PlatformIO + Arduino + TinyUSB. Each board is a USB HID joystick with 8 × 16-bit axes and 64 buttons; Falcon Command is also a USB CDC serial port that drives the single WS2812B strip. Which switch is which button lives in <code>firmware/include/config_*.h</code>; <code>shared/input_map.json</code> and the 02 wiring diagrams are generated from those headers.</p>')}
  {card("<h4>Switch inputs</h4><p class='small'>Switches go through daisy-chained 74HC165 shift registers (3 Pilot, 3 Ops, 4 Command), analog axes to ADC1 pins at 3.3 V. The last chip's SER pin is tied to 3V3, so the firmware can tell when no chain is connected and falls back to joystick-only mode.</p>")}
 </div>
</div>"""
    simple = md_section(er, "Simple joystick test")
    calib = [x for x in simple.split("\n\n") if x.startswith("**Calibrate**")]
    p2 = f"""
<div class="g-wide-l">
 {fig('docs/electronics/01_simple_joystick.png', '<b>Diagram 01 · start here.</b> One 3-axis joystick + button straight to a DevKitC-1, and how to identify unlabeled wires with a multimeter.', 'h5i', paper=True, maxw=2000, q=88)}
 <div>
  {md_tbl(md_table(simple), 'compact')}
  {card('<h4>Calibrate</h4><p class="small">' + (md_html(re.sub(r'^\*\*Calibrate\*\*\s*', '', calib[0]), True) if calib else '') + '</p>', 'cmd')}
 </div>
</div>"""
    diag = [
        ("02_pilot_wiring.png", "Falcon Pilot wiring", "74HC165 chain with every switch named, joystick, throttle pot and the FLIGHT ASSIST encoder."),
        ("02_ops_wiring.png", "Falcon Ops wiring", "74HC165 chain for power toggles, payload and jump controls, RCS joystick and OPS MODE encoder."),
        ("02_command_wiring.png", "Falcon Command wiring", "Dad's panel + overhead chips (over a CAT5/6 cable), MISSION and DIMMER encoders, LED data line and the three read-only crew-position senses (GPIO39/40/41)."),
    ]
    dpages = "".join(page(t, fig("docs/electronics/" + f, f"<b>Diagram {f[:2]} · {t}.</b> {d}", "h5i center", paper=True, maxw=2300, q=88),
                          "generated from the firmware config headers", toc=True) for f, t, d in diag)
    led = md_section(er, "LED backlighting")
    p_led = f"""
<div class="g-wide-l">
 {fig('docs/electronics/03_ws2812_power.png', '<b>Diagram 03 · LED strip power:</b> 5 V supply sizing, power injection at start/middle/end, 1000 µF at the strip input, 330 Ω data resistor, 74AHCT125 level shifter, common ground.', 'h5i', paper=True, maxw=2000, q=88)}
 <div>{md_tbl(md_table(led), 'compact')}</div>
</div>"""
    pins = md_section(er, "Common pin plan")
    beh = md_bullets(md_section("firmware/README.md", "Behaviour"))
    p4 = f"""
<div class="g2">
 <div>{md_tbl(md_table(pins), 'compact')}<p class="tiny dim">{md_html(pins.split(chr(10) + chr(10))[-1], True)}</p></div>
 <div><h3>Firmware behaviour</h3><ul class="small">{''.join(f'<li>{md_html(b, True)}</li>' for b in beh)}</ul></div>
</div>"""
    ls = "docs/electronics/linux_setup.md"

    def code(sec):
        m = re.search(r"```(?:bash)?\n(.*?)```", md_section(ls, sec), flags=re.S)
        return f"<pre>{esc(m.group(1).rstrip())}</pre>" if m else ""
    win = md_bullets(md_section(ls, "7. Windows check"))
    p5 = f"""
<div class="g3">
 <div><h4>1 · udev rule (once)</h4>{code('1. udev')}<h4>2 · Is it enumerating?</h4>{code('2. Is it')}</div>
 <div><h4>3 · Test the joystick</h4>{code('3. Test the joystick')}<h4>4 · Test the LEDs</h4>{code('4. Test Falcon')}</div>
 <div><h4>Flashing</h4><ul class="tiny">{''.join(f'<li>{md_html(b, True)}</li>' for b in md_bullets(md_section(ls, '6. Flashing')))}</ul>
  <h4>Windows</h4><ol class="tiny">{''.join(f'<li>{md_html(b, True)}</li>' for b in win)}</ol></div>
</div>"""
    overview = ("<p class='lead'>The full wiring diagrams for each board follow on the next pages. They are generated from the firmware "
                "config headers by <code>docs/electronics/src/make_all.py</code>, so they always match the button numbers the game expects.</p>"
                + '<div class="g3">' + "".join(fig("docs/electronics/" + f, f"<b>{t}</b>", "h28 center", paper=True, maxw=900, q=80) for f, t, d in diag) + "</div>")
    p_parts = f"""
<div class="g2">
 <div><h3>Controllers and logic</h3>{md_tbl(md_table(md_section(er, 'Controllers and logic')), 'compact')}</div>
 <div><h3>Panel controls</h3>{md_tbl(md_table(md_section(er, 'Panel controls')), 'compact')}</div>
</div>"""
    return (chapter("Electronics", p1, "Three ESP32-S3 USB joysticks") + page("Electronics parts", p_parts, "from docs/electronics/README.md (counts include spares)")
            + page("First test: one joystick, one board", p2)
            + dpages + page("LED strip power", p_led)
            + page("Pin plan and firmware behaviour", p4) + page("Linux Mint and Windows setup", p5, "from docs/electronics/linux_setup.md"))


def ch_led(D: Data) -> str:
    s = D.segs.get("strip", {})
    segs = D.segs.get("segments", {})
    status_leds = [k for k, v in segs.items() if "5mm" in v.get("type", "")]
    per = OrderedDict((p, [0, 0, 0]) for p in D.labels.get("panel_order", []))
    for v in segs.values():
        e = per.setdefault(v.get("panel", "?"), [0, 0, 0])
        e[1 if "5mm" in v.get("type", "") else 0] += 1
        e[2] += v.get("count", 0)
    used = sum(v.get("count", 0) for v in segs.values())
    rows = [[f'<b>{esc(p)}</b>', str(a), str(b), str(c)] for p, (a, b, c) in per.items()]
    p1 = f"""
<div class="g-wide-r">
 <div>
  <div class="stats" style="grid-template-columns: 1fr 1fr">
   {stat(s.get('total_leds', '?'), f"LEDs on the strip ({s.get('type', '')}, {s.get('color_order', '')}, {s.get('leds_per_meter', '')}/m)")}
   {stat(len(segs), 'named segments: backlit labels + 5 mm status LEDs')}
   {stat(len(status_leds), '5 mm WS2812D-F5 status LEDs spliced into the same line')}
   {stat(used, 'LEDs assigned; the rest are hops between panels')}
  </div>
  {card('<h4>One data line, many panels</h4><p class="small">Falcon Command drives the whole strip from GPIO21 through a 74AHCT125 level shifter. The game never talks to LEDs directly: it sends short text lines over USB serial (through a small Python bridge, because Godot has no serial API) and the firmware renders at 60 fps with global brightness, the DIMMER knob and a current limit (capped at 8 A) on top.</p>')}
  <div class="note"><h4>Placeholder map</h4><p class="tiny">{md_html(D.segs.get('_comment', ''), True)}</p></div>
 </div>
 <div>
  <h3>Segments per panel, in strip order</h3>
  {table(['Panel', 'Labels', 'Status LEDs', 'LEDs'], rows, 'compact', (1, 2, 3), total=['Total', str(sum(r[0] for r in per.values())), str(sum(r[1] for r in per.values())), str(used)])}
  <h4>Boot and idle</h4><ol class="small">{''.join(f'<li>{md_html(b, True)}</li>' for b in md_bullets(md_section('shared/led_protocol.md', 'Boot / idle')))}</ol>
 </div>
</div>"""
    cmds = md_section("shared/led_protocol.md", "Commands")
    modes = cmds.split("`MODE` is one of:")[-1]
    ex = re.search(r"```\n(.*?)```", md_section("shared/led_protocol.md", "Example session"), flags=re.S)
    framing = md_bullets(md_section("shared/led_protocol.md", "Framing"))
    p2 = f"""
<div class="g-wide-l">
 <div>{md_tbl(md_table(cmds), 'compact')}</div>
 <div>
  <h4>Modes</h4>{md_tbl(md_table(modes), 'compact')}
  <h4>Example session</h4><pre>{esc(ex.group(1).rstrip()) if ex else ''}</pre>
  <h4>Framing</h4><ul class="tiny">{''.join(f'<li>{md_html(b, True)}</li>' for b in framing[:4])}</ul>
 </div>
</div>"""
    return chapter("LED lighting system", p1, "Every label glows, and the game picks the colour") + page("The serial LED protocol", p2, "game → Falcon Command, shared/led_protocol.md")


SHOTS = {   # screenshots per mission id (docs/game/screenshots), with captions
    "launch": [("01_launch_pad_chase.jpg", "On the pad: lattice tower and countdown banner."), ("03_launch_ascent_chase.jpg", "Ascent, chase view."),
               ("04_launch_ascent_cockpit.jpg", "Ascent from the Pilot's window: minimal HUD.")],
    "docking": [("08_docking_chase.jpg", "Final approach to the station port."), ("07_docking_ops.jpg", "Docking from the window view."),
                ("05_orbit_station_tiled.jpg", "Station in orbit, dev-mode tiled view.")],
    "lunar": [("09_lunar_descent.jpg", "Lunar descent from the window."), ("10_lunar_chase.jpg", "Hovering down toward the beacon.")],
    "asteroids": [("11_asteroid_field.jpg", "Inside the asteroid field."), ("12_asteroid_chase.jpg", "Threading between the rocks.")],
    "reentry": [("13_reentry_plasma_chase.jpg", "Reentry plasma: SHIELDS!"), ("14_reentry_plasma_cockpit.jpg", "Plasma from the cockpit."),
                ("15_runway_approach.jpg", "Runway approach."), ("16_runway_chase.jpg", "Gliding down to the runway.")],
    "sandbox": [("06_orbit_station_left.jpg", "Free flight near the station."), ("17_mission_complete.jpg", "Mission complete: score, stars and celebration.")],
}


def ch_game(D: Data) -> str:
    gr = "docs/game/README.md"
    intro = md_section(gr, "The Filament Falcon: game").split("![")[0]
    gfx = md_bullets(md_section(gr, "Graphics notes"))
    disp = md_section(gr, "3. The four screens")
    dparts = [x for x in md_section(gr, "Which screen gets which role").split("\n\n")
              if x.strip() and not x.strip().startswith(("|", "```", "1.", "-"))]
    p1 = f"""
<div class="g-wide-r">
 <div>
  <p class="lead">{md_html(intro, True)}</p>
  {card('<h4>Engine</h4><p class="small">Godot 4 (README: 4.7.x stable, standard build), Forward+ renderer on Vulkan (Mesa RADV on the RX 6800 XT), GDScript. <code>godot --path game</code> opens cockpit mode (one fullscreen window per screen) when it finds ≥ 3 screens, otherwise a tiled dev mode. Four windows: left and right out-the-window views, the kids\' touch console and the Commander screen (with three screens the Commander becomes a console tab).</p>')}
  <h4>Graphics notes</h4><ul class="tiny">{''.join(f'<li>{md_html(b, True)}</li>' for b in gfx[:3])}</ul>
 </div>
 <div>
  {fig('docs/game/screenshots/02_cockpit_tiled_briefing.jpg', '<b>Dev mode:</b> both window views, the kids\' console and the Commander screen tiled in one window.', 'h22')}
  {md_tbl(md_table(disp), 'compact')}
  <p class="tiny">{" ".join(md_html(x, True) for x in dparts[:3])}</p>
 </div>
</div>"""
    sim = rd("game/scripts/sim/ship_sim.gd")
    doc = [l[2:].strip() for l in sim.splitlines()[:14] if l.startswith("##")]

    def var(name):
        m = re.search(rf"^var {name} := ([\d.]+)", sim, flags=re.M)
        if not m:
            MISSING.append(f"ship_sim.gd var {name}")
            return 0.0
        return float(m.group(1))
    params = [
        ["Dry mass / max fuel", f"{var('dry_mass') / 1000:.0f} t / {var('fuel_max') / 1000:.0f} t"],
        ["Main engine", f"{var('main_thrust') / 1000:.0f} kN, Isp {var('main_isp_sl'):.0f} s (sea level) to {var('main_isp_vac'):.0f} s (vacuum)"],
        ["Booster (launch)", f"{var('booster_thrust') / 1000:.0f} kN, {var('booster_fuel_max') / 1000:.0f} t propellant"],
        ["RCS", f"{var('rcs_force') / 1000:.1f} kN, {var('mono_max'):.0f} kg monopropellant"],
        ["Rotation", f"reaction wheels {var('rw_torque') / 1000:.0f} kN·m + RCS {var('rcs_torque') / 1000:.0f} kN·m; max 22°/s pitch/yaw, 40°/s roll"],
    ]
    crew = md_section(gr, "7. Crew guide")
    fa = md_bullets(crew.split("**Flight assist (the knob):**")[-1].split("The physics")[0])
    before = md_bullets(crew.split("**Before every mission:**")[-1].split("**Flight assist")[0])
    p2 = f"""
<div class="g2">
 <div>
  {card('<h4>Newtonian 6-DOF flight model (ship_sim.gd)</h4><ul class="small">' + ''.join(f'<li>{esc(d.lstrip("- "))}</li>' for d in doc[1:] if d) + '</ul>')}
  {table(['Ship parameter', 'Value'], params, 'kv compact')}
  {card('<h4>Crew tips (crew guide)</h4><ul class="small">' + ''.join(f'<li>{md_html(b, True)}</li>' for b in md_bullets(crew.split("Tips:")[-1].split("## ")[0])) + '</ul>')}
 </div>
 <div>
  {card('<h4>Flight-assist knob (Pilot)</h4><ul class="small">' + ''.join(f'<li>{md_html(b, True)}</li>' for b in fa) + '</ul><p class="small"><em>The physics is real. The assists make it easy.</em></p>', 'pilot')}
  {card('<h4>Before every mission</h4><ol class="small">' + ''.join(f'<li>{md_html(b, True)}</li>' for b in before) + '</ol>', 'cmd')}
 </div>
</div>"""
    out = chapter("The game", p1, "Godot 4, four screens, six missions") + page("Flight model", p2, "real physics, friendly assists")
    flight = {t["id"]: t for t in D.tests.get("flight", [])}
    for i, m in enumerate(D.missions):
        hero = D.hero[i] if i < len(D.hero) else ["", "", "", "", ""]
        objs = "".join(f'<li><span class="badge b-{r}">{r}</span>{esc(t)}</li>' for t, r in m["objectives"])
        t = flight.get(m["id"])
        tline = (f'<p class="small"><span class="{"pass" if t["ok"] else "fail"}">{"PASS" if t["ok"] else "FAIL"}</span> in the flight test: the robot crew completed '
                 f'{t.get("step", "?")} objectives in {t.get("mission_time", "?")}, {t.get("stars", "?")} stars, hull {t.get("hull", "?")}, max {t.get("maxG", "?")} g.</p>') if t else ""
        sh = SHOTS.get(m["id"], [])
        if len(sh) > 2:
            grid = '<div class="g2">' + "".join(fig("docs/game/screenshots/" + s, c, "h2i", maxw=1100, q=80) for s, c in sh[:4]) + "</div>"
        else:
            grid = "".join(fig("docs/game/screenshots/" + s, c, "h25", maxw=1300, q=80) for s, c in sh)
        inner = f"""
<div class="g-wide-r">
 <div>
  <p class="lead">{esc(m['briefing'])}</p>
  {card(f'<h4>Pilot</h4><p class="small">{esc(m["pilot"])}</p><p class="tiny dim">Hero moment: {md_html(hero[3], True)}</p>', 'pilot')}
  {card(f'<h4>Ops</h4><p class="small">{esc(m["ops"])}</p><p class="tiny dim">Hero moment: {md_html(hero[4], True)}</p>', 'ops')}
  <h4>Objectives, in order</h4><ol class="small">{objs}</ol>
  {tline}
 </div>
 <div>{grid}</div>
</div>"""
        out += page(f"Mission {i + 1} · {m['title'].title()}", inner, esc(m["tagline"]), cls="mission")
    pages = [("18_console_flight.jpg", "FLIGHT", "attitude ball, speed/altitude tapes, fuel; Pilot and Ops controls, live camera"),
             ("19_console_nav.jpg", "NAV", "orbit map, steer-to vectors, nav target"),
             ("20_console_systems.jpg", "SYSTEMS", "power distribution, ship health, the fault list for MASTER CAUTION"),
             ("21_console_cameras.jpg", "CAMERAS", "docking, arm and chase camera feeds"),
             ("22_console_checklist.jpg", "CHECKLIST", "the overhead start-up switches, green when done in order")]
    tp = '<div class="g3">' + "".join(fig("docs/game/screenshots/" + f, f"<b>{n}</b> · {d}", "h15", maxw=900, q=78) for f, n, d in pages) + \
        card('<h4>Made for 22" touch, only for the kids</h4><p class="tiny">Buttons 76-100 px (19-25 mm), text 22-34 px, readable from the seats. A task strip shows each kid\'s current job; MASTER CAUTION flashes at the top. When a Falcon board is connected, its physical switches win and the matching touch buttons only mirror them. Touch is mapped to this monitor by <code>game/tools/setup_displays.sh</code> (run by <code>run.sh</code>).</p>') + "</div>"
    out += page("Kids' touchscreen console", tp, "ViewSonic TD2220 in the centre console")
    cpages = [("23_commander_mission_control.jpg", "MISSION CONTROL", "missions, start/pause/restart, failures, score; orbit map, warp; both kids' tasks, ship health"),
              ("24_commander_briefing.jpg", "BRIEFING", "briefing, both jobs, every objective, read aloud"),
              ("25_commander_training.jpg", "TRAINING", "difficulty, skip checklist, assist override, voice"),
              ("26_commander_controls.jpg", "CONTROLS", "live test of every switch and axis, devices, LED test"),
              ("27_commander_setup.jpg", "SETUP", "screen roles, quality, FPS cap, vsync, geometry, LED bridge"),
              ("28_console_commander_tab.jpg", "3-SCREEN FALLBACK", "no Commander monitor: the same UI as a console tab (Esc)")]
    tc = '<div class="g3">' + "".join(fig("docs/game/screenshots/" + f, f"<b>{n}</b> · {d}", "h15", maxw=900, q=78) for f, n, d in cpages) + "</div>"
    out += page("Commander screen", tc, "31.5\" monitor at dad's seat, mouse and keyboard")
    vpages = [("29_console_virtual_panels.jpg", "VIRTUAL PANELS", "Pilot and Ops boards unplugged: their real panels on the touchscreen, with touch sticks"),
              ("30_console_checklist_overhead.jpg", "CHECKLIST + OVERHEAD", "Falcon Command unplugged: the three overhead panels on screen"),
              ("31_commander_panel.jpg", "PANEL", "CMD_A + CMD_B on screen (mouse); MOTION, CREW POS and STOP stay hardwired-only"),
              ("32_commander_ics.jpg", "ICS", "intercom: headset per seat, VOX/PTT, levels, volumes, radio effect")]
    tv = '<div class="g2">' + "".join(fig("docs/game/screenshots/" + f, f"<b>{n}</b> · {d}", "h2i", maxw=1100, q=78) for f, n, d in vpages) + "</div>" + \
        card('<p class="tiny">Virtual panels are generated from the CAD layouts (<code>game/tools/gen_virtual_panels.py</code>) and appear and disappear as boards are plugged in; guarded switches need two taps (lift the cover, flip). The intercom helper (<code>game/tools/falcon_ics.py</code>) mixes three USB headsets on PulseAudio or PipeWire with about 30-40 ms delay; the game\'s callouts ride on its MISSION CONTROL channel.</p>')
    out += page("Virtual panels and intercom", tv, "on-screen stand-ins for unplugged boards; three-headset ICS")
    T = D.tests
    if T:
        def rows(sec, fl):
            r = []
            for t in T.get(sec, []):
                base = [f'<span class="{"pass" if t["ok"] else "fail"}">{"PASS" if t["ok"] else "FAIL"}</span>', t["id"], t.get("step", t.get("steps", "")),
                        t.get("score", ""), "★" * int(t.get("stars", 0) or 0), t.get("hull", "")]
                if fl:
                    base += [t.get("mission_time", ""), t.get("maxG", "")]
                r.append(base)
            return r
        meta = T.get("meta", {})
        tests_html = f"""
<div class="g2">
 <div><h3>Flight test · robot crews fly every mission</h3>
  {table(['', 'Mission', 'Objectives', 'Score', 'Stars', 'Hull', 'Time', 'Max g'], rows('flight', True), 'compact')}
  <p class="small"><b>{esc(T.get('flight_result', ''))}</b>. The bots use only the crew's controls (sticks, throttle, switches, buttons, assist modes): no teleporting, real physics.</p></div>
 <div><h3>Smoke test · every mission start to finish</h3>
  {table(['', 'Mission', 'Objectives', 'Score', 'Stars', 'Hull'], rows('smoke', False), 'compact')}
  <p class="small"><b>{esc(T.get('smoke_result', ''))}</b>, with every injected failure (engine fire, cabin leak, power fault, sensor glitch) fixed by crew actions.</p>
  <p class="tiny dim">Run {esc(meta.get('date', '?'))} with {esc(meta.get('godot', '?'))} on commit {esc(meta.get('commit', '?'))}. Re-run with <code>python3 docs/book/build_book.py --run-tests --godot &lt;path&gt;</code>, or by hand as in docs/game/README.md section 8.</p></div>
</div>"""
    else:
        tests_html = "<p>No stored test results (docs/book/test_results.txt).</p>"
    out += page("Test results", tests_html, "headless Godot")
    return out


def ch_bom(D: Data) -> str:
    B = D.bom
    core = {k: v for k, v in B["cats"].items() if "ALTERNATIVE" not in k.upper()}
    rows = [[esc(k), str(v["lines"]), str(v["buy_lines"]), cad(v["total"])] for k, v in B["cats"].items()]
    st_rows = [[esc(k or "-"), cad(v)] for k, v in sorted(B["status"].items(), key=lambda kv: -kv[1]) if v > 0]
    sto_rows = [[esc(k or "-"), cad(v)] for k, v in sorted(B["stores"].items(), key=lambda kv: -kv[1]) if v > 0]
    p1 = f"""
<div class="g-wide-l">
 <div>{table(['Category', 'Lines', 'To buy', 'Total CAD'], rows, 'compact', (1, 2, 3),
             total=['Grand total to buy (excl. ALTERNATIVE)', str(sum(v['lines'] for v in core.values())), str(sum(v['buy_lines'] for v in core.values())), cad(B['grand'])])}
  <p class="tiny dim">Recomputed from <code>{esc(D.bom_source)}</code> exactly like its formulas: Qty to buy = 0 when "Have it" is TRUE, line total = Qty to buy × unit price. Prices before tax and shipping.</p></div>
 <div>
  <div class="stats" style="grid-template-columns: 1fr">{stat(cad(B['grand']), 'to buy, CAD before tax; with NB HST (15 %) about ' + cad(B['grand'] * 1.15))}</div>
  <h4>By price source</h4>{table(['Price status', 'CAD'], st_rows, 'compact', (1,))}
  <h4>By store</h4>{table(['Store', 'CAD'], sto_rows, 'compact', (1,))}
 </div>
</div>"""
    p2 = f"""
<div class="g2">
 <div>
  <h3>How to use the spreadsheet</h3>
  <ol class="small">
   <li>Open <code>bom/Filament_Falcon_BOM.xlsx</code> in LibreOffice Calc or Excel. Sheets: {', '.join(f'<b>{esc(s)}</b>' for s in D.bom_sheets)}.</li>
   <li>On <b>BOM</b>, set <b>Have it</b> to TRUE for anything already in the workshop (switches, wire, screws...). <b>Qty to buy</b> drops to 0 and every total updates.</li>
   <li><b>Summary</b> shows lines, lines still to buy and CAD per category, plus the grand total and how much of it rests on verified prices versus estimates.</li>
   <li><b>Amazon cart</b> lists only the Amazon.ca rows still to buy (alternatives excluded) with product and search links: work down it to fill the cart.</li>
   <li>Rows marked "Estimate" are not verified prices: check them in store (Kent, Home Depot) or get a quote (steel, actuators).</li>
   <li>A CSV copy (<code>bom/Filament_Falcon_BOM.csv</code>) and the scripts that built the sheet are in <code>bom/</code>.</li>
   <li>After editing, re-run this book's generator: the BOM chapter and the headline numbers update.</li>
  </ol>
 </div>
 <div><h3>Notes sheet</h3><ul class="tiny">{''.join(f'<li>{esc(n)}</li>' for n in B['notes'][1:])}</ul></div>
</div>"""
    return chapter("Bill of materials", p1, "What it costs and where to buy it") + page("Using the BOM spreadsheet", p2)


def ch_dome(D: Data) -> str:
    ds = "docs/mechanical/projector_dome_study.md"
    p1 = f"""
{fig('cad/export/png/dome_concept.png', '<b>Concept only:</b> three HY300 projectors rear-projecting onto a 1.2 m (3\' 11") radius dome band around the pod pivot (<code>cad/assembly/dome_concept.scad</code>).', 'h2i', trim=True, pad=0.01, maxw=2000)}
<div class="g2">
 {card('<h4>Recommendation</h4><div class="small">' + md_html(md_section(ds, "Recommendation")) + '</div>', 'cmd')}
 {card('<h4>Verdict</h4><div class="small">' + md_html(md_section(ds, "Verdict")) + '</div>', 'ok')}
</div>"""
    fit = md_bullets(md_section(ds, "Fit with the cockpit"))
    p2 = f"""
<div class="g2">
 <div><h3>Options for the spare GPU output</h3>{md_tbl(md_table(md_section(ds, "GPU output count")), 'compact')}
  <div class="g2">{fig('cad/export/png/dome_concept_3q.png', 'Dome concept, ¾ view.', 'h15 center', trim=True, maxw=800)}{fig('cad/export/png/dome_concept_side.png', 'Side view.', 'h15 center', trim=True, maxw=800)}</div></div>
 <div><h3>Why not with the drop-down pod</h3><ul class="small">{''.join(f'<li>{md_html(b, True)}</li>' for b in fit)}</ul></div>
</div>"""
    return chapter("Projector dome study", p1, "Could cheap projectors wrap the view around the crew?") + page("Outputs and fit with the cockpit", p2)


# Cross-checks between repo files, noticed while compiling the book (not written in any one file).
CROSS_CHECKS = [
    "<b>Third position contact.</b> Firmware, electronics diagram 04 and the game read three contacts (cradle reclined GPIO39, pod down + locked GPIO40, optional pod up + locked GPIO41); frame/BOM.md lists two sense micro switches. Add a third micro switch (or use the second contact of a POD_UP_LOCKED pawl switch) if you want the game to tell POD UP from POD MOVING while the seats are reclined.",
    "<b>New buttons not on the CAD panels.</b> The intercom adds a PTT button per kid (Pilot bit 11, Ops bit 13) and an ALL-CALL button on Falcon Command (bit 7). They are wired and mapped, but cad/tools/layouts.py has no holes for them yet, and the project BOM (bom/) does not list them, the three extra PC817s or the USB headsets.",
    "<b>Cabling plan vs. the real rig.</b> docs/mechanical/displays.md plans the C275W (OPS) on HDMI, but on the owner's rig HDMI-A-0 drives the 31.5\" Commander monitor and the windows are on DisplayPort-2/-1. The game maps roles by output name and size, so this works. Update the cabling table when the final cables are in.",
]


def ch_status(D: Data, now: datetime) -> str:
    T = D.tests
    done = [
        f"Master spec; CAD for {len(D.labels.get('panels', []))} panels and {len(D.val.get('parts', {}))} printed part files, all 3MF exports validated.",
        "Parametric wooden frame with motion geometry, clearance checks, drawings, cut list and frame BOM (v0.2 reclining cradle + drop-down pod).",
        "ESP32-S3 firmware for the three boards, wiring diagrams, udev rules, LED protocol; v0.2 crew-position circuit (relay H-bridges, interlock) with three read-only senses.",
        "Three-headset intercom (VOX / PTT, radio effect, ALL-CALL, MISSION CONTROL callouts) and on-screen virtual panels for unplugged boards.",
        f"Godot game v0.1: six missions, four-screen setup (two windows, kids' touch console, Commander screen). Tests: {esc(T.get('smoke_result', 'n/a'))} (smoke), {esc(T.get('flight_result', 'n/a'))} (flight).",
        f"Editable BOM with {sum(v['lines'] for v in D.bom['cats'].values())} lines: {cad(D.bom['grand'])} CAD still to buy.",
    ]
    p1 = f"""
<div class="g2">
 <div>
  <div class="note"><h4>Status (README)</h4><p class="small">{md_html(md_section('README.md', 'Status'), True)}</p></div>
  {card('<h4>Done on paper and in software</h4><ul class="small">' + ''.join(f'<li>{d}</li>' for d in done) + '</ul>', 'ok')}
 </div>
 <div>
  {card('<h4>Not done yet</h4><ul class="small"><li>Nothing printed, cut, wired or flashed.</li><li>Real LED segment map (measure the strip with <code>FIND &lt;index&gt;</code>).</li><li>Real measurements of joysticks, buckles, VESA screw depth and the TD2220 body.</li><li>Actuators, struts and steel parts ordered and checked against the model.</li><li>Game on the real three screens and touch panel (screenshots so far come from the software renderer).</li></ul>', 'cmd')}
  {fig('docs/game/screenshots/17_mission_complete.jpg', 'The goal: a crew that sees this screen after their first real flight.', 'h22')}
 </div>
</div>"""

    def bl(rel, sec):
        return md_bullets(md_section(rel, sec))
    q_disp = bl("docs/mechanical/displays.md", "To confirm by Yves")
    q_mech = bl("docs/mechanical/README.md", "Assumptions to check before printing")
    q_el = bl("docs/electronics/README.md", "Assumptions to confirm")

    def ul(items):
        return '<ul class="tiny">' + "".join(f"<li>{md_html(b, True)}</li>" for b in items) + "</ul>"
    p2 = f"""
<div class="g3">
 {card('<h4>Displays (displays.md)</h4>' + ul(q_disp) + '<h4>Electronics (electronics README)</h4>' + ul(q_el))}
 {card('<h4>Before printing (mechanical README)</h4>' + ul(q_mech))}
 {card('<h4>Noticed while compiling this book</h4><ul class="tiny">' + ''.join(f'<li>{c}</li>' for c in CROSS_CHECKS) + '</ul>', 'cmd')}
</div>"""
    order = [
        ("Decide and measure", "Answer the open questions: which monitor goes left, harness choice (kit buckles vs. rated metal), joystick type and bolt pattern, buckle size, and a ceiling ≥ 1 950 mm (6' 4.8\") where the cockpit will live."),
        ("Order", "Work down the BOM's Amazon cart; get quotes for steel plates, shafts and actuators. Check retracted lengths (364 / 415 mm) and self-locking before ordering actuators."),
        ("Bench electronics", "Flash one DevKitC-1 with falcon_joystick_test, wire diagram 01, calibrate, check it in evtest / jstest-gtk and on the game's CONTROLS page."),
        ("Print test pieces", "One panel (multi-material or body + inserts) for fit and light leaks, one harness hub base with the real buckles, one joystick housing."),
        ("Build the frame", "Base, nose box, towers and casings, cradle on its shaft (frame assembly steps 1-6). Test the recline empty."),
        ("Pod and counterbalance", "Pod cheeks, back sheet and bands; gas struts with the pod up, then the pod actuators (steps 7-9)."),
        ("Interlock", "Wire the hardwired interlock (frame drawing 04); test every limit, lock, key, E-stop, lever and the safety edge with nobody seated (step 10)."),
        ("Guards and gaps", "Brush strips, skins, crush-zone ramp; re-check every gap with the 25 mm dowel and the 120 mm ball (step 11)."),
        ("Panels, displays, harness", "Bolt in the panels and the monitors with their safety cables, route cables through the pivot clamps, fit the harnesses (step 12)."),
        ("LEDs and game", "Lay the strip, measure the real segment map, rebuild Falcon Command; set up xrandr, autostart the touch mapping and set the display geometry on the Commander SETUP page."),
        ("First flight", "Checklist, harnesses on, hands on laps, heads back, hold FLT... and launch First Light."),
    ]
    p3 = '<div class="g3">' + "".join(
        f'<div class="card keep"><h4>{i + 1:02d} · {esc(t)}</h4><p class="tiny">{d}</p></div>' for i, (t, d) in enumerate(order)) + "</div>"
    return (chapter("Status and next steps", p1, f"As of {now.strftime('%B %-d, %Y')}") + page("Open questions for Yves", p2)
            + page("Suggested build order", p3, "based on the frame assembly steps and the open items"))


def back_page(D: Data, now: datetime) -> str:
    TOC.append((1, "back", "", "Version and changelog"))
    log = "".join(f"<tr><td><code>{esc(h)}</code></td><td class='num'>{esc(d)}</td><td>{esc(s)}</td></tr>" for h, d, s in D.git["log"])
    miss = "".join(f"<li>{esc(m)}</li>" for m in sorted(set(MISSING))) or "<li>Nothing: every file, section and image the generator looks for was found.</li>"
    ed = (f'<h4>This edition</h4><table class="kv compact"><tbody><tr><td>Book version</td><td>{BOOK_VERSION}</td></tr>'
          f'<tr><td>Generated</td><td>{now.strftime("%Y-%m-%d %H:%M %Z")} (Atlantic time)</td></tr>'
          f'<tr><td>Source</td><td>github.com/whyvas/filament-falcon, {esc(D.git["branch"])} @ {esc(D.git["head"])}{" + uncommitted changes" if D.git["dirty"] else ""} ({esc(D.git["count"])} commits)</td></tr>'
          f'<tr><td>Generator</td><td><code>docs/book/build_book.py</code>, <code>book.css</code>, <code>template.html</code></td></tr></tbody></table>')
    return f"""
<section class="page back" id="back"><h2>Version and changelog</h2>
<div class="g-wide-l">
 <div><h3>Project history (git log)</h3>
  <table class="compact"><thead><tr><th>Commit</th><th class="num">Date (Atlantic time)</th><th>Change</th></tr></thead><tbody>{log}</tbody></table>
 </div>
 <div>
  {card(ed, 'cmd')}
  {card('<h4>Book changelog</h4><ul class="small"><li><b>1.0</b> (2026-10-09): first edition, generated from the repo after the mechanical v0.2 and game v0.1 merges.</li></ul>')}
  {card('<h4>Not found in the repo at build time</h4><ul class="tiny">' + miss + '</ul>')}
  <p class="tiny dim">Regenerate after any change: <code>python3 docs/book/build_book.py</code>. Prices in CAD before tax. Metric first, imperial in brackets.</p>
 </div>
</div></section>"""


# ----------------------------------------------------------------------------------------------
def run_tests(godot: str):
    """run the game's smoke + flight tests headless and store the summary lines"""
    game = ROOT / "game"
    out = {}
    subprocess.run([godot, "--headless", "--path", str(game), "--import"], capture_output=True, text=True, timeout=900)
    for name, flag in (("smoke", "--smoke-test"), ("flight", "--flight-test")):
        p = subprocess.run([godot, "--headless", "--path", str(game), "--audio-driver", "Dummy", "--", flag],
                           capture_output=True, text=True, timeout=3600)
        summ = (p.stdout + p.stderr).split("SUMMARY ====")[-1]
        out[name] = [l for l in summ.splitlines() if re.match(r"^(PASS|FAIL) |^RESULT:", l)]
    ver = subprocess.run([godot, "--version"], capture_output=True, text=True).stdout.strip()
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    now = datetime.now(TZ).strftime("%Y-%m-%d %H:%M %Z")
    lines = ["# Game test results - written by docs/book/build_book.py --run-tests",
             f"# date: {now} (Atlantic time)", f"# godot: Godot {ver} (headless, Dummy audio)", f"# commit: {head}"]
    for name in ("smoke", "flight"):
        lines += [f"[{name}]"] + out[name]
    TEST_RESULTS.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote", TEST_RESULTS)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(OUT_PDF))
    ap.add_argument("--html-only", action="store_true")
    ap.add_argument("--run-tests", action="store_true")
    ap.add_argument("--godot", default="godot")
    a = ap.parse_args()

    IMGDIR.mkdir(parents=True, exist_ok=True)
    if a.run_tests:
        run_tests(a.godot)
    make_starfield()
    now = datetime.now(TZ)
    D = Data()
    body = [cover(D, now), toc_page()]
    for f in (ch_vision, ch_crew, ch_layout, ch_motion, ch_safety, ch_frame, ch_panels, ch_parts,
              ch_displays, ch_electronics, ch_led, ch_game, ch_bom, ch_dome):
        body.append(f(D))
    body.append(ch_status(D, now))
    body.append(back_page(D, now))
    bookver = f"v{BOOK_VERSION} · {now.strftime('%Y-%m-%d')} · {D.git['head']}"
    html_body = "\n".join(body).replace("%%TOC%%", render_toc()).replace("%%BOOKVER%%", esc(bookver))
    doc = Template((BOOK / "template.html").read_text(encoding="utf-8")).substitute(
        title="The Filament Falcon - Project Book", description="Home-built three-seat spaceship cockpit simulator",
        created=now.isoformat(timespec="seconds"),
        body=html_body)
    (BUILD / "book.html").write_text(doc, encoding="utf-8")
    if MISSING:
        print("Not found in the repo:", *sorted(set(MISSING)), sep="\n  - ")
    if a.html_only:
        print("wrote", BUILD / "book.html")
        return
    from weasyprint import CSS, HTML
    from weasyprint.text.fonts import FontConfiguration
    fonts = FontConfiguration()          # needed for the @font-face (repo's Barlow Condensed Black)
    HTML(string=doc, base_url=str(BOOK) + "/").write_pdf(
        a.out, stylesheets=[CSS(filename=str(BOOK / "book.css"), font_config=fonts)], font_config=fonts)
    print(f"wrote {a.out} ({Path(a.out).stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
