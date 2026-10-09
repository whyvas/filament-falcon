// The Filament Falcon - CONCEPT ONLY: rear-projection dome with HY300 projectors.
// See docs/mechanical/projector_dome_study.md (recommendation: do NOT build now).
// Dome is a spherical band centred on the pod pivot (= reclined head centre), so the
// pod (max radius ~712 mm) can never touch it.  Projectors sit OUTSIDE the dome
// (rear projection) one throw-distance away.
include <overview.scad>          // cockpit in FLIGHT pose (STATE = "flight")

DOME_R = 1200;          // mm from the pod pivot
DOME_T = 6;             // stretched rear-projection fabric / frosted PETG skin
AZ = 75;                // +- azimuth covered
EL0 = -5; EL1 = 45;     // elevation band
N_PROJ = 3;             // 3 x HY300 across, one row (see study: 2 rows needed for full height)
THROW = 0.8;            // HY300 throw ratio
SEG = 2 * AZ / N_PROJ + 10;            // deg per projector incl. ~10 deg blend overlap
IMG_W = 2 * PI * DOME_R * SEG / 360;   // arc width per projector
DIST = THROW * IMG_W;                  // projector lens to dome
echo(str("dome: per-projector image ", round(IMG_W), " mm wide, throw ", round(DIST), " mm"));

module dome_band() {
  translate(FF_PP) rotate([0, 0, 90 - AZ]) rotate_extrude(angle = 2 * AZ, $fn = 120)
    polygon(concat([for (e = [EL0:5:EL1]) [DOME_R * cos(e), DOME_R * sin(e)]],
                   [for (e = [EL1:-5:EL0]) [(DOME_R + DOME_T) * cos(e), (DOME_R + DOME_T) * sin(e)]]));
}
module rib(a) translate(FF_PP) rotate([0, 0, 90 + a]) for (e = [EL0:5:EL1 - 5])
  hull() for (k = [e, e + 5]) translate([(DOME_R + DOME_T + 20) * cos(k), 0, (DOME_R + DOME_T + 20) * sin(k)]) cube([38, 38, 38], center = true);

module hy300() {   // ~95 dia x 160 body, lens facing +x
  color("#e8e8e8") rotate([0, 90, 0]) cylinder(d = 100, h = 160, center = true, $fn = 40);
  color("#222") translate([80, 0, 25]) rotate([0, 90, 0]) cylinder(d = 40, h = 12, $fn = 30);
}
EL_C = (EL0 + EL1) / 2;
for (i = [0:N_PROJ - 1]) if (HIDE_SIDE == 0 || i == (N_PROJ - 1) / 2) {
  a = -AZ + (2 * AZ / N_PROJ) * (i + 0.5);
  translate(FF_PP) rotate([0, 0, 90 + a]) rotate([0, -EL_C, 0]) {
    translate([DOME_R + DOME_T + DIST, 0, 0]) rotate([0, 0, 180]) hy300();
    // light cone
    color("#9fd3ff", 0.12) hull() {
      translate([DOME_R + DOME_T + DIST - 80, 0, 0]) cube(4, center = true);
      translate([DOME_R + 10, 0, 0]) cube([2, IMG_W, IMG_W * 9 / 16], center = true);
    }
  }
}
module dome_cut() {   // side view: section the dome on the centre plane so its arc shows
  if (HIDE_SIDE == 1) difference() { children(); translate([0, -4000, -100]) cube([3000, 8000, 4000]); }
  else children();
}
dome_cut() color("#c9d6e3", 0.45) dome_band();
dome_cut() color("#b08850") for (a = [-AZ:AZ / 3:AZ]) rib(a);
// required room footprint (grey floor)
color("#3a3d44") translate([-2500, -2600, -12]) cube([5000, 2600 + DOME_R + DIST + 400 - FF_PP[1] * 0 - 1375 + 200, 10]);
