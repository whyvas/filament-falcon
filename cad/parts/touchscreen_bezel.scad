// Bezel frame for the 15.6" USB-C touchscreen lying almost flat between the kids
// (centre console).  The screen lies on foam pads on an 18 mm plywood tray; the
// bezel's skirt surrounds the screen and its lip overlaps the screen glass edge.
// The bezel bolts to the tray on a 40 mm grid (M5 into T-nuts).
// Total size exceeds the 220 mm bed, so it is split into 4 quadrants joined with
// half-lap joints; one grid bolt goes through every lap.
// Measure your screen and set SCR / ACTIVE / ACTIVE_OFF.
include <../lib/ff_lib.scad>
PART = "preview";       // q_fl | q_fr | q_rl | q_rr | full | preview

SCR = [359, 225, 9];     // screen outer size (typical 15.6" portable monitor)
ACTIVE = [345, 195];     // visible/touch area
ACTIVE_OFF = [0, 4];     // active-area centre offset from screen centre (+y = toward the chin)
CLR = 1.0;               // gap around the screen
BORDER = 22;             // bezel border outside the screen
TOP_T = 5;               // top plate
SKIRT_H = SCR[2] + 1;
LAP = 16;
CABLE_SIDE = 1;          // +1 = cable notch on +x side, -1 = -x side
OUT = [SCR[0] + 2*CLR + 2*BORDER, SCR[1] + 2*CLR + 2*BORDER];

// mounting holes: 40 mm grid, offset 8 mm so a hole lands in every lap joint
function hole_pts() = concat(
  [ for (x = [-OUT[0]/2 + 12 : 40 : OUT[0]/2 - 8]) for (y = [-OUT[1]/2 + BORDER/2, OUT[1]/2 - BORDER/2]) [round((x - 8) / 40) * 40 + 8, y] ],
  [ for (y = [-OUT[1]/2 + 30 : 40 : OUT[1]/2 - 20]) for (x = [-OUT[0]/2 + BORDER/2, OUT[0]/2 - BORDER/2]) [x, round((y + 8) / 40) * 40 - 8] ]);

module outline2d() offset(r = 6, $fn = 48) square([OUT[0] - 12, OUT[1] - 12], center = true);

module bezel_full() {
  difference() {
    union() {
      // top plate z = 0 .. TOP_T (top surface at z = TOP_T)
      linear_extrude(TOP_T) outline2d();
      // skirt hangs down around the screen
      translate([0, 0, -SKIRT_H]) linear_extrude(SKIRT_H + 0.01) difference() {
        outline2d();
        square([SCR[0] + 2*CLR, SCR[1] + 2*CLR], center = true);
      }
    }
    // window over the active area, chamfered
    translate([ACTIVE_OFF[0], ACTIVE_OFF[1], -1]) hull() {
      cube([ACTIVE[0] + 2, ACTIVE[1] + 2, 0.01 + 2], center = true);
      translate([0, 0, TOP_T + 1]) cube([ACTIVE[0] + 2 + 2*(TOP_T), ACTIVE[1] + 2 + 2*(TOP_T), 0.01], center = true);
    }
    // cable notch (USB-C / mini HDMI)
    translate([CABLE_SIDE * (SCR[0]/2 + CLR + BORDER/2), 0, -SKIRT_H - 1]) cube([BORDER + 2, 60, 2*(SKIRT_H - 1)], center = true);
    // M5 holes with countersink for flat heads
    for (p = hole_pts()) translate([p[0], p[1], TOP_T]) ff_countersink_m5(40);
    // engraved name on the chin
    translate([0, -OUT[1]/2 + BORDER/2 - 1, TOP_T - 0.6]) linear_extrude(1)
      text("THE FILAMENT FALCON", size = 7, halign = "center", valign = "center", font = "Liberation Sans:style=Bold");
  }
}

// lap masks: upper half (z >= TOP_T/2) splits at 0, lower half at +-LAP
module q_mask(sx, sy) {
  big = 1000;
  for (layer = [0, 1]) {
    z0 = layer == 0 ? -50 : TOP_T / 2;
    z1 = layer == 0 ? TOP_T / 2 : 50;
    xs = layer == 0 ? LAP : 0;            // lower layer: left pieces reach +LAP
    ys = layer == 0 ? -LAP : 0;           // lower layer: front pieces reach -LAP
    x0 = sx < 0 ? -big : xs;  x1 = sx < 0 ? xs : big;
    y0 = sy < 0 ? -big : ys;  y1 = sy < 0 ? ys : big;
    translate([x0, y0, z0]) cube([x1 - x0, y1 - y0, z1 - z0]);
  }
}
module quadrant(sx, sy) intersection() { bezel_full(); q_mask(sx, sy); }

// print orientation: top face down
module flip() translate([0, 0, TOP_T]) rotate([180, 0, 0]) children();
if (PART == "q_fl") flip() quadrant(-1, -1);
else if (PART == "q_fr") flip() quadrant(1, -1);
else if (PART == "q_rl") flip() quadrant(-1, 1);
else if (PART == "q_rr") flip() quadrant(1, 1);
else if (PART == "full") bezel_full();
else bezel_assembly();

module bezel_assembly() {
  color("#111") translate([-SCR[0]/2, -SCR[1]/2, -SKIRT_H]) cube(SCR);
  color("#1d3b5a") translate([ACTIVE_OFF[0] - ACTIVE[0]/2, ACTIVE_OFF[1] - ACTIVE[1]/2, -SKIRT_H + SCR[2] - 0.5]) cube([ACTIVE[0], ACTIVE[1], 0.6]);
  for (sx = [-1, 1]) for (sy = [-1, 1]) color(sx * sy > 0 ? "#2a2a2e" : "#34343a") quadrant(sx, sy);
}
