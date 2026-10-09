// =====================================================================
//  Generic backlit panel builder.  A panel file sets these globals and
//  then includes this file:
//    PANEL_ID, W, H                nominal size (multiples of 40 mm)
//    SEAM_L, SEAM_R                true if this edge joins a neighbour piece
//    CUTS    = [[type, x, y], ...] standard holes (see FF_CUTS)
//    SLOTS   = [[x, y, w, l], ...] rounded slots (lever travel), l along y
//    GROOVES = [[x0, y0, x1, y1], ...] engraved outline on the front
//    LABELS  = [[id, cx, cy, iw, ih, full_poly, stencil_poly], ...]
//              poly = [points, paths]  (letters already in panel coords)
//    PART    = "mm_body" | "mm_letters" | "sm_body" | "sm_inserts" |
//              "preview" | "assembly"
//    EXPORT  = true -> rotate into print orientation
// =====================================================================
include <ff_lib.scad>

function ff_seam_ys() = [30, H - 30];

module ff_letters2d(which) {        // which: 5 = full, 6 = stencil
  for (L = LABELS) polygon(points = L[which][0], paths = L[which][1]);
}

module ff_panel_body(which) {
  difference() {
    union() {
      translate([0, 0, -FF_T]) linear_extrude(FF_T) ff_outline2d(W, H);
      // perimeter stiffening rib (stays inside the rail bands' flat zone)
      translate([0, 0, -FF_T - FF_RIB_H]) linear_extrude(FF_RIB_H + 0.01)
        difference() {
          translate([FF_GAP/2, FF_BAND]) square([W - FF_GAP, H - 2*FF_BAND]);
          translate([FF_GAP/2 + FF_RIB_W, FF_BAND + FF_RIB_W]) square([W - FF_GAP - 2*FF_RIB_W, H - 2*FF_BAND - 2*FF_RIB_W]);
        }
      for (L = LABELS) ff_lightbox(L[1], L[2], L[3], L[4]);
      if (SEAM_L) for (y = ff_seam_ys()) ff_seam_boss(W, y, -1);
      if (SEAM_R) for (y = ff_seam_ys()) ff_seam_boss(W, y, 1);
    }
    // M5 mounting holes
    for (p = ff_mount_points(W, H)) translate([p[0], p[1], -50]) cylinder(d = FF_M5_D, h = 100, $fn = 32);
    // switch holes
    for (c = CUTS) translate([c[1], c[2], -50]) linear_extrude(100) ff_hole2d(c[0]);
    for (c = CUTS) translate([c[1], c[2], 0]) ff_hole_extra(c[0]);
    for (s = SLOTS) translate([s[0], s[1], -50]) linear_extrude(100)
      hull() for (d = [-1, 1]) translate([0, d*(s[3] - s[2])/2]) circle(d = s[2], $fn = 48);
    // engraved front outlines
    for (g = GROOVES) translate([0, 0, -0.8]) linear_extrude(1)
      difference() {
        translate([g[0], g[1]]) square([g[2] - g[0], g[3] - g[1]]);
        translate([g[0] + 1.2, g[1] + 1.2]) square([g[2] - g[0] - 2.4, g[3] - g[1] - 2.4]);
      }
    // wire pass-through notches in the side ribs, mid height
    for (x = [FF_GAP/2 - 1, W - FF_GAP/2 - FF_RIB_W - 1])
      translate([x, H/2 - 7, -FF_T - FF_RIB_H - 1]) cube([FF_RIB_W + 2, 14, FF_RIB_H + 0.5]);
    // through-letters
    translate([0, 0, -FF_T - 0.01]) linear_extrude(FF_T + 0.02) ff_letters2d(which);
    if (SEAM_L) for (y = ff_seam_ys()) ff_seam_hole(W, y, -1);
    if (SEAM_R) for (y = ff_seam_ys()) ff_seam_hole(W, y, 1);
  }
}

