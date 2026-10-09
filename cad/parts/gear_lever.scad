// Landing gear lever for the PILOT_SIDE panel.
// Local origin = centre of the gear slot on the panel FRONT face, z up, +y = forward (UP).
// The box hangs from the panel on 4 x M3x12 countersunk screws (holes are in the panel)
// that self-tap into the box corners.  The lever pivots on an M4x40 bolt + nylock; tighten
// for friction so it stays put.  Two KW11 micro switches (20 x 10 x 6.4 mm, 9.5 mm hole
// spacing, M2 screws) on the floor read GEAR UP / GEAR DOWN; the slot ends are the stops.
include <../lib/ff_lib.scad>
PART = "preview";     // box | lever | knob | preview
ANGLE = 20;           // preview lever angle, +-20 (switch trip), slot stop ~ +-22

BX = 15; BY = 40;     // outer half sizes (panel keep-out 30 x 80)
TOP = -3.2;           // touches panel back
AX = -30;             // pivot depth
FLOOR = -62;
W = 2.5;
LT = 8; LW = 10;      // lever section (slot is 12 wide)
TAIL = 26;            // tail length below the pivot
SW = [20, 10, 6.4];   // KW11 body
SW_Y = 9.6;           // plunger line distance from centre

module gear_box() {
  difference() {
    union() {
      difference() {
        translate([-BX, -BY, FLOOR]) cube([2*BX, 2*BY, TOP - FLOOR]);
        translate([-BX + W, -BY + W, FLOOR + 3]) cube([2*BX - 2*W, 2*BY - 2*W, 100]);
      }
      // corner screw posts
      for (x = [-10, 10]) for (y = [-36, 36]) translate([x, y, FLOOR]) cylinder(d = 9, h = TOP - FLOOR);
    }
    for (x = [-10, 10]) for (y = [-36, 36]) translate([x, y, TOP - 14]) cylinder(d = 2.6, h = 15);
    // pivot
    translate([-BX - 1, 0, AX]) rotate([0, 90, 0]) cylinder(d = 4.3, h = 2*BX + 2);
    // micro switch screw holes (M2) in the floor
    for (s = [-1, 1]) for (x = [-4.75, 4.75]) translate([x, s * (SW_Y + 1.2 + 5), FLOOR - 1]) cylinder(d = 2.1, h = 10);
    // wire exit
    translate([0, BY - 10, FLOOR - 1]) cylinder(d = 8, h = 5);
  }
}

module gear_lever_arm() {
  difference() {
    union() {
      hull() {
        translate([-LT/2, 0, AX]) rotate([0, 90, 0]) cylinder(d = 14, h = LT);
        translate([-LT/2, -LW/2, AX - TAIL]) cube([LT, LW, 1]);
      }
      translate([-LT/2, -LW/2, AX]) cube([LT, LW, 52 - AX]);
    }
    translate([-LT, 0, AX]) rotate([0, 90, 0]) cylinder(d = 4.3, h = 2*LT);
    translate([0, 0, 52 - 12]) cylinder(d = 2.6, h = 13);
  }
}

// classic landing-gear wheel knob
module gear_knob() {
  difference() {
    rotate([0, 90, 0]) difference() {
      cylinder(d = 36, h = 16, center = true, $fn = 96);
      for (a = [0 : 15 : 359]) rotate([0, 0, a]) translate([18, 0, 0]) cube([3, 3.5, 20], center = true);
      for (s = [-1, 1]) translate([0, 0, s * 8]) cylinder(d = 24, h = 3, center = true, $fn = 64);
    }
    translate([-LT/2 - 0.25, -LW/2 - 0.25, -19]) cube([LT + 0.5, LW + 0.5, 13]);
    translate([0, 0, -20]) cylinder(d = 3.4, h = 40);
    translate([0, 0, 14]) cylinder(d = 6.5, h = 10);
  }
}

if (PART == "box") translate([0, 0, -FLOOR]) gear_box();
else if (PART == "lever") rotate([0, 90, 0]) translate([LT/2, 0, 0]) gear_lever_arm();
else if (PART == "knob") rotate([0, 90, 0]) gear_knob();
else gear_assembly();

module gear_assembly() {
  color("#2a2a2e") gear_box();
  translate([0, 0, AX]) rotate([-ANGLE, 0, 0]) translate([0, 0, -AX]) { color("#999") gear_lever_arm(); color("#eee") translate([0, 0, 52 + 12]) gear_knob(); }
  for (s = [-1, 1]) color("#226") translate([-SW[0]/2, s > 0 ? SW_Y + 1.2 : -SW_Y - 1.2 - SW[1], FLOOR + 3]) cube(SW);
}
