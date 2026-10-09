// Monitor standoff for the drop-down pod: each 27" curved Sceptre hangs on the
// pod's 12 mm back sheet with ONE printed hat-channel standoff.
//   C275B-144R   : 618 x 363.5 x 62.5 mm, 3.80 kg, 1800R, VESA 100 (M4)
//   C275W-1920RN : 616.5 x 366.5 x 65 mm, 3.40 kg, 1800R, VESA 75 (M4)
// The plate carries BOTH VESA 75 and VESA 100 patterns, so one design fits both;
// only the standoff height differs (it puts the screen centre exactly R_SCREEN
// = 600 mm from the pod pivot, i.e. ~540 mm from the 12 yr's eyes).
// Coordinates (PART = "standoff"): monitor plate on the bed (z = 0 is the face that
// touches the monitor's back), walls up, flanges at z = H against the back sheet.
// 4 x M6 carriage bolts through the back sheet + fender washers + nyloc nuts.
// SAFETY: PETG or ASA, 6 perimeters, 5 top/bottom, 50 % gyroid.  The pod turns
// the monitor face-down when it is parked UP, so ALWAYS add a 2 mm steel safety
// cable (loop through a VESA screw and an eye bolt on the back sheet), max 50 mm
// slack.  A steel VESA plate on 64 mm spacers is an equally good substitute.
include <../lib/ff_lib.scad>
PART = "preview";       // standoff | preview | monitor
MODEL = "C275B";        // C275B | C275W

// [width, height, depth incl. curve, mass, VESA]
function mon(m) = m == "C275W" ? [616.5, 366.5, 65.0, 3.40, 75] : [618.0, 363.5, 62.5, 3.80, 100];
CURVE_R = 1800;
function sag(m) = mon(m)[0] * mon(m)[0] / (8 * CURVE_R);
// back of the panel at the VESA area, measured from the screen-centre face
function back_z(m) = mon(m)[2] - sag(m);
GAP = 100;              // pod back sheet front face - screen centre face (700 - 600)
function standoff_h(m) = GAP - back_z(m);

PL = 130; PT = 8; WALL = 8; FL = 30; FT = 8;

module standoff(m = MODEL) {
  H = standoff_h(m);
  difference() {
    union() {
      translate([-PL/2, -PL/2, 0]) cube([PL, PL, PT]);
      for (s = [-1, 1]) translate([s > 0 ? PL/2 - WALL : -PL/2, -PL/2, 0]) cube([WALL, PL, H]);
      // flanges with 45 deg gussets underneath (printable without supports)
      for (s = [-1, 1]) hull() {
        translate([s > 0 ? PL/2 : -PL/2 - FL, -PL/2, H - FT]) cube([FL, PL, FT]);
        translate([s > 0 ? PL/2 - 0.01 : -PL/2, -PL/2, H - FT - FL]) cube([0.01, PL, FL]);
      }
      // stiffening rib across the plate (between the walls)
      translate([-PL/2, -4, 0]) cube([PL, 8, 22]);
    }
    // VESA 100 + VESA 75, M4 clearance, counterbored from inside for the heads
    for (v = [75, 100]) for (x = [-v/2, v/2]) for (y = [-v/2, v/2]) translate([x, y, -1]) {
      cylinder(d = 4.6, h = 50, $fn = 24);
      translate([0, 0, PT - 2 + 1]) cylinder(d = 9, h = 40, $fn = 32);
    }
    // rib clearance around the screw heads
    for (v = [75, 100]) for (x = [-v/2, v/2]) translate([x, 0, PT]) cylinder(d = 14, h = 30, $fn = 32);
    // cable hole + M6 holes
    translate([0, 0, -1]) cylinder(d = 30, h = 50);
    for (s = [-1, 1]) for (y = [-45, 45]) translate([s * (PL/2 + FL/2), y, H - 40]) cylinder(d = 6.6, h = 60, $fn = 24);
    // safety-cable hole in a flange corner
    translate([PL/2 + FL - 9, PL/2 - 9, H - 30]) cylinder(d = 4, h = 40, $fn = 20);
    // model name
    translate([0, -PL/2 + 12, PT - 0.6]) linear_extrude(1) text(m, size = 7, halign = "center", font = "Liberation Sans:style=Bold");
  }
}

// curved monitor stand-in.  Origin = screen centre on the face, +y = up the screen,
// +z = toward the viewer (the centre of curvature is at z = +CURVE_R).
module monitor_standin(m = MODEL) {
  W = mon(m)[0]; Hh = mon(m)[1]; D = mon(m)[2];
  a = 2 * asin(W / 2 / CURVE_R);
  color("#151517") translate([0, 0, CURVE_R]) rotate([90, 0, 0]) translate([0, 0, -Hh/2])
    rotate([0, 0, -90 - a/2]) rotate_extrude(angle = a, $fn = 360) translate([CURVE_R, 0]) square([16, Hh]);
  color("#0b1a3a") translate([0, 0, CURVE_R]) rotate([90, 0, 0]) translate([0, 0, -Hh/2 + 12])
    rotate([0, 0, -90 - a/2 + 0.5]) rotate_extrude(angle = a - 1, $fn = 360) translate([CURVE_R - 0.5, 0]) square([1, Hh - 24]);
  color("#1d1d20") hull() {
    translate([-170, -120, -back_z(m)]) cube([340, 220, 2]);
    translate([-250, -160, -16]) cube([500, 300, 2]);
  }
}

// monitor + standoff in the monitor frame (used by cad/assembly/overview.scad)
module pod_monitor_assembly(m = MODEL, sheet = false) {
  monitor_standin(m);
  color("#2a2a2e") translate([0, 0, -back_z(m)]) mirror([0, 0, 1]) standoff(m);
  if (sheet) color("#c9a46c", 0.6) translate([-320, -200, -GAP - 12]) cube([640, 400, 12]);   // back sheet (context)
}

if (PART == "standoff") standoff(MODEL);
else if (PART == "monitor") monitor_standin(MODEL);
else {
  rotate([90, 0, 0]) pod_monitor_assembly(MODEL, true);
  echo(str(MODEL, " standoff height = ", standoff_h(MODEL), " mm, sag = ", sag(MODEL)));
}
