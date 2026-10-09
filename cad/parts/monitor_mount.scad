// Adjustable hanger for a 27" curved monitor (VESA 100) hanging almost straight
// down from a 2x4 top cross-beam in front of each kid.
// Coordinates: the 2x4 stands on edge, its FRONT face is the plane y = 0
// (beam occupies y -38..0, z 0..89).  +y points toward the kid.
//   beam_bracket : screws to the beam front face (4 x M6 lag or #12 wood screws in
//                  vertical slots: +-8 mm height adjust; more via the frame holes)
//   vesa_plate   : 4 x M4x12 into the monitor's VESA 100 holes.  Its tongue hangs
//                  between the bracket ears on an M8 pivot bolt; an M6 bolt through
//                  the arc slot locks the tilt (-20 .. +20 deg).
// SAFETY: PETG/ASA, 6 perimeters, 60 %+ infill.  ALWAYS add a steel safety cable
// from a VESA screw to the beam.  A steel VESA tilt bracket is a fine substitute.
include <../lib/ff_lib.scad>
PART = "preview";     // beam_bracket | vesa_plate | preview
TILT = 8;

VESA = 100;
PY = 22; PZ = -28;    // pivot position
LOCK_R = 30;          // tilt lock bolt radius (straight below the pivot)
TONGUE_T = 20;
EAR_T = 8;
EAR_GAP = TONGUE_T + 0.8;
PLATE_Y = 56;         // back face of the VESA plate
PLATE_T = 7;

module ear2d() {      // in the y-z plane
  hull() {
    translate([0, 5]) square([8, 80]);
    translate([PY, PZ]) circle(r = 13);
    for (a = [-22, 22]) translate([PY + LOCK_R * sin(a), PZ - LOCK_R * cos(a)]) circle(r = 9);
  }
}

module beam_bracket() {
  difference() {
    union() {
      translate([-50, 0, 5]) cube([100, 8, 80]);
      for (s = [-1, 1]) translate([s > 0 ? EAR_GAP/2 : -EAR_GAP/2 - EAR_T, 0, 0])
        rotate([90, 0, 90]) linear_extrude(EAR_T) ear2d();
      // web between ears under the plate
      translate([-EAR_GAP/2 - EAR_T, 0, 5]) cube([EAR_GAP + 2*EAR_T, 8, 10]);
    }
    for (x = [-38, 38]) for (z = [22, 68]) translate([x, -1, z]) rotate([-90, 0, 0])
      hull() for (dz = [-8, 8]) translate([0, dz, 0]) cylinder(d = 6.8, h = 20);
    translate([-60, PY, PZ]) rotate([0, 90, 0]) cylinder(d = 8.5, h = 120);
    for (a = [-20 : 2 : 18]) hull() for (b = [a, a + 2])
      translate([-60, PY + LOCK_R * sin(b), PZ - LOCK_R * cos(b)]) rotate([0, 90, 0]) cylinder(d = 6.6, h = 120);
    translate([-EAR_GAP/2, 8.01, -100]) cube([EAR_GAP, 200, 200]);
  }
}

module vesa_plate() {
  difference() {
    union() {
      translate([-65, PLATE_Y, PZ - 150]) cube([130, PLATE_T, 135]);
      for (x = [-35, 35]) translate([x - 3, PLATE_Y - 10, PZ - 150]) cube([6, 10.01, 135]);
      hull() {
        translate([-TONGUE_T/2, PY, PZ]) rotate([0, 90, 0]) cylinder(r = 11, h = TONGUE_T);
        translate([-TONGUE_T/2, PY, PZ - LOCK_R]) rotate([0, 90, 0]) cylinder(r = 9, h = TONGUE_T);
        translate([-TONGUE_T/2, PLATE_Y - 0.01, PZ - 70]) cube([TONGUE_T, 0.02, 70 + 11]);
      }
    }
    translate([-60, PY, PZ]) rotate([0, 90, 0]) cylinder(d = 8.5, h = 120);
    translate([-60, PY, PZ - LOCK_R]) rotate([0, 90, 0]) cylinder(d = 6.6, h = 120);
    for (x = [-VESA/2, VESA/2]) for (z = [-VESA/2, VESA/2]) translate([x, PLATE_Y - 20, PZ - 85 + z]) rotate([-90, 0, 0]) {
      cylinder(d = 4.5, h = 40); cylinder(d = 9, h = 20 + 0.01);
    }
    translate([0, PLATE_Y - 20, PZ - 85]) rotate([-90, 0, 0]) cylinder(d = 36, h = 40);
  }
}

if (PART == "beam_bracket") rotate([90, 0, 0]) beam_bracket();
else if (PART == "vesa_plate") translate([0, 0, PLATE_Y + PLATE_T]) rotate([-90, 0, 0]) vesa_plate();
else {
  color("#a0784a") translate([-200, -38, 0]) cube([400, 38, 89]);
  monitor_assembly();
}
module monitor_assembly(tilt = TILT) {
  color("#2a2a2e") beam_bracket();
  translate([0, PY, PZ]) rotate([-tilt, 0, 0]) translate([0, -PY, -PZ]) {
    color("#555") vesa_plate();
    // 27" 1500R curved monitor stand-in
    color("#111") translate([0, PLATE_Y + PLATE_T + 1500 + 40, PZ - 85 - 185]) rotate([0, 0, -90 - 11.8])
      rotate_extrude(angle = 23.6, $fn = 400) translate([1500, 0]) square([45, 370]);
    color("#0b1730") translate([0, PLATE_Y + PLATE_T + 1500 + 40, PZ - 85 - 175]) rotate([0, 0, -90 - 11.4])
      rotate_extrude(angle = 22.8, $fn = 400) translate([1499.5, 0]) square([1, 350]);
  }
}
