// Adjustable bracket for a V-15 style 15 A roller-lever micro switch
// (body ~49 x 28 x 17 mm, two M3 holes 22.2 mm apart).  Two of these make the
// seat platform's end-of-travel limit switches (UP and DOWN) in the hardwired
// actuator circuit; a third, separate switch contact can be wired to Falcon
// Command so the game can READ "seat up".  Screws to the 2x4 frame with two
// #8 wood screws in slots (+-10 mm adjustment).
include <../lib/ff_lib.scad>
PART = "bracket";
HOLE_PITCH = 22.2;
difference() {
  union() {
    cube([60, 36, 5]);                       // base on the 2x4
    translate([0, 0, 0]) cube([60, 5, 40]);  // switch plate
    for (x = [4, 52]) translate([x, 5, 5]) rotate([0, 0, 0]) hull() { cube([4, 0.01, 30]); cube([4, 25, 0.01]); }
  }
  // wood screw slots (along y = adjustment toward the platform)
  for (x = [16, 44]) translate([x, 0, -1]) hull() for (y = [14, 28]) translate([0, y, 0]) cylinder(d = 4.6, h = 10);
  // switch holes, slotted along z for fine adjustment
  for (x = [30 - HOLE_PITCH/2, 30 + HOLE_PITCH/2]) translate([x, -1, 0]) rotate([-90, 0, 0])
    hull() for (z = [-18, -30]) translate([0, z, 0]) cylinder(d = 3.3, h = 10);
}
