// Seam alignment pin (3 mm x 16 mm) for split panels and the touchscreen bezel.
// A 3 mm steel dowel or a cut 3 mm aluminium rod is better if you have one.
// Printed lying down with a flat so it needs no support; print a few spares.
include <../lib/ff_lib.scad>
PART = "pin";
N = 8;
for (i = [0 : N - 1]) translate([0, i * 6, 0])
  intersection() {
    translate([0, 0, FF_PIN_D/2 - 0.3]) rotate([0, 90, 0])
      hull() { translate([0, 0, 0.4]) cylinder(d = FF_PIN_D - 0.1, h = 15.2, $fn = 32);
               cylinder(d = FF_PIN_D - 0.9, h = 16, $fn = 32); }
    translate([-1, -5, 0]) cube([20, 10, 10]);
  }
