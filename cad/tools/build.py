#!/usr/bin/env python3
"""Build everything in cad/: regenerate panels, export + validate 3MF, render PNGs.

  python3 cad/tools/build.py [--only NAME] [--no-render] [--openscad PATH]

Needs: OpenSCAD (2021.01 works; a 2024+ snapshot with --backend=Manifold is ~100x
faster), python3 with trimesh, numpy, lib3mf, shapely, fonttools, networkx.
"""
import argparse, concurrent.futures as cf, json, os, shutil, subprocess, sys, tempfile, time
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
import trimesh

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CAD = os.path.join(ROOT, "cad")
OUT3 = os.path.join(CAD, "export", "3mf")
OUTP = os.path.join(CAD, "export", "png")
BUILD = os.path.join(CAD, "build")          # cache (git-ignored)
BED = 220.0
BLACK, WHITE, RED, GREY = "#1E1F22", "#F2F2F2", "#C81E1E", "#55575C"

# (scad file, PART, extra -D, output name, colour, copies to print)
PARTS = [
    ("parts/toggle_guard.scad", "base", {}, "toggle_guard_base", BLACK, 3),
    ("parts/toggle_guard.scad", "lid", {}, "toggle_guard_lid_RED", RED, 3),
    ("parts/button_collar.scad", "collar", {}, "engage_button_collar", BLACK, 1),
    ("parts/alignment_pin.scad", "pin", {}, "alignment_pins_x8", BLACK, 1),
    ("parts/throttle_quadrant.scad", "housing", {}, "throttle_housing", BLACK, 1),
    ("parts/throttle_quadrant.scad", "lever", {}, "throttle_lever", BLACK, 1),
    ("parts/throttle_quadrant.scad", "grip", {}, "throttle_grip", RED, 1),
    ("parts/gear_lever.scad", "box", {}, "gear_lever_box", BLACK, 1),
    ("parts/gear_lever.scad", "lever", {}, "gear_lever_arm", GREY, 1),
    ("parts/gear_lever.scad", "knob", {}, "gear_lever_wheel_knob", WHITE, 1),
    ("parts/joystick_housing.scad", "housing", {}, "joystick_housing", BLACK, 2),
    ("parts/joystick_housing.scad", "adapter", {}, "joystick_adapter_plate", GREY, 2),
    ("parts/esp32_enclosure.scad", "base", {}, "esp32_enclosure_base", BLACK, 3),
    ("parts/esp32_enclosure.scad", "lid", {"NAME": "PILOT"}, "esp32_enclosure_lid_PILOT", BLACK, 1),
    ("parts/esp32_enclosure.scad", "lid", {"NAME": "OPS"}, "esp32_enclosure_lid_OPS", BLACK, 1),
    ("parts/esp32_enclosure.scad", "lid", {"NAME": "COMMAND"}, "esp32_enclosure_lid_COMMAND", BLACK, 1),
    ("parts/cable_clips.scad", "set", {}, "cable_clips_set", BLACK, 3),
    ("parts/limit_switch_mount.scad", "bracket", {}, "limit_switch_mount", BLACK, 3),
    ("parts/monitor_mount.scad", "standoff", {"MODEL": "C275B"}, "monitor_standoff_C275B_vesa100", BLACK, 1),
    ("parts/monitor_mount.scad", "standoff", {"MODEL": "C275W"}, "monitor_standoff_C275W_vesa75", BLACK, 1),
    ("parts/touchscreen_bezel.scad", "c_fl", {}, "td2220_trim_corner_front_left", BLACK, 1),
    ("parts/touchscreen_bezel.scad", "c_fr", {}, "td2220_trim_corner_front_right", BLACK, 1),
    ("parts/touchscreen_bezel.scad", "c_rl", {}, "td2220_trim_corner_rear_left", BLACK, 1),
    ("parts/touchscreen_bezel.scad", "c_rr", {}, "td2220_trim_corner_rear_right", BLACK, 1),
    ("parts/touchscreen_bezel.scad", "m_f", {}, "td2220_trim_middle_front", BLACK, 1),
    ("parts/touchscreen_bezel.scad", "m_r", {}, "td2220_trim_middle_rear", BLACK, 1),
    ("parts/touchscreen_bezel.scad", "riser", {}, "td2220_vesa100_riser", BLACK, 1),
    ("parts/harness_hub.scad", "base", {}, "harness_hub_base", BLACK, 2),
    ("parts/harness_hub.scad", "lid", {}, "harness_hub_lid", BLACK, 2),
    ("parts/pivot_cable_clamp.scad", "base", {}, "pivot_cable_clamp_base", BLACK, 8),
    ("parts/pivot_cable_clamp.scad", "cap", {}, "pivot_cable_clamp_cap", BLACK, 8),
]
PART_RENDERS = [  # scad, camera rot (x,y,z), name
    ("parts/toggle_guard.scad", (55, 0, 35), "toggle_guard"),
    ("parts/button_collar.scad", (55, 0, 25), "engage_button_collar"),
    ("parts/throttle_quadrant.scad", (65, 0, 40), "throttle_quadrant"),
    ("parts/gear_lever.scad", (65, 0, 40), "gear_lever"),
    ("parts/joystick_housing.scad", (60, 0, 30), "joystick_housing"),
    ("parts/esp32_enclosure.scad", (55, 0, 30), "esp32_enclosure"),
    ("parts/cable_clips.scad", (50, 0, 20), "cable_clips"),
    ("parts/limit_switch_mount.scad", (60, 0, 35), "limit_switch_mount"),
    ("parts/monitor_mount.scad", (70, 0, 145), "monitor_mount"),
    ("parts/touchscreen_bezel.scad", (40, 0, 15), "touchscreen_bezel"),
    ("parts/harness_hub.scad", (45, 0, 15), "harness_hub"),
    ("parts/harness_hub.scad", (35, 0, 0), "harness_hub_open", {"PART": "preview_open"}),
    ("parts/harness_hub.scad", (40, 0, 20), "harness_hub_base_only", {"PART": "base"}),
    ("parts/pivot_cable_clamp.scad", (60, 0, 30), "pivot_cable_clamp"),
]


