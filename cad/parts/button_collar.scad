// Raised collar for the 22 mm JUMP ENGAGE button (stops accidental hyperspace).
// Clamped under the button's front nut; a finger notch faces the Ops seat.
include <../lib/ff_lib.scad>
PART = "collar";
H = 14; OD = 44; ID = 32;
difference() {
  union() {
    cylinder(d = OD, h = 2, $fn = 96);
    cylinder(d = OD, h = H, $fn = 96);
  }
  translate([0, 0, 2]) cylinder(d = ID, h = H, $fn = 96);
  translate([0, 0, -1]) cylinder(d = 22 + FF_HOLE_COMP + 0.3, h = 5, $fn = 96);
  // finger notch
  translate([0, -OD/2, H]) rotate([0, 90, 0]) cylinder(r = 7, h = 24, center = true, $fn = 48);
}
