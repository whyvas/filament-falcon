// 4-point harness hub for 1" (25 mm webbing) side-release buckles, e.g. the kit at
// amazon.ca/dp/B0B3J1GCVQ.  Two SHOULDER straps come in diagonally from above, two
// LAP straps from the sides, the CROTCH / anchor strap leaves through the loop hole
// at the bottom.  The hub houses the buckles' OWN female latch bodies (no printed
// latches).
//
// LOAD PATH (the printed part carries NO strap load):
//   strap -> male tongue -> buckle's female body -> its webbing bar -> a short sewn
//   webbing loop -> STEEL O-RING (welded, 50 mm OD, 6 mm wire) in the hub centre ->
//   crotch / anchor strap (looped round the same ring) -> eye bolt in the cradle deck.
//   The housing only holds the 4 female bodies in their directions so a kid can
//   click in by feel.  Alternative to the ring: a 4 mm steel plate with 5 slots.
//
// Base + lid, 5 x M3 x 20 screws into M3 heat-set inserts.  All buckle and ring
// sizes below are parameters: MEASURE your buckles (kits differ by +-1 mm) and set
// BW / BL / BT / MOUTH, then print one test base.
// Print: PETG (not PLA: creep + brittle when cold), 6 perimeters, 5 top / 5 bottom
// layers, 40-50 % gyroid, 0.2 mm layers.  Base floor-down, lid flat.  No supports.
//
// SAFETY: this is a POSITIONING harness for a slow-moving home cockpit, NOT a
// crash-rated restraint.  The POM luggage buckles in that kit are not certified
// for life-safety loads (sellers quote ~50 kg); see docs/mechanical/README.md.
include <../lib/ff_lib.scad>
PART = "preview";     // base | lid | preview

// buckle (female body) - measure yours
BW = 35.0;            // female body width
BL = 33.0;            // female body length (mouth .. webbing bar end)
BT = 13.0;            // thickness
MOUTH = 13.0;         // length of the female that stays OUTSIDE the hub (side release windows)
WEB = 25.4;           // webbing width
CLR = 0.4;
// steel ring
RING_OD = 50.0; RING_WIRE = 6.0;
// layout
SH_ANG = 30;          // shoulder straps: degrees from vertical
DIRS = [0, 90 - SH_ANG, 90 + SH_ANG, 180];        // lap R, shoulder R, shoulder L, lap L
CROTCH = 270;
FLOOR = 3.0; LIDT = 3.0; WALL = 4.5;
H = FLOOR + BT + 1.0;                                  // base height (to the lid)
CH_R = RING_OD / 2 + RING_WIRE + 3;                  // central chamber radius (ring + webbing loops)
R_IN = max(CH_R + 9, (BW / 2 + WALL + 2) / sin((90 - SH_ANG) / 2));   // buckle pocket inner end
R_OUT = R_IN + BL - MOUTH;                           // hub edge along each strap
SCREWS = [[30, R_IN + 3], [90, R_IN + 3], [150, R_IN + 3], [215, CH_R + 9], [325, CH_R + 9]];

module along(a) rotate([0, 0, a]) children();
module lobe2d(a, len, half) along(a) translate([0, -half]) square([len, 2 * half]);
module outline2d() offset(r = 3, $fn = 24) offset(delta = -3) union() {
  circle(r = CH_R + WALL + 2, $fn = 96);
  for (a = DIRS) hull() { circle(r = CH_R, $fn = 64); lobe2d(a, R_OUT, BW / 2 + CLR + WALL); }
  hull() { circle(r = CH_R, $fn = 64); lobe2d(CROTCH, CH_R + 14, WEB / 2 + 2 + WALL); }
  for (s = SCREWS) along(s[0]) translate([s[1], 0]) circle(r = 5.5, $fn = 32);
}