def run(cmd, timeout=1800):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)}\n{r.stdout[-2000:]}\n{r.stderr[-3000:]}")
    return r.stdout + r.stderr


class OS:
    exe = "openscad"
    manifold = False

    @classmethod
    def export(cls, scad, out, defs):
        cmd = [cls.exe, "-o", out]
        if cls.manifold:
            cmd += ["--backend=Manifold", "--export-format", "binstl"]
        for k, v in defs.items():
            cmd += ["-D", f'{k}="{v}"' if isinstance(v, str) else f"{k}={v}"]
        log = run(cmd + [scad])
        if "WARNING" in log:
            w = [l for l in log.splitlines() if "WARNING" in l]
            print(f"  ! {os.path.basename(scad)} {defs}: {w[:3]}")
        return out

    @classmethod
    def png(cls, scad, out, defs, camera=None, size=(1600, 1200), extra=()):
        cmd = ["xvfb-run", "-a", cls.exe, "-o", out, f"--imgsize={size[0]},{size[1]}", "--colorscheme=Tomorrow Night"]
        cmd += list(extra)
        if camera:
            cmd += [f"--camera={camera}"]
        for k, v in defs.items():
            cmd += ["-D", f'{k}="{v}"' if isinstance(v, str) else f"{k}={v}"]
        run(cmd + [scad])
        return out


def load(path):
    m = trimesh.load(path, force="mesh")
    m.merge_vertices()
    return m


def check(m, name, single_shell=False, bed=True):
    probs = []
    if not m.is_watertight:
        probs.append("not watertight")
    if not m.is_winding_consistent:
        probs.append("inconsistent winding")
    if m.volume <= 0:
        probs.append("non-positive volume")
    ext = m.extents
    if bed and (ext[0] > BED + 0.01 or ext[1] > BED + 0.01):
        probs.append(f"footprint {ext[0]:.1f} x {ext[1]:.1f} exceeds {BED} bed")
    if single_shell:
        n = len(m.split(only_watertight=False))
        if n != 1:
            probs.append(f"{n} separate shells (islands would fall out)")
    return dict(name=name, faces=len(m.faces), volume_cm3=round(m.volume / 1000, 2),
                size_mm=[round(v, 1) for v in ext], watertight=bool(m.is_watertight), problems=probs)


