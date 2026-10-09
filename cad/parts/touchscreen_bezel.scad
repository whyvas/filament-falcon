// Centre console touchscreen: ViewSonic TD2220 (21.5", 1920x1080, optical 2-point
// touch over USB-B, VESA 100, inputs VGA + DVI-D).
//   TD2220 (without stand): 511.5 x 310.4 x 66.5 mm, 4.0 kg, active area ~476 x 268 mm.
// The screen lies (near) flat in a cut-out of the cradle's centre console top,
// screwed to a printed VESA riser on an internal plywood shelf.  This printed TRIM
// RING only closes the gap between the screen's outer edge and the plywood cut-out.
// It NEVER overlaps the screen's front: the TD2220's optical (IR) touch sensors sit in
// its bezel and look across the glass, so anything raised over the bezel/glass
// blocks touches.  The ring top is 1 mm BELOW the screen's front plane.
// Ring outer size 558.5 x 357.4 mm -> 6 printable pieces (all <= 220 mm):
//   4 corner L's (200 x 179) + 2 straight middles (159 long) on the long sides,
//   half-lap joints, one M4 countersunk wood screw through every lap.
// Coordinates: z = 0 is the plywood console top; +x = kids' right; +y = forward
// (toward the pod) = the TOP edge of the picture.  Ports are on the rear (-y) edge.
include <../lib/ff_lib.scad>
PART = "preview";   // c_fl | c_fr | c_rl | c_rr | m_f | m_r | riser | full | preview

TD = [511.5, 310.4, 66.5];      // outer size, depth incl. back
ACTIVE = [476.6, 268.1];
GAP = 1.5;                       // screen edge -> ring inner edge
CUT = 8;                         // screen edge -> plywood cut-out edge
BW = 22;                         // ring width from its inner edge
RT = 4;                          // ring flange thickness (sits on the plywood)
FACE_Z = RT + 1;                 // screen front plane (1 mm proud of the ring)
SK_T = CUT - GAP - 1.5;          // skirt in the gap
SK_D = 15;
LAP = 16;
IN = [TD[0] + 2*GAP, TD[1] + 2*GAP];
OUT = [IN[0] + 2*BW, IN[1] + 2*BW];
XJ = OUT[0]/2 - 200;             // joints on the long sides at x = +-XJ (corner arm = 200)
TILT = 0;                        // riser tilt (deg): 0 = flat in the cradle (faces the reclined kids)
SHELF_Z = -(TD[2] - FACE_Z) - 40;   // top of the internal plywood shelf

module ring2d() difference() {
  offset(r = 4, $fn = 32) square([OUT[0] - 8, OUT[1] - 8], center = true);
  square(IN, center = true);
}
module skirt2d() difference() {
  square([IN[0] + 2*SK_T, IN[1] + 2*SK_T], center = true);
  square(IN, center = true);
}
function screw_pts() = concat(
  [for (x = [-XJ - LAP/2, XJ + LAP/2]) for (y = [-1, 1]) [x, y * (IN[1]/2 + BW/2 + 3)]],
  [for (y = [LAP/2]) for (x = [-1, 1]) [x * (IN[0]/2 + BW/2 + 3), y]],
  [for (x = [-OUT[0]/2 + 40, OUT[0]/2 - 40]) for (y = [-1, 1]) [x, y * (IN[1]/2 + BW/2 + 3)]],
  [for (y = [-OUT[1]/2 + 60, OUT[1]/2 - 60]) for (x = [-1, 1]) [x * (IN[0]/2 + BW/2 + 3), y]]);

module ring_full() {
  difference() {
    union() {
      linear_extrude(RT) ring2d();
      translate([0, 0, -SK_D]) linear_extrude(SK_D + 0.01) skirt2d();
    }
    for (p = screw_pts()) translate([p[0], p[1], RT]) {
      translate([0, 0, -30]) cylinder(d = 4.4, h = 40, $fn = 20);
      translate([0, 0, -2.2]) cylinder(d1 = 4.4, d2 = 8.8, h = 2.21, $fn = 32);
      cylinder(d = 8.8, h = 5, $fn = 32);
    }
    // cable notch at the rear edge (ports exit downward into the console)
    translate([0, -IN[1]/2 - SK_T/2, -SK_D - 1]) cube([120, SK_T + 2, 2 * SK_D], center = true);
    translate([0, -OUT[1]/2 + BW/2 - 2, RT - 0.6]) linear_extrude(1)
      text("THE FILAMENT FALCON", size = 7, halign = "center", valign = "center", font = "Liberation Sans:style=Bold");
  }
}

