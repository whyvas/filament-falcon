// The Filament Falcon - assembled cockpit overview (renders only).
// Needs the panel meshes in cad/build/assembly/ (python3 cad/tools/build.py makes them).
// Motion: the kid CRADLE reclines (FF_RECLINE deg) first, then the instrument POD
// rotates down from FF_ALPHA_UP to FF_ALPHA_DN.  Reverse order to get out.
include <../../frame/generated/frame.scad>
use <../parts/throttle_quadrant.scad>
use <../parts/gear_lever.scad>
use <../parts/joystick_housing.scad>
use <../parts/touchscreen_bezel.scad>
use <../parts/monitor_mount.scad>
use <../parts/harness_hub.scad>

STATE = "flight";       // boarding | reclined | flight | custom
TH = 0;                 // custom: cradle recline (deg)
AL = 95;                // custom: pod elevation (deg)
SHOW_CREW = 1;
HIDE_SIDE = 0;          // 1 = cut away the RIGHT casing / skins for the side view; 2 = open the LEFT casing above z 380 (pod drive)
th = STATE == "boarding" ? 0 : STATE == "custom" ? TH : FF_RECLINE;
al = STATE == "flight" ? FF_ALPHA_DN : STATE == "custom" ? AL : FF_ALPHA_UP;

POD_PANELS = ["PILOT_DASH_A", "PILOT_DASH_B", "OPS_DASH_A", "OPS_DASH_B", "OVERHEAD_A", "OVERHEAD_B", "OVERHEAD_C"];
CRADLE_PANELS = ["PILOT_SIDE", "OPS_SIDE"];
FIXED_PANELS = ["CMD_A", "CMD_B"];

module panel_mesh(id) {
  color("#2B2D33") import(str("../build/assembly/", id, "_body.stl"));
  color("#F4F4F4") import(str("../build/assembly/", id, "_letters.stl"));
}
module place(id) {
  if (id == "PILOT_DASH_A") at_PILOT_DASH_A() children();
  if (id == "PILOT_DASH_B") at_PILOT_DASH_B() children();
  if (id == "OPS_DASH_A") at_OPS_DASH_A() children();
  if (id == "OPS_DASH_B") at_OPS_DASH_B() children();
  if (id == "OVERHEAD_A") at_OVERHEAD_A() children();
  if (id == "OVERHEAD_B") at_OVERHEAD_B() children();
  if (id == "OVERHEAD_C") at_OVERHEAD_C() children();
  if (id == "PILOT_SIDE") at_PILOT_SIDE() children();
  if (id == "OPS_SIDE") at_OPS_SIDE() children();
  if (id == "CMD_A") at_CMD_A() children();
  if (id == "CMD_B") at_CMD_B() children();
}
module cutaway() {
  if (HIDE_SIDE == 1) difference() { children(); translate([645, -3000, -10]) cube([600, 3200, 2500]); }
  else if (HIDE_SIDE == 2) difference() { children(); translate([-1245, -3000, 380]) cube([550, 3200, 2500]); }   // open the LEFT casing (pod drive)
  else children();
}

// fixed: base, nose box, towers + casings, ramp, dad dais / seat / console
cutaway() ff_frame_fixed();
for (id = FIXED_PANELS) place(id) panel_mesh(id);
if (SHOW_CREW == 1) color("#d9a066", 0.9) ff_dad();

// cradle (reclines)
ff_cradle_pose(th) {
  cutaway() ff_frame_cradle();
  for (id = CRADLE_PANELS) place(id) panel_mesh(id);
  at_throttle() throttle_assembly();
  at_gear() gear_assembly();
  at_joystick_pilot() joystick_assembly();
  at_joystick_ops() joystick_assembly();
  at_bezel() bezel_assembly();
  if (SHOW_CREW == 1) { color("#e8b27a", 0.9) ff_kid_PILOT(); color("#e8b27a", 0.9) ff_kid_OPS(); }
}

// pod (rotates about the reclined 12 yr head centre)
ff_pod_pose(al) {
  difference() {
    ff_frame_pod();
    if (HIDE_SIDE == 1) translate([800, -3000, -10]) cube([400, 3200, 2500]);
  }
  for (id = POD_PANELS) place(id) panel_mesh(id);
  at_monitor_L() pod_monitor_assembly("C275B");
  at_monitor_R() pod_monitor_assembly("C275W");
}

// actuators (blue), gas struts (black), pivot shafts
if (HIDE_SIDE == 2) ff_mechanisms(th, al); else cutaway() ff_mechanisms(th, al);
