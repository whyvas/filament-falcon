// =====================================================================
//  The Filament Falcon - shared OpenSCAD library
//  Units: mm.  Works in OpenSCAD 2021.01+ (faster with a 2024+ build and
//  the Manifold backend: --backend=Manifold).
//
//  Panel coordinate convention (all panel modules):
//    x = right, y = up, as seen from the FRONT of the panel.
//    Front face at z = 0, panel body occupies z = -FF_T .. 0,
//    back-side features (light boxes, ribs, bosses) grow toward -z.
//    Export rotates 180 deg about X so the front face prints on the bed.
// =====================================================================

// ---------- global parameters (override with -D or before include) ----
FF_T          = 3.0;    // panel thickness (letters go all the way through)
FF_GRID       = 40;     // mounting grid pitch
FF_GAP        = 0.5;    // panels are (nominal - FF_GAP) so neighbours never bind
FF_BAND       = 20;     // top/bottom band that sits on the plywood rail (flat back)
FF_HOLE_EDGE  = 10;     // M5 hole centre distance from top/bottom nominal edge
FF_M5_D       = 5.5;    // M5 clearance hole
FF_HOLE_COMP  = 0.2;    // added to every switch hole: printed holes come out small
FF_STRIP_W    = 12;     // WS2812B strip width (set 10 for 10 mm strips)
FF_STRIP_SLOT = FF_STRIP_W + 0.6;
FF_STANDOFF   = 9;      // LED face to panel back = diffusion distance
FF_LED_H      = 1.6;    // 5050 LED height above strip PCB
FF_PCB_T      = 0.6;    // strip PCB + tolerance
FF_WALL       = 1.6;    // light box wall
FF_LEDGE      = 1.2;    // strip-stop ledge width (PCB margin beside the LED)
FF_NUB        = 0.6;    // snap nub that retains the strip
FF_BOX_DEPTH  = FF_STANDOFF + FF_LED_H + FF_PCB_T + 1.6;   // wall height behind panel
FF_RIB_W      = 2.0;
FF_RIB_H      = 6.0;
FF_PIN_D      = 3.0;    // seam alignment pin (3 mm dowel / printed pin)
FF_BRIDGE     = 1.2;    // stencil bridge width (single-material version)
FF_INSERT_CLR = 0.12;   // insert letters are offset inward by this
FF_PLAQUE_T   = 0.8;    // white backing box behind each label (part of the letter object)

$fn = 48;

// ---------- standard holes -------------------------------------------
// [type, nominal hole dia, back keep-out radius, front keep-out radius]
FF_CUTS = [
  ["tog6",    6.2,  8,  6],   // mini toggle, 6 mm (1/4") bushing
  ["tog6g",   6.2,  8,  6],   // mini toggle with printed missile guard
  ["tog12",  12.0, 13,  9],   // heavy-duty toggle, 12 mm bushing (seat lift)
  ["btn12",  12.0,  9,  8],   // 12 mm momentary
  ["btn16",  16.0, 11, 10],   // 16 mm momentary
  ["arc19",  19.0, 13, 12],   // 19 mm metal/arcade button
  ["arc22",  22.0, 15, 14],   // 22 mm button
  ["estop22",22.0, 15, 21],   // 22 mm emergency stop (40 mm mushroom)
  ["led5",    5.0,  4.5, 4],  // 5 mm LED (push fit) - use 8 mm for chrome bezels
  ["ec11",    7.0,  9, 12],   // EC11 rotary encoder, 7 mm bushing, 24 mm knob
  ["key19",  19.0, 14, 13],   // 19 mm key switch
  ["pot7",    7.0, 10, 12],   // 16 mm pot, M7 bushing
  ["m3cs",    3.2,  4,  3.5], // M3 countersunk screw (holds lever boxes under a panel)
];
function ff_cut(t) = FF_CUTS[search([t], FF_CUTS)[0]];
function ff_hole_d(t) = ff_cut(t)[1] + FF_HOLE_COMP;

module ff_hole2d(t) {
  circle(d = ff_hole_d(t), $fn = 64);
}
// countersinks are cut separately (3D) by the panel builder
module ff_hole_extra(t) {
  if (t == "m3cs") translate([0, 0, -1.8]) cylinder(d1 = 3.4, d2 = 6.6, h = 1.81, $fn = 32);
}

// ---------- mounting grid --------------------------------------------
// M5 clearance holes on the 40 mm grid along the top and bottom bands.
function ff_mount_points(W, H) =
  [ for (x = [FF_GRID/2 : FF_GRID : W - 1]) for (y = [FF_HOLE_EDGE, H - FF_HOLE_EDGE]) [x, y] ];

module ff_outline2d(W, H, r = 1.5) {
  g = FF_GAP / 2;
  translate([g + r, g + r]) offset(r = r) square([W - 2*g - 2*r, H - 2*g - 2*r]);
}