def verify_3mf(path, expect_objects):
    import lib3mf
    w = lib3mf.get_wrapper()
    model = w.CreateModel()
    model.QueryReader("3mf").ReadFromFile(path)
    it = model.GetMeshObjects()
    n = 0
    tri = 0
    names = []
    while it.MoveNext():
        o = it.GetCurrentMeshObject()
        tri += o.GetTriangleCount()
        names.append(o.GetName())
        n += 1
    sc = trimesh.load(path)
    geoms = list(sc.geometry.values()) if hasattr(sc, "geometry") else [sc]
    info = dict(lib3mf_objects=n, lib3mf_names=names, lib3mf_triangles=tri,
                trimesh_geometries=len(geoms), trimesh_triangles=sum(len(g.faces) for g in geoms))
    if n != expect_objects:
        info["problems"] = [f"expected {expect_objects} objects, found {n}: {names}"]
    return info


def build_panel(pid):
    """One multi-material 3MF: black panel object + white letters object.

    The letter object is the through-face lettering plus the 0.8 mm backing box
    behind each label (the old separate insert's plaque).
    """
    from threemf import write_3mf
    scad = os.path.join(CAD, "panels", f"{pid}.scad")
    tmp = os.path.join(BUILD, pid)
    os.makedirs(tmp, exist_ok=True)
    meshes = {}
    for part in ("mm_body", "mm_letters"):
        meshes[part] = load(OS.export(scad, os.path.join(tmp, f"{part}.stl"), {"PART": part}))
    res = [check(meshes["mm_body"], f"{pid} panel"),
           check(meshes["mm_letters"], f"{pid} letters")]
    face_z = float(meshes["mm_letters"].bounds[0][2])
    if float(meshes["mm_letters"].bounds[1][2]) < face_z + 3.5:
        res[1]["problems"].append("letters are only the face thickness; backing box is missing")
    try:
        hit = trimesh.boolean.intersection([meshes["mm_body"], meshes["mm_letters"]], engine="manifold")
        iv = float(hit.volume) if hit is not None and len(hit.faces) else 0.0
        if iv > 5.0:
            res[1]["problems"].append(f"letters intersect the panel by {iv:.1f} mm^3")
    except Exception as e:
        res[1]["problems"].append(f"intersection check failed: {e}")
    d = os.path.join(OUT3, "panels")
    os.makedirs(d, exist_ok=True)
    for old in (f"{pid}_multimaterial.3mf", f"{pid}_single_body.3mf", f"{pid}_single_letter_inserts_WHITE.3mf"):
        p = os.path.join(d, old)
        if os.path.exists(p):
            os.remove(p)
    f = os.path.join(d, f"{pid}.3mf")
    write_3mf(f, pid, [("panel", meshes["mm_body"], 1, BLACK),
                       ("letters", meshes["mm_letters"], 2, WHITE)])
    info = verify_3mf(f, 2)
    if info.get("problems"):
        res[0]["problems"] += info["problems"]
    return pid, res, {os.path.relpath(f, ROOT): info}


def build_part(entry):
    from threemf import write_3mf
    scad, part, extra, name, col, copies = entry
    tmp = os.path.join(BUILD, "parts")
    os.makedirs(tmp, exist_ok=True)
    defs = dict(extra); defs["PART"] = part
    m = load(OS.export(os.path.join(CAD, scad), os.path.join(tmp, f"{name}.stl"), defs))
    res = check(m, name, single_shell=name not in ("alignment_pins_x8", "cable_clips_set"))
    d = os.path.join(OUT3, "parts")
    os.makedirs(d, exist_ok=True)
    f = os.path.join(d, f"{name}.3mf")
    write_3mf(f, name, [(name, m, 1, col)])
    res["copies"] = copies
    res["file"] = os.path.relpath(f, ROOT)
    return name, res, {os.path.relpath(f, ROOT): verify_3mf(f, 1)}


