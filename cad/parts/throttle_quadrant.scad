// Throttle quadrant for the PILOT_SIDE panel.
// Local origin = centre of the throttle slot on the panel FRONT face, z up,
// +y = forward (MAX).  The housing hangs between the two plywood rails of the
// side console and is screwed into the rails' inner edges (4 x #8 / 4 mm wood screws).
// Lever pivots on an M6 bolt (left) and drives a 16 mm pot with a 6 mm D shaft (right).
// Parts: housing, lever, grip.  Hardware: M6x30 bolt + nylock + 2 washers,
// 10k linear pot (16 mm, M7 bushing, 6 mm D shaft >= 15 mm), M4x20 screw.
include <../lib/ff_lib.scad>
PART = "preview";       // housing | lever | grip | preview
ANGLE = 0;              // lever angle for preview (-29 .. +29)

AX_Z  = -70;            // pivot depth below panel front
IN_X  = 14;             // inner half width
WALL  = 5;
OUT_X = IN_X + WALL;
LEN_Y = 60;             // half length: matches rail edges (panel y 20..140)
TOP_Z = -9.5;           // stays clear of the panel's back rib
BOT_Z = AX_Z - 22;
HUB_D = 26;
LEV_T = 10;             // lever thickness (x) - slot is 14 wide
LEV_W = 12;             // lever width (y)
LEV_TOP = 58;           // lever top above panel front
POT_TAB_R = 7.8;        // anti-rotation tab radius on common 16 mm pots

module thr_housing() {
  difference() {
    union() {
      // side walls
      for (s = [-1, 1]) translate([s > 0 ? IN_X : -OUT_X, -LEN_Y, BOT_Z]) cube([WALL, 2*LEN_Y, TOP_Z - BOT_Z]);
      // floor
      translate([-OUT_X, -LEN_Y, BOT_Z]) cube([2*OUT_X, 2*LEN_Y, 4]);
      // end walls (screwed to the rails' inner edges)
      for (s = [-1, 1]) translate([-OUT_X, s > 0 ? LEN_Y - 5 : -LEN_Y, BOT_Z]) cube([2*OUT_X, 5, TOP_Z - BOT_Z]);
      // pivot bosses
      for (s = [-1, 1]) translate([s * (OUT_X + 2) , 0, AX_Z]) rotate([0, 90, 0]) cylinder(d = 22, h = 4, center = true);
    }
    // inner clearance for the hub
    // M6 pivot bolt (left)
    translate([-OUT_X - 10, 0, AX_Z]) rotate([0, 90, 0]) cylinder(d = 6.5, h = 20);
    // pot bushing + anti-rotation tab (right)
    translate([IN_X - 1, 0, AX_Z]) rotate([0, 90, 0]) cylinder(d = 7 + FF_HOLE_COMP + 0.2, h = 20);
    translate([IN_X + WALL/2, 0, AX_Z + POT_TAB_R]) cube([WALL + 6, 1.6, 3.2], center = true);
    // rail screws: 2 per end, countersunk from inside
    for (s = [-1, 1]) for (x = [-9, 9]) translate([x, s * (LEN_Y - 5), -15])
      rotate([s > 0 ? -90 : 90, 0, 0]) {
        translate([0, 0, -12]) cylinder(d = 4.4, h = 30);
        cylinder(d1 = 9, d2 = 4.4, h = 2.3);
        translate([0, 0, -12]) cylinder(d = 9, h = 12.01);
      }
    // wiring exit
    translate([0, -LEN_Y + 20, BOT_Z - 1]) cylinder(d = 12, h = 6);
    // weight-saving windows in side walls (below the pivot reach)
    for (s = [-1, 1]) for (y = [-36, 36]) translate([s * (IN_X + WALL/2), y, AX_Z + 12]) cube([WALL + 2, 22, 34], center = true);
  }
}

module thr_lever() {
  difference() {
    union() {
      translate([-(2*IN_X - 2)/2, 0, AX_Z]) rotate([0, 90, 0]) cylinder(d = HUB_D, h = 2*IN_X - 2);
      translate([-LEV_T/2, -LEV_W/2, AX_Z]) cube([LEV_T, LEV_W, LEV_TOP - AX_Z]);
    }
    // M6 stub axle (blind, left)
    translate([-IN_X - 1, 0, AX_Z]) rotate([0, 90, 0]) cylinder(d = 6.3, h = 12);
    // pot 6 mm D-shaft socket (right)
    translate([IN_X - 11, 0, AX_Z]) rotate([0, 90, 0]) intersection() {
      cylinder(d = 6.25, h = 12);
      translate([-3.5, -3.5 + 1.75, 0]) cube([7, 7, 12]);   // flat at 4.6 mm
    }
    // grip screw
    translate([0, 0, LEV_TOP - 18]) cylinder(d = 3.4, h = 20);
  }
}

module thr_grip() {
  difference() {
    hull() {
      for (x = [-16, 16]) translate([x, 0, 0]) scale([1, 1, 1]) cylinder(d = 22, h = 4, $fn = 64);
      for (x = [-14, 14]) translate([x, 2, 26]) sphere(d = 18, $fn = 48);
    }
    translate([-LEV_T/2 - 0.25, -LEV_W/2 - 0.25, -1]) cube([LEV_T + 0.5, LEV_W + 0.5, 17]);
    translate([0, 0, -1]) cylinder(d = 4.5, h = 50);
    translate([0, 0, 31]) cylinder(d = 8.5, h = 20);
    // finger grooves on the front
    for (x = [-12, 0, 12]) translate([x, 13, 18]) rotate([90, 0, 0]) cylinder(d = 8, h = 6, center = true);
  }
}

if (PART == "housing") translate([0, 0, -BOT_Z]) thr_housing();
else if (PART == "lever") rotate([0, 90, 0]) translate([LEV_T/2, 0, 0]) thr_lever();
else if (PART == "grip") thr_grip();
else throttle_assembly();

module throttle_assembly() {
  color("#2a2a2e") thr_housing();
  translate([0, 0, AX_Z]) rotate([ANGLE, 0, 0]) translate([0, 0, -AX_Z]) {
    color("#666") thr_lever();
    color("#d33") translate([0, 0, LEV_TOP - 16]) thr_grip();
  }
  color("silver") translate([OUT_X + 4, 0, AX_Z]) rotate([0, 90, 0]) cylinder(d = 16, h = 10);
}