module ff_panel_letters() {
  translate([0, 0, -FF_T]) linear_extrude(FF_T) ff_letters2d(5);
}

// single-material fallback: white plaque + stencil letters, pressed in from the back
module ff_panel_inserts() {
  for (L = LABELS) {
    translate([L[1], L[2], -FF_T - FF_PLAQUE_T])
      linear_extrude(FF_PLAQUE_T) offset(r = 0.6) offset(delta = -0.6 - 0.3)
        square([L[3], L[4]], center = true);
    translate([0, 0, -FF_T - 0.01]) linear_extrude(FF_T + 0.01)
      offset(delta = -FF_INSERT_CLR) polygon(points = L[6][0], paths = L[6][1]);
  }
}

// rough stand-ins for switches, for renders only
module ff_dummy(c) {
  t = c[0];
  translate([c[1], c[2], 0]) {
    if (t == "tog6" || t == "tog6g" || t == "tog12") {
      color("silver") { cylinder(d = t == "tog12" ? 16 : 9.5, h = 2.5, $fn = 6); cylinder(d = t == "tog12" ? 12 : 6, h = 6);
        translate([0, 0, 6]) rotate([-15, 0, 0]) cylinder(d1 = 3, d2 = 2.2, h = 10); }
      color("#333") translate([-6.5, -4, -FF_T - 13]) cube([13, 8, 13]);
    } else if (t == "m3cs") {
      color("silver") translate([0, 0, -0.5]) cylinder(d = 6, h = 0.6);
    } else if (t == "led5") {
      color("#2f2") translate([0, 0, -2]) { cylinder(d = 5, h = 2.5); translate([0, 0, 2.5]) sphere(d = 5); }
    } else if (t == "ec11" || t == "pot7") {
      color("#222") cylinder(d = 22, h = 14); color("silver") translate([0, 0, 14]) cylinder(d = 23, h = 1);
      color("white") translate([-0.8, 4, 14.5]) cube([1.6, 7, 1]);
    } else if (t == "key19") {
      color("silver") { cylinder(d = 22, h = 3); translate([0, 0, 3]) cylinder(d = 18, h = 2); }
      color("#444") translate([-1, -4, 5]) cube([2, 8, 1]);
    } else if (t == "estop22") {
      color("yellow") cylinder(d = 30, h = 3); color("red") translate([0, 0, 3]) { cylinder(d = 24, h = 8); translate([0, 0, 8]) cylinder(d = 40, h = 8); }
    } else {
      d = ff_cut(t)[1];
      col = t == "arc22" ? "red" : t == "arc19" ? "orange" : "#ddd";
      color("silver") cylinder(d = d + 3, h = 2);
      color(col) cylinder(d = d - 2, h = t == "btn12" || t == "btn16" ? 4 : 6);
    }
  }
}

module ff_panel_preview(dummies = true) {
  color(dummies ? "#202226" : "#4a4e57") ff_panel_body(5);
  color("white") ff_panel_letters();
  if (dummies) for (c = CUTS) {
    ff_dummy(c);
    if (c[0] == "tog6g") translate([c[1], c[2], 0]) { color("#c00") ff_guard_lid(0); color("#444") ff_guard_base(); }
  }
}

module ff_export_orient() { rotate([180, 0, 0]) children(); }

module ff_panel_part(part) {
  if (part == "mm_body")         ff_export_orient() ff_panel_body(5);
  else if (part == "mm_letters") ff_export_orient() ff_panel_letters();
  else if (part == "sm_body")    ff_export_orient() ff_panel_body(6);
  else if (part == "sm_inserts") translate([0, 0, FF_T + FF_PLAQUE_T]) ff_panel_inserts();
  else if (part == "preview")    ff_panel_preview(true);
  else if (part == "bare")       ff_panel_preview(false);
  else if (part == "asm_body")   ff_panel_body(5);
  else if (part == "asm_letters") ff_panel_letters();
}