// ---------- light box (one per backlit label) -------------------------
// Sits on the panel back, centred on the label.  Inner height along y is
// at least the strip slot.  The strip is pushed in LEDs-first until its
// PCB edges hit the two ledges; the snap nubs hold it there.  End walls
// are notched so the strip (or a 3-wire jumper) passes on to the next box.
module ff_lightbox(cx, cy, iw, ih) {
  ow = iw + 2*FF_WALL; oh = ih + 2*FF_WALL;
  zb = -FF_T;                                   // panel back
  zl = zb - (FF_STANDOFF + FF_LED_H);           // ledge face (PCB rests here)
  translate([cx, cy, 0]) {
    difference() {
      translate([-ow/2, -oh/2, zb - FF_BOX_DEPTH]) cube([ow, oh, FF_BOX_DEPTH + 0.01]);
      translate([-iw/2, -ih/2, zb - FF_BOX_DEPTH - 1]) cube([iw, ih, FF_BOX_DEPTH + 2]);
      // pass-through notches in both end walls, at strip level
      for (sx = [-1, 1])
        translate([sx*(iw/2 + FF_WALL/2) - FF_WALL, -FF_STRIP_SLOT/2, zb - FF_BOX_DEPTH - 1])
          cube([2*FF_WALL, FF_STRIP_SLOT, (zl + 2) - (zb - FF_BOX_DEPTH - 1)]);
    }
    // strip-stop ledges along the long walls, chamfered toward the panel
    // (printable: the panel prints face-down so these are 45 deg overhangs)
    sw = ih;   // inner y size
    for (s = [-1, 1]) {
      hull() {
        translate([-iw/2, s*(sw/2) - (s > 0 ? FF_LEDGE : 0), zl - 0.01]) cube([iw, FF_LEDGE, 0.01]);
        translate([-iw/2, s*(sw/2) - (s > 0 ? 0.01 : -0.0), zl + FF_LEDGE + 0.4]) cube([iw, 0.01, 0.01]);
      }
    }
    // snap nubs above the strip (every ~25 mm, at least one per wall)
    n = max(1, floor(iw / 25));
    for (i = [0 : n - 1]) for (s = [-1, 1]) {
      x = -iw/2 + (i + 0.5) * iw / n;
      zn = zl - FF_PCB_T;
      translate([x, s*(ih/2), 0])
        hull() {
          translate([-3, s > 0 ? -0.01 : 0, zn - 0.01]) cube([6, 0.01, 0.01]);
          translate([-3, s > 0 ? -FF_NUB : 0, zn - 0.6]) cube([6, FF_NUB, 0.01]);
          translate([-3, s > 0 ? -0.01 : 0, zn - 1.4]) cube([6, 0.01, 0.01]);
        }
    }
  }
}

// ---------- seam alignment boss with pin hole --------------------------
// side = -1 (boss on left edge) or +1 (right edge).  Hole runs along x.
module ff_seam_boss(W, y, side) {
  x0 = side < 0 ? FF_GAP/2 : W - FF_GAP/2 - 10;
  translate([x0, y - 6, -FF_T - 9]) cube([10, 12, 9.01]);
}
module ff_seam_hole(W, y, side) {
  x0 = side < 0 ? FF_GAP/2 - 1 : W - FF_GAP/2 - 9;
  translate([x0, y, -FF_T - 4.5]) rotate([0, 90, 0]) cylinder(d = FF_PIN_D + 0.3, h = 10, $fn = 24);
}

// ---------- printed toggle guard (missile-switch cover) -----------------
// Two parts + a 1.75 mm filament (or 2 mm steel) hinge pin.
// The base clamps under the toggle's front nut; the lid flips up.
FFG_W = 22; FFG_FRONT = 19; FFG_BACK = 20; FFG_H = 20; FFG_AX_Y = 16.5; FFG_AX_Z = 9;
FFG_PIN = 1.95;
module ff_guard_base() {
  difference() {
    union() {
      translate([-FFG_W/2, -9, 0]) cube([FFG_W, 9 + FFG_BACK, 2]);
      for (s = [-1, 1]) hull() {
        translate([s > 0 ? 6 : -FFG_W/2, FFG_AX_Y - 3.5, 0]) cube([FFG_W/2 - 6, 7, 2]);
        translate([s > 0 ? 6 : -FFG_W/2, FFG_AX_Y, FFG_AX_Z]) rotate([0, 90, 0]) cylinder(r = 3.5, h = FFG_W/2 - 6);
      }
    }
    cylinder(d = 6.2 + FF_HOLE_COMP + 0.2, h = 10, center = true);
    translate([-20, FFG_AX_Y, FFG_AX_Z]) rotate([0, 90, 0]) cylinder(d = FFG_PIN, h = 40, $fn = 20);
  }
}
module ff_guard_lid(angle = 0) {
  translate([0, FFG_AX_Y, FFG_AX_Z]) rotate([-angle, 0, 0]) translate([0, -FFG_AX_Y, -FFG_AX_Z])
  difference() {
    union() {
      // cover shell
      difference() {
        translate([-FFG_W/2, -FFG_FRONT, 2]) cube([FFG_W, FFG_FRONT + FFG_AX_Y - 4, FFG_H - 2]);
        translate([-FFG_W/2 + 1.6, -FFG_FRONT + 1.6, 1]) cube([FFG_W - 3.2, FFG_FRONT + FFG_AX_Y - 4 - 3.2, FFG_H - 2 - 0.6]);
      }
      // hinge arm + knuckle
      hull() {
        translate([-5.6, FFG_AX_Y - 6, FFG_H - 2]) cube([11.2, 2, 2]);
        translate([-5.6, FFG_AX_Y, FFG_AX_Z]) rotate([0, 90, 0]) cylinder(r = 3.4, h = 11.2);
      }
      // finger tab
      translate([-6, -FFG_FRONT - 5, FFG_H - 2]) cube([12, 6, 2]);
    }
    translate([-20, FFG_AX_Y, FFG_AX_Z]) rotate([0, 90, 0]) cylinder(d = FFG_PIN + 0.25, h = 40, $fn = 20);
  }
}

// ---------- misc helpers ----------------------------------------------
module ff_rounded_box(size, r = 3) {
  hull() for (x = [r, size[0] - r]) for (y = [r, size[1] - r])
    translate([x, y, 0]) cylinder(r = r, h = size[2]);
}
module ff_countersink_m5(h = 20) {   // from z = 0 downward
  translate([0, 0, -h]) cylinder(d = FF_M5_D, h = h + 0.1);
  translate([0, 0, -2.75]) cylinder(d1 = FF_M5_D, d2 = 10.5, h = 2.76);
}
