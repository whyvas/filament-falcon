// Strain-relief clamp pair for every cable bundle that crosses a pivot
// (pod pivot: 2 x video, 2 x monitor power, panel USB + LED power;
//  cradle pivot: TD2220 DVI + USB + power, cradle ESP32 USB, controls).
// Fit one clamp on the FIXED side and one on the MOVING side, each as close to the
// pivot axis as possible (<= 60 mm), with a 200 mm "U" service loop of the bundle
// in braided sleeve between them, so the pivot rotation only bends the loop (no
// pull on any connector).  The bore has soft ribs; wrap the bundle in 2 turns of
// rubber tape where it is clamped.
//   base : screws to the wood with 2 x #10 / M5 wood screws (countersunk)
//   cap  : 2 x M4 x 25 into M4 heat-set inserts in the base
// Print: PETG, 4 perimeters, 30 % infill.
include <../lib/ff_lib.scad>
PART = "preview";       // base | cap | preview
BORE = 30;              // bundle diameter (set to your bundle; 24 .. 40)
W = 34;                 // clamp width along the bundle
L = BORE + 2 * 24;      // overall length across the bundle
T = 6;                  // floor under the bore

module ribs(h) for (a = [0 : 30 : 359]) rotate([0, 0, a]) translate([BORE / 2 - 0.6, -0.8, 0]) cube([1.4, 1.6, h]);

module half(top = false) {
  difference() {
    translate([-L / 2, -W / 2, 0]) cube([L, W, T + BORE / 2]);
    translate([0, W / 2 + 1, T + BORE / 2]) rotate([90, 0, 0]) difference() {
      cylinder(d = BORE, h = W + 2, $fn = 64);
      ribs(W + 2);
    }
    // entry chamfers so the bundle is not cut by an edge when it bends
    for (s = [-1, 1]) translate([0, s * (W / 2), T + BORE / 2]) rotate([90, 0, 0]) cylinder(d1 = BORE + 8, d2 = BORE - 2, h = 5, center = true, $fn = 64);
    for (x = [-1, 1]) translate([x * (L / 2 - 11), 0, -1]) {
      if (!top) { cylinder(d = 4.2, h = 100, $fn = 24); }   // insert from the top face
      else { cylinder(d = 4.5, h = 100, $fn = 24); translate([0, 0, T + BORE / 2 - 5]) cylinder(d = 8.5, h = 100, $fn = 32); }
    }
    if (!top) for (y = [-1, 1]) translate([0, y * 0, -1]) {}
  }
}
module base() difference() {
  union() {
    half(false);
    translate([-L / 2 - 16, -W / 2, 0]) cube([L + 32, W, 5]);
  }
  for (x = [-1, 1]) translate([x * (L / 2 + 8), 0, -1]) { cylinder(d = 5.4, h = 20, $fn = 24); translate([0, 0, 5 - 2.6 + 1]) cylinder(d1 = 5.4, d2 = 10.6, h = 2.61, $fn = 32); }
  translate([0, 0, -1]) linear_extrude(1.6) mirror([1, 0, 0]) text("PIVOT", size = 6, halign = "center", valign = "center");
}
module cap() half(true);

if (PART == "base") base();
else if (PART == "cap") cap();
else {
  color("#2a2a2e") base();
  color("#3a3c42") translate([0, 0, 2 * (T + BORE / 2) + 20]) mirror([0, 0, 1]) cap();
  color("#2d3b55") translate([0, 120, T + BORE / 2]) rotate([90, 0, 0]) cylinder(d = BORE - 2, h = 240, $fn = 48);
}