def render_panel(pid):
    scad = os.path.join(CAD, "panels", f"{pid}.scad")
    out = []
    p = os.path.join(OUTP, "panels")
    os.makedirs(p, exist_ok=True)
    out.append(OS.png(scad, os.path.join(p, f"{pid}_front.png"), {"PART": "preview"},
                      extra=["--viewall", "--autocenter", "--projection=o"], camera="0,0,0,0,0,0,0", size=(1600, 1300)))
    out.append(OS.png(scad, os.path.join(p, f"{pid}_back.png"), {"PART": "bare"},
                      extra=["--viewall", "--autocenter"], camera="0,0,0,215,0,200,0", size=(1600, 1300)))
    return out


def render_part(e):
    scad, rot, name = e[:3]
    defs = e[3] if len(e) > 3 else {}
    p = os.path.join(OUTP, "parts")
    os.makedirs(p, exist_ok=True)
    return [OS.png(os.path.join(CAD, scad), os.path.join(p, f"{name}.png"), defs,
                   extra=["--viewall", "--autocenter"], camera=f"0,0,0,{rot[0]},{rot[1]},{rot[2]},0", size=(1400, 1100))]


def assembly_meshes(pids):
    """Unrotated body/letters STLs used by cad/assembly/overview.scad."""
    d = os.path.join(BUILD, "assembly")
    os.makedirs(d, exist_ok=True)

    def one(pid):
        scad = os.path.join(CAD, "panels", f"{pid}.scad")
        # 'preview_body' / 'preview_letters' = un-rotated
        OS.export(scad, os.path.join(d, f"{pid}_body.stl"), {"PART": "asm_body"})
        OS.export(scad, os.path.join(d, f"{pid}_letters.stl"), {"PART": "asm_letters"})
    with cf.ThreadPoolExecutor(8) as ex:
        list(ex.map(one, pids))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--openscad", default=os.environ.get("OPENSCAD", "openscad"))
    ap.add_argument("--only")
    ap.add_argument("--no-render", action="store_true")
    ap.add_argument("--no-export", action="store_true")
    a = ap.parse_args()
    OS.exe = a.openscad
    OS.manifold = "Manifold" in subprocess.run([OS.exe, "--help"], capture_output=True, text=True).stdout + \
                  subprocess.run([OS.exe, "--help"], capture_output=True, text=True).stderr
    t0 = time.time()
    r = subprocess.run([sys.executable, os.path.join(CAD, "tools", "gen_panels.py")], capture_output=True, text=True)
    print(r.stdout.strip())
    if r.returncode:
        print(r.stdout, r.stderr)
        sys.exit("layout check failed")
    import layouts
    pids = [p.id for p in layouts.PANELS]
    parts = PARTS
    if a.only:
        pids = [p for p in pids if a.only in p]
        parts = [p for p in PARTS if a.only in p[3]]
    report = dict(panels={}, parts={}, files={})
    ok = True
    with cf.ThreadPoolExecutor(8) as ex:
        if not a.no_export:
            for pid, res, v in ex.map(build_panel, pids):
                report["panels"][pid] = res
                report["files"].update(v)
            for name, res, v in ex.map(build_part, parts):
                report["parts"][name] = res
                report["files"].update(v)
        if not a.no_render:
            list(ex.map(render_panel, pids))
            list(ex.map(render_part, PART_RENDERS if not a.only else [e for e in PART_RENDERS if a.only in e[2]]))
    if not a.no_render and not a.only:
        assembly_meshes([p.id for p in layouts.PANELS])
        render_overview()
    for k, v in list(report["panels"].items()):
        for r_ in v:
            if r_["problems"]:
                ok = False; print("PROBLEM", r_["name"], r_["problems"])
    for k, r_ in report["parts"].items():
        if r_["problems"]:
            ok = False; print("PROBLEM", k, r_["problems"])
    if not a.only and not a.no_export:
        with open(os.path.join(CAD, "export", "validation_report.json"), "w") as f:
            json.dump(report, f, indent=1)
    print(f"done in {time.time() - t0:.0f}s, {'all checks passed' if ok else 'PROBLEMS FOUND'}")
    return 0 if ok else 1


