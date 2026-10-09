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
    ("parts/monitor_mount.scad", "beam_bracket", {}, "monitor_beam_bracket", BLACK, 2),
    ("parts/monitor_mount.scad", "vesa_plate", {}, "monitor_vesa_plate", BLACK, 2),
    ("parts/touchscreen_bezel.scad", "q_fl", {}, "touchscreen_bezel_front_left", BLACK, 1),
    ("parts/touchscreen_bezel.scad", "q_fr", {}, "touchscreen_bezel_front_right", BLACK, 1),
    ("parts/touchscreen_bezel.scad", "q_rl", {}, "touchscreen_bezel_rear_left", BLACK, 1),
    ("parts/touchscreen_bezel.scad", "q_rr", {}, "touchscreen_bezel_rear_right", BLACK, 1),
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
    ("parts/monitor_mount.scad", (75, 0, 150), "monitor_mount"),
    ("parts/touchscreen_bezel.scad", (40, 0, 15), "touchscreen_bezel"),
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


def verify_3mf(path, expect_parts):
    import lib3mf
    w = lib3mf.get_wrapper()
    model = w.CreateModel()
    model.QueryReader("3mf").ReadFromFile(path)
    it = model.GetMeshObjects()
    n = 0
    tri = 0
    while it.MoveNext():
        o = it.GetCurrentMeshObject()
        tri += o.GetTriangleCount()
        n += 1
    sc = trimesh.load(path)
    geoms = list(sc.geometry.values()) if hasattr(sc, "geometry") else [sc]
    return dict(lib3mf_objects=n, lib3mf_triangles=tri, trimesh_triangles=sum(len(g.faces) for g in geoms))


def build_panel(pid):
    from threemf import write_3mf
    scad = os.path.join(CAD, "panels", f"{pid}.scad")
    tmp = os.path.join(BUILD, pid)
    os.makedirs(tmp, exist_ok=True)
    meshes = {}
    for part in ("mm_body", "mm_letters", "sm_body", "sm_inserts"):
        meshes[part] = load(OS.export(scad, os.path.join(tmp, f"{part}.stl"), {"PART": part}))
    # unrotated copies for the assembly render
    for part, d in (("body", {"PART": "mm_body"}), ("letters", {"PART": "mm_letters"})):
        pass
    res = [check(meshes["mm_body"], f"{pid} multi-material body"),
           check(meshes["mm_letters"], f"{pid} letters"),
           check(meshes["sm_body"], f"{pid} single-material body", single_shell=True),
           check(meshes["sm_inserts"], f"{pid} letter inserts")]
    d = os.path.join(OUT3, "panels")
    os.makedirs(d, exist_ok=True)
    f_mm = os.path.join(d, f"{pid}_multimaterial.3mf")
    write_3mf(f_mm, pid, [("body (black)", meshes["mm_body"], 1, BLACK), ("letters (white)", meshes["mm_letters"], 2, WHITE)])
    f_b = os.path.join(d, f"{pid}_single_body.3mf")
    write_3mf(f_b, f"{pid}_single_body", [("body", meshes["sm_body"], 1, BLACK)])
    f_i = os.path.join(d, f"{pid}_single_letter_inserts_WHITE.3mf")
    write_3mf(f_i, f"{pid}_letter_inserts", [("letter inserts", meshes["sm_inserts"], 1, WHITE)])
    v = {os.path.relpath(f, ROOT): verify_3mf(f, 2) for f in (f_mm, f_b, f_i)}
    return pid, res, v


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
    scad, rot, name = e
    p = os.path.join(OUTP, "parts")
    os.makedirs(p, exist_ok=True)
    return [OS.png(os.path.join(CAD, scad), os.path.join(p, f"{name}.png"), {},
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
    views = [("overview_raised", {"SEAT": "raised"}, "0,-950,850,60,0,35,5600"),
             ("overview_lowered", {"SEAT": "lowered"}, "0,-950,850,60,0,35,5600"),
             ("overview_front", {"SEAT": "raised"}, "0,-950,850,62,0,215,5600"),
             ("overview_cockpit_pov", {"SEAT": "raised"}, "0,-330,950,66,0,0,1500"),
             ("overview_side", {"SEAT": "raised", "HIDE_SIDE": 1}, "0,-1050,900,90,0,90,4800"),
             ("overview_side_lowered", {"SEAT": "lowered", "HIDE_SIDE": 1}, "0,-1050,900,90,0,90,4800")]
    for name, defs, cam in views:
        extra = ["--projection=o", "--viewall", "--autocenter"] if "side" in name else []
        OS.png(scad, os.path.join(OUTP, f"{name}.png"), defs, camera=cam, size=(1920, 1200), extra=extra)


if __name__ == "__main__":
    sys.exit(main())