module base() {
  difference() {
    linear_extrude(H) outline2d();
    // central chamber
    translate([0, 0, FLOOR]) cylinder(r = CH_R, h = H, $fn = 96);
    for (a = DIRS) along(a) {
      // buckle pocket (open to the outside and to the lid)
      translate([R_IN, -BW / 2 - CLR, FLOOR]) cube([BL + 20, BW + 2 * CLR, H]);
      // webbing channel chamber -> pocket
      translate([CH_R - 5, -WEB / 2 - 1.5, FLOOR]) cube([R_IN - CH_R + 6, WEB + 3, H]);
      // (the female is held IN by its own webbing tail to the ring; the lid clamps it flat)
    }
    // crotch / anchor strap loop hole (bottom)
    along(CROTCH) translate([CH_R - 5, -WEB / 2 - 2, FLOOR]) cube([40, WEB + 4, H]);
    // insert holes
    for (s = SCREWS) along(s[0]) translate([s[1], 0, H - 6]) cylinder(d = 4.2, h = 7, $fn = 24);
    // label on the bottom (mirrored so it reads from the back)
    translate([0, -CH_R / 2, -0.01]) mirror([1, 0, 0]) linear_extrude(0.6) text("RING INSIDE", size = 5, halign = "center", font = "Liberation Sans:style=Bold");
  }
}

module lid() {
  difference() {
    linear_extrude(LIDT) outline2d();
    for (s = SCREWS) along(s[0]) translate([s[1], 0, -1]) { cylinder(d = 3.4, h = 10, $fn = 20); translate([0, 0, LIDT - 1.6 + 1]) cylinder(d = 6.2, h = 5, $fn = 24); }
    // crotch slot continues through the lid edge so the loop can be threaded with the lid on
    along(CROTCH) translate([CH_R + 6, -WEB / 2 - 2, -1]) cube([30, WEB + 4, 10]);
    translate([0, 8, LIDT - 0.6]) linear_extrude(1) text("PUSH TO CLICK", size = 6, halign = "center", font = "Liberation Sans:style=Bold");
    translate([0, -4, LIDT - 0.6]) linear_extrude(1) text("FALCON CREW", size = 5, halign = "center", font = "Liberation Sans");
  }
}

// ------------------------------------------------------------- preview stand-ins
module female_standin() color("#e0e0e0") difference() {
  translate([0, -BW / 2, 0]) cube([BL, BW, BT]);
  translate([BL - 18, -BW / 2 + 4, 2]) cube([20, BW - 8, BT - 4]);
}
module male_standin() color("#9a9a9a") {
  translate([BL - 18, -BW / 2 + 4.5, 2.5]) cube([22, BW - 9, BT - 5]);
  translate([BL + 4, -BW / 2, 0]) cube([18, BW, BT]);
}
module web(len) color("#c0392b") translate([0, -WEB / 2, BT / 2 - 1]) cube([len, WEB, 2]);
module ring_standin() color("#b8bcc2") translate([0, 0, FLOOR + RING_WIRE / 2 + 0.5]) rotate_extrude($fn = 96) translate([RING_OD / 2 - RING_WIRE / 2, 0]) circle(d = RING_WIRE, $fn = 24);

module hub_assembly(show_lid = true, explode = 0) {
  color("#5a5e66") base();
  ring_standin();
  for (a = DIRS) along(a) {
    translate([R_IN, 0, FLOOR]) { female_standin(); male_standin(); translate([BL + 22, 0, 0]) web(35); }
    translate([RING_OD / 2 - 3, 0, FLOOR]) web(R_IN - RING_OD / 2 + 6);
  }
  along(CROTCH) translate([RING_OD / 2 - 3, 0, FLOOR]) web(75);
  if (show_lid) color("#2B2D33", 0.9) translate([0, 0, H + 0.2 + explode]) lid();
}

if (PART == "base") base();
else if (PART == "lid") translate([0, 0, LIDT]) mirror([0, 0, 1]) lid();
else if (PART == "preview_open") hub_assembly(false);
else hub_assembly(true, 22);
echo(str("hub R_IN=", R_IN, " R_OUT=", R_OUT, " H=", H));
