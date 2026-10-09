// Electronics enclosure for one ESP32-S3-DevKitC-1 (Falcon Pilot / Ops / Command).
// The DevKitC-1 has no mounting holes, so it plugs into female headers on a
// standard 70 x 90 mm perfboard (holes 2 mm from the edges), together with the
// 74HC165 / MCP23017 boards.  The perfboard sits on 4 standoffs (M2.5 self-tap).
// Both USB-C ports of the DevKit face the -x end wall slot.
// Screw tabs: M5 on a 40 mm grid (120 mm apart) into T-nuts, or #8 wood screws.
include <../lib/ff_lib.scad>
PART = "preview";        // base | lid | preview
NAME = "COMMAND";        // PILOT | OPS | COMMAND (engraved on the lid)

PCB = [90, 70, 1.6];     // perfboard
PCB_HOLES = [[3.5, 3.5], [86.5, 3.5], [3.5, 66.5], [86.5, 66.5]];
CLR = 3;                 // inside clearance around the PCB
WALL = 2.4;
FLOOR = 2.4;
STANDOFF = 6;
INNER_H = 34;            // DevKit on headers + wiring
IN = [PCB[0] + 2*CLR, PCB[1] + 2*CLR];
OUTS = [IN[0] + 2*WALL, IN[1] + 2*WALL];
H = FLOOR + INNER_H;
LID_T = 2.4;

module esp_base() {
  difference() {
    union() {
      ff_rounded_box([OUTS[0], OUTS[1], H], 4);
      // screw tabs on the short ends, 120 mm apart on the 40 mm grid
      for (s = [-1, 1]) hull() {
        translate([OUTS[0]/2 + s * 60, OUTS[1]/2, 0]) cylinder(d = 14, h = 4);
        translate([s > 0 ? OUTS[0] - 1 : 0, OUTS[1]/2 - 15, 0]) cube([1, 30, 4]);
      }
    }
    translate([WALL, WALL, FLOOR]) ff_rounded_box([IN[0], IN[1], H], 2);
    for (s = [-1, 1]) translate([OUTS[0]/2 + s * 60, OUTS[1]/2, -1]) cylinder(d = FF_M5_D, h = 10);
    // USB-C x2 (DevKit end) on the -x wall
    translate([-1, OUTS[1]/2 - 16, FLOOR + STANDOFF + PCB[2] + 6]) cube([WALL + 2, 32, 11]);
    // cable slots: two on +x wall, one on each long wall
    translate([OUTS[0] - WALL - 1, OUTS[1]/2 - 25, H - 14]) cube([WALL + 2, 50, 15]);
    for (y = [-1, OUTS[1] - WALL - 1]) translate([OUTS[0]/2 - 20, y, H - 12]) cube([40, WALL + 2, 13]);
    // lid screw holes (M3 self-tap) in corner bosses
    for (p = [[6, 6], [OUTS[0] - 6, 6], [6, OUTS[1] - 6], [OUTS[0] - 6, OUTS[1] - 6]])
      translate([p[0], p[1], H - 12]) cylinder(d = 2.6, h = 13);
  }
  // PCB standoffs
  for (p = PCB_HOLES) translate([WALL + CLR + p[0], WALL + CLR + p[1], FLOOR - 0.01]) difference() {
    cylinder(d = 6, h = STANDOFF); cylinder(d = 2.2, h = STANDOFF + 1);
  }
  // lid screw corner bosses
  difference() {
    for (p = [[6, 6], [OUTS[0] - 6, 6], [6, OUTS[1] - 6], [OUTS[0] - 6, OUTS[1] - 6]])
      translate([p[0], p[1], H - 14]) { cylinder(d = 9, h = 14); translate([0, 0, -7]) cylinder(d1 = 0.5, d2 = 9, h = 7.01); }
    for (p = [[6, 6], [OUTS[0] - 6, 6], [6, OUTS[1] - 6], [OUTS[0] - 6, OUTS[1] - 6]])
      translate([p[0], p[1], H - 12]) cylinder(d = 2.6, h = 13);
  }
  // cable tie anchors
  for (x = [20, OUTS[0] - 20]) translate([x - 6, OUTS[1] - WALL - 5, FLOOR]) difference() {
    cube([12, 5, 8]); translate([-1, 1, 2.5]) cube([14, 3, 3]);
  }
}

module esp_lid() {
  difference() {
    union() {
      ff_rounded_box([OUTS[0], OUTS[1], LID_T], 4);
      // locating lip
      translate([WALL + 0.3, WALL + 0.3, LID_T - 0.01]) difference() {
        ff_rounded_box([IN[0] - 0.6, IN[1] - 0.6, 3], 2);
        translate([1.6, 1.6, -1]) ff_rounded_box([IN[0] - 3.8, IN[1] - 3.8, 5], 1);
        for (p = [[6, 6], [OUTS[0] - 6, 6], [6, OUTS[1] - 6], [OUTS[0] - 6, OUTS[1] - 6]])
          translate([p[0] - WALL - 0.3, p[1] - WALL - 0.3, -1]) cylinder(d = 9, h = 5);
      }
    }
    for (p = [[6, 6], [OUTS[0] - 6, 6], [6, OUTS[1] - 6], [OUTS[0] - 6, OUTS[1] - 6]])
      translate([p[0], p[1], -1]) { cylinder(d = 3.4, h = 10); cylinder(d1 = 6.6, d2 = 3.4, h = 2.2); }
    // vents
    for (i = [0 : 7]) translate([OUTS[0] - 30 + 0, 12 + i * 7, -1]) cube([18, 3, 10]);
    // engraved name (reads correctly from outside: lid prints outside-down)
    translate([(OUTS[0] - 32)/2, OUTS[1]/2, -0.01]) mirror([1, 0, 0])
      linear_extrude(0.81) text(str("FALCON ", NAME), size = 5, halign = "center", valign = "center",
                                font = "Liberation Sans:style=Bold");
  }
}

if (PART == "base") esp_base();
else if (PART == "lid") esp_lid();
else {
  color("#2a2a2e") esp_base();
  color("#3a3a40") translate([0, OUTS[1], H + LID_T + 0.01]) rotate([180, 0, 0]) esp_lid();
}