// region masks with half laps: upper layer (z >= RT/2) splits on the joint line,
// lower layer + skirt splits LAP further on (so every joint overlaps by LAP)
module region(xa, xb, ya, yb) translate([xa, ya, -100]) cube([xb - xa, yb - ya, 200]);
BIG = 1000;
module piece(name) {
  // upper / lower limits per piece: [x0, x1, y0, y1] for each layer
  up = name == "c_fl" ? [-BIG, -XJ, 0, BIG] : name == "c_fr" ? [XJ, BIG, 0 + LAP, BIG]
     : name == "c_rl" ? [-BIG, -XJ, -BIG, 0] : name == "c_rr" ? [XJ, BIG, -BIG, 0 + LAP]
     : name == "m_f" ? [-XJ, XJ, 0, BIG] : [-XJ, XJ, -BIG, 0];
  lo = name == "c_fl" ? [-BIG, -XJ - LAP, LAP, BIG] : name == "c_fr" ? [XJ + LAP, BIG, 0, BIG]
     : name == "c_rl" ? [-BIG, -XJ - LAP, -BIG, LAP] : name == "c_rr" ? [XJ + LAP, BIG, -BIG, 0]
     : name == "m_f" ? [-XJ - LAP, XJ + LAP, 0, BIG] : [-XJ - LAP, XJ + LAP, -BIG, 0];
  intersection() {
    ring_full();
    union() {
      intersection() { region(up[0], up[1], up[2], up[3]); translate([-BIG/2, -BIG/2, RT/2]) cube([BIG, BIG, 100]); }
      intersection() { region(lo[0], lo[1], lo[2], lo[3]); translate([-BIG/2, -BIG/2, -100]) cube([BIG, BIG, 100 + RT/2]); }
    }
  }
}

// VESA 100 riser: screen back -> internal plywood shelf.  Print base-down.
RS = 140; RB = 190; RH = -(TD[2] - FACE_Z) - SHELF_Z;   // height at the centre
module riser() {
  difference() {
    union() {
      translate([-RB/2, -RS/2, 0]) cube([RB, RS, 6]);
      hull() {
        translate([-RS/2, -RS/2, 0]) cube([RS, RS, 6]);
        translate([0, 0, RH]) rotate([TILT, 0, 0]) translate([-RS/2, -RS/2, -6]) cube([RS, RS, 6]);
      }
    }
    // hollow it (keep 6 mm walls) and open the sides for a screwdriver
    hull() {
      translate([-RS/2 + 6, -RS/2 + 6, 6]) cube([RS - 12, RS - 12, 1]);
      translate([0, 0, RH]) rotate([TILT, 0, 0]) translate([-RS/2 + 6, -RS/2 + 6, -12]) cube([RS - 12, RS - 12, 1]);
    }
    translate([-RS, -RS/2 + 20, 12]) cube([2 * RS, RS - 40, RH - 30]);
    translate([0, 0, RH]) rotate([TILT, 0, 0]) for (x = [-50, 50]) for (y = [-50, 50]) translate([x, y, -20]) {
      cylinder(d = 4.6, h = 40, $fn = 20);
    }
    translate([0, 0, RH]) rotate([TILT, 0, 0]) translate([0, 0, -20]) cylinder(d = 30, h = 40);
    for (x = [-1, 1]) for (y = [-45, 45]) translate([x * (RB/2 - 12), y, -1]) cylinder(d = 5, h = 20, $fn = 20);
  }
}

module td2220_standin() {
  translate([0, 0, FACE_Z]) {
    color("#141416") translate([-TD[0]/2, -TD[1]/2, -26]) cube([TD[0], TD[1], 26]);
    color("#0b1a3a") translate([-ACTIVE[0]/2, -ACTIVE[1]/2 + 6, -0.5]) cube([ACTIVE[0], ACTIVE[1], 0.6]);
    color("#1d1d20") hull() {
      translate([-TD[0]/2 + 30, -TD[1]/2 + 30, -27]) cube([TD[0] - 60, TD[1] - 60, 1]);
      translate([-140, -110, -TD[2]]) cube([280, 200, 1]);
    }
  }
}

module bezel_assembly() {
  color("#1E1F22") ring_full();
  td2220_standin();
  color("#555") translate([0, 0, SHELF_Z]) riser();
}

if (PART == "full") ring_full();
else if (PART == "riser") riser();
else if (PART == "preview") {
  bezel_assembly();
  for (p = ["c_fl", "c_fr", "c_rl", "c_rr", "m_f", "m_r"]) translate([0, 0, 120]) color(p == "m_f" || p == "m_r" ? "#3a3c42" : "#1E1F22") piece(p);
}
else {
  // print orientation: flat on its top face (the visible face is smooth on the bed)
  rotate([180, 0, 0]) translate([-(PART == "c_fl" || PART == "c_rl" ? -OUT[0]/2 + 100 : PART == "c_fr" || PART == "c_rr" ? OUT[0]/2 - 100 : 0),
                                  -(PART == "c_fl" || PART == "c_fr" || PART == "m_f" ? OUT[1]/4 : -OUT[1]/4), -RT]) piece(PART);
}