def render_overview():
    scad = os.path.join(CAD, "assembly", "overview.scad")
    os.makedirs(OUTP, exist_ok=True)
    for f in os.listdir(OUTP):          # drop renders of the old tilting-platform design
        if f.startswith("overview_") and f.endswith(".png"):
            os.remove(os.path.join(OUTP, f))
    rear = "0,-1150,800,62,0,35,6200"
    front = "0,-1150,750,60,0,215,6400"
    side = "0,-1250,900,90,0,90,5200"
    views = [("overview_flight", {"STATE": "flight"}, rear),
             ("overview_boarding", {"STATE": "boarding"}, rear),
             ("overview_reclined_pod_up", {"STATE": "reclined"}, rear),
             ("overview_boarding_front", {"STATE": "boarding"}, front),
             ("overview_flight_front", {"STATE": "flight"}, front),
             ("overview_dad_view", {"STATE": "flight"}, "0,-915,1300,75,0,0,1900"),
             ("overview_pod_drive", {"STATE": "flight", "HIDE_SIDE": 2}, "0,-1250,850,50,0,245,7000"),
             ("overview_side_boarding", {"STATE": "boarding", "HIDE_SIDE": 1}, side),
             ("overview_side_reclined", {"STATE": "reclined", "HIDE_SIDE": 1}, side),
             ("overview_side_flight", {"STATE": "flight", "HIDE_SIDE": 1}, side)]

    def one(v):
        name, defs, cam = v
        extra = ["--projection=o"] if "side" in name else []
        return OS.png(scad, os.path.join(OUTP, f"{name}.png"), defs, camera=cam, size=(1920, 1200), extra=extra)
    with cf.ThreadPoolExecutor(4) as ex:
        list(ex.map(one, views))
    # motion sequence strip (side views)
    from PIL import Image, ImageDraw
    ims = [Image.open(os.path.join(OUTP, f"overview_side_{k}.png")).convert("RGB") for k in ("boarding", "reclined", "flight")]
    w, h = ims[0].size
    crop = (int(w * 0.08), int(h * 0.02), int(w * 0.92), int(h * 0.98))
    ims = [im.crop(crop).resize(((crop[2] - crop[0]) // 2, (crop[3] - crop[1]) // 2)) for im in ims]
    W_, H_ = ims[0].size
    strip = Image.new("RGB", (3 * W_, H_ + 40), (30, 31, 34))
    d = ImageDraw.Draw(strip)
    from PIL import ImageFont
    try:
        fnt = ImageFont.load_default(size=26)
    except TypeError:
        fnt = ImageFont.load_default()
    for i, (im, t) in enumerate(zip(ims, ("1 BOARDING: upright, pod parked up", "2 RECLINE 35 deg (pod still locked up)", "3 FLIGHT: pod down to its stop"))):
        strip.paste(im, (i * W_, 40))
        d.text((i * W_ + 20, 8), t, fill=(240, 240, 240), font=fnt)
    strip.save(os.path.join(OUTP, "overview_motion_sequence.png"))
    render_dome()


def render_dome():
    """Concept render for docs/mechanical/projector_dome_study.md."""
    from PIL import Image, ImageDraw, ImageFont
    scad = os.path.join(CAD, "assembly", "dome_concept.scad")
    a = os.path.join(OUTP, "dome_concept_3q.png")
    b = os.path.join(OUTP, "dome_concept_side.png")
    OS.png(scad, a, {}, camera="0,-900,900,55,0,215,9500", size=(1600, 1100))
    OS.png(scad, b, {"HIDE_SIDE": 1}, camera="0,-700,900,90,0,90,7000", size=(1600, 1100), extra=["--projection=o"])
    ims = [Image.open(x).convert("RGB") for x in (a, b)]
    W_, H_ = ims[0].size
    out = Image.new("RGB", (2 * W_, H_ + 70), (30, 31, 34))
    d = ImageDraw.Draw(out)
    try:
        f = ImageFont.load_default(size=30)
    except TypeError:
        f = ImageFont.load_default()
    for i, (im, t) in enumerate(zip(ims, ("CONCEPT: 3 x HY300 rear-projecting onto a dome band (R 1200 about the pod pivot)",
                                          "Side section: in FLIGHT the pod sits between the kids and the dome"))):
        out.paste(im, (i * W_, 70))
        d.text((i * W_ + 24, 20), t, fill=(240, 240, 240), font=f)
    out.save(os.path.join(OUTP, "dome_concept.png"))


if __name__ == "__main__":
    sys.exit(main())
