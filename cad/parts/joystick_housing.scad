// Joystick base housing + parametric adapter plate for the owner's existing
// 3-axis joysticks (X, Y, twist Z + top button, bare wires).
// The mounting pattern is unknown, so the adapter has 8 radial slots (M3/M4)
// covering bolt circles from SLOT_R0 to SLOT_R1, plus a 4-hole square pattern
// you can set with SQ_PITCH once you measure the joystick.  The centre hole
// clears the joystick body / rubber boot.
// The housing bolts to the plywood side console with 4 x M5 on the 40 mm grid
// (120 mm apart) into T-nuts.
include <../lib/ff_lib.scad>
PART = "preview";     // housing | adapter | preview

OUT = 104;            // housing outer (x and y)
HGT = 90;             // housing height
WALL = 3.2;
FLANGE = 136;         // foot flange size; M5 holes at +-60 (40 mm grid)
TOP_RECESS = 3;       // adapter sits flush in a recess
ADAPTER_T = 5;
CENTER_D = 46;        // clearance hole for joystick body
SLOT_R0 = 22; SLOT_R1 = 44; SLOT_W = 4.4;   // radial slots (bolt circle range)
N_SLOTS = 8;
SQ_PITCH = 0;         // set e.g. 50 for a 50 x 50 square pattern (0 = none)
SQ_HOLE = 4.4;
CABLE_D = 14;

module js_housing() {
  difference() {
    union() {
      translate([-OUT/2, -OUT/2, 0]) ff_rounded_box([OUT, OUT, HGT], 6);
      translate([-FLANGE/2, -FLANGE/2, 0]) ff_rounded_box([FLANGE, FLANGE, 5], 8);
      // corner gussets
      for (a = [0 : 90 : 270]) rotate([0, 0, a]) translate([OUT/2 - 1, -3, 0])
        hull() { cube([1, 6, 30]); cube([(FLANGE - OUT)/2, 6, 5]); }
    }
    translate([-OUT/2 + WALL, -OUT/2 + WALL, 4]) ff_rounded_box([OUT - 2*WALL, OUT - 2*WALL, HGT], 4);
    // adapter recess
    translate([-(OUT - 2*WALL + 6)/2 - 0.2, -(OUT - 2*WALL + 6)/2 - 0.2, HGT - TOP_RECESS])
      ff_rounded_box([OUT - 2*WALL + 6.4, OUT - 2*WALL + 6.4, 10], 4);
    // M5 frame bolts on the 40 mm grid
    for (x = [-60, 60]) for (y = [-60, 60]) translate([x, y, -1]) cylinder(d = FF_M5_D, h = 10);
    // adapter screws (M4 self-tapping into corner posts)
    for (x = [-1, 1]) for (y = [-1, 1]) translate([x * (OUT/2 - 9), y * (OUT/2 - 9), HGT - 30]) cylinder(d = 3.5, h = 40);
    // cable exit at the back (-y) + zip-tie bar
    translate([0, -OUT/2 - 1, 16]) rotate([-90, 0, 0]) cylinder(d = CABLE_D, h = 10);
    // floor drain/lightening
    translate([0, 0, -1]) cylinder(d = 50, h = 10);
  }
  // corner posts for the adapter screws
  difference() {
    for (x = [-1, 1]) for (y = [-1, 1]) translate([x * (OUT/2 - 9), y * (OUT/2 - 9), 4])
      cylinder(d = 10, h = HGT - TOP_RECESS - 4);
    for (x = [-1, 1]) for (y = [-1, 1]) translate([x * (OUT/2 - 9), y * (OUT/2 - 9), HGT - 30]) cylinder(d = 3.5, h = 40);
  }
  // zip-tie anchor inside, next to the cable exit
  translate([0, -OUT/2 + WALL + 4, 4]) difference() {
    translate([-8, -3, 0]) cube([16, 6, 10]);
    translate([-10, -1.5, 3]) cube([20, 3, 4]);
  }
}

module js_adapter() {
  S = OUT - 2*WALL + 6;
  difference() {
    translate([-S/2, -S/2, 0]) ff_rounded_box([S, S, ADAPTER_T], 4);
    translate([0, 0, -1]) cylinder(d = CENTER_D, h = 10, $fn = 96);
    for (i = [0 : N_SLOTS - 1]) rotate([0, 0, i * 360 / N_SLOTS]) translate([0, 0, -1])
      hull() for (r = [max(SLOT_R0, CENTER_D/2 + 4), SLOT_R1]) translate([r, 0, 0]) cylinder(d = SLOT_W, h = 10);
    if (SQ_PITCH > 0) for (x = [-1, 1]) for (y = [-1, 1]) translate([x * SQ_PITCH/2, y * SQ_PITCH/2, -1]) cylinder(d = SQ_HOLE, h = 10);
    for (x = [-1, 1]) for (y = [-1, 1]) translate([x * (OUT/2 - 9), y * (OUT/2 - 9), -1]) {
      cylinder(d = 4.5, h = 10); translate([0, 0, ADAPTER_T - 2.4]) cylinder(d1 = 4.5, d2 = 9, h = 2.41);
    }
  }
}

if (PART == "housing") js_housing();
else if (PART == "adapter") js_adapter();
else joystick_assembly();

module joystick_assembly() {
  color("#2a2a2e") js_housing();
  color("#555") translate([0, 0, HGT - TOP_RECESS]) js_adapter();
  // stand-in joystick
  color("#111") translate([0, 0, HGT]) { cylinder(d = 40, h = 8); translate([0, 0, 8]) cylinder(d1 = 34, d2 = 16, h = 20);
    translate([0, 0, 28]) cylinder(d = 14, h = 60); translate([0, 0, 88]) scale([1, 1.2, 1.6]) sphere(d = 30); }
  color("red") translate([0, 0, HGT + 108]) cylinder(d = 10, h = 6);
}
