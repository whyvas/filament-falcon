// Screw-down cable clips for the plywood frame (one #6/#8 wood screw each).
// Bundle sizes 6, 10, 16, 24 mm; plus a flat clip for the 12 mm WS2812B strip
// jumpers / ribbon.  PART = "set" prints 2 of each on one plate.
include <../lib/ff_lib.scad>
PART = "set";
SIZES = [6, 10, 16, 24];

module clip(d) {
  w = 12; t = 2.4;
  difference() {
    union() {
      translate([-(d/2 + t + 12), -w/2, 0]) cube([d + 2*t + 12, w, t]);
      translate([0, 0, d/2 + 0.5]) rotate([90, 0, 0]) cylinder(d = d + 2*t, h = w, center = true);
    }
    translate([0, 0, d/2 + 0.5]) rotate([90, 0, 0]) cylinder(d = d, h = w + 2, center = true);
    translate([-(d + 2*t + 4), -w, -10]) cube([2*d + 4*t + 8, 2*w, 10]);   // flat base
    translate([d/2 + t - 0.01, -w, -0.01]) cube([20, 2*w, 30]);              // open side
    translate([-(d/2 + t + 6), 0, -1]) { cylinder(d = 4.2, h = 10); translate([0, 0, t - 1.6]) cylinder(d1 = 4.2, d2 = 8.4, h = 1.61); }
  }
}
module strip_clip() {
  difference() {
    translate([-14, -6, 0]) cube([28, 12, 5]);
    translate([-7, -7, -0.01]) cube([14, 14, 3]);
    for (x = [-10.5, 10.5]) translate([x, 0, -1]) { cylinder(d = 3.8, h = 10); translate([0, 0, 3.4]) cylinder(d1 = 3.8, d2 = 7.5, h = 1.61); }
  }
}
if (PART == "set") {
  for (i = [0 : len(SIZES) - 1]) for (j = [0, 1]) translate([j * 60, i * 22 + (i > 2 ? 6 : 0), 0]) clip(SIZES[i]);
  for (j = [0, 1, 2]) translate([j * 34, -24, 0]) strip_clip();
} else if (PART == "strip") strip_clip();
else clip(10);
