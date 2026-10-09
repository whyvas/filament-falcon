// The Filament Falcon - assembled cockpit overview (renders only).
// Needs the panel meshes in cad/build/assembly/ (python3 cad/tools/build.py makes them).
include <../../frame/generated/frame.scad>
use <../parts/throttle_quadrant.scad>
use <../parts/gear_lever.scad>
use <../parts/joystick_housing.scad>
use <../parts/touchscreen_bezel.scad>
use <../parts/monitor_mount.scad>

SEAT = "raised";              // raised | lowered
SHOW_PLATFORM_GHOST = 0;
HIDE_SIDE = 0;          // 1 = cut away the right-hand side skins for the side view
A = SEAT == "raised" ? FRAME_THETA_MAX : 0;

FIXED_PANELS = ["PILOT_DASH_A", "PILOT_DASH_B", "OPS_DASH_A", "OPS_DASH_B", "OVERHEAD_A", "OVERHEAD_B", "OVERHEAD_C"];
PLATFORM_PANELS = ["PILOT_SIDE", "OPS_SIDE", "CMD_A", "CMD_B"];

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

// fixed frame + everything bolted to it
if (HIDE_SIDE == 1) difference() { ff_frame_fixed(); translate([840, -2200, -10]) cube([100, 2300, 2000]); }
else ff_frame_fixed();
for (id = FIXED_PANELS) place(id) panel_mesh(id);
at_monitor_L() monitor_assembly(6);
at_monitor_R() monitor_assembly(6);

// pivoting seat platform + everything on it
ff_platform_pose(A) {
  ff_frame_platform(SHOW_PLATFORM_GHOST == 1);
  for (id = PLATFORM_PANELS) place(id) panel_mesh(id);
  at_throttle() throttle_assembly();
  at_gear() gear_assembly();
  at_joystick_pilot() joystick_assembly();
  at_joystick_ops() joystick_assembly();
  at_bezel() bezel_assembly();
  // seat cushions + harness straps (illustrative)
  for (x = [-380, 380]) {
    color("#7a1f1f") translate([x - 160, -850, 422]) cube([320, 370, 60]);
    color("#7a1f1f") translate([x - 160, -868 + 18, 482]) cube([320, 40, 560]);
    color("#222") for (s = [-1, 1]) translate([x + s * 80 - 25, -830, 482]) cube([50, 4, 520]);
  }
  color("#7a1f1f") translate([-250, -1780, 652]) cube([500, 470, 70]);
  color("#7a1f1f") translate([-250, -1780, 722]) cube([500, 40, 700]);
  // linear actuators (stand-ins)
}
// actuators: drawn between the header and the moving nose clevis
for (x = [-500, 500]) {
  top = [x, -160, 850];
  bot = [x, -(160 + 0) , 110];
  // rotate the bottom clevis with the platform
  hb = FRAME_HINGE;
  r = [bot[1] - hb[1], bot[2] - hb[2]];
  bb = [x, hb[1] + r[0] * cos(A) - r[1] * sin(A), hb[2] + r[0] * sin(A) + r[1] * cos(A)];
  color("silver") hull() { translate(top) sphere(d = 30); translate(top - [0, 0, 300]) sphere(d = 30); }
  color("#888") hull() { translate(bb) sphere(d = 20); translate(top) sphere(d = 20); }
}
