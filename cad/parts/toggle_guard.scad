// Missile-switch guard for a 6 mm mini toggle.  Print 1 base + 1 lid per guard
// (lid in red!).  Hinge pin: 24 mm of 1.75 mm filament, ends melted, or a 2 mm steel pin.
// The base slips over the toggle bushing and is clamped by the toggle's front nut.
include <../lib/ff_lib.scad>
PART = "preview";   // base | lid | preview
if (PART == "base") ff_guard_base();
else if (PART == "lid") translate([0, 0, FFG_H]) rotate([180, 0, 0]) ff_guard_lid(0);
else { color("#444") ff_guard_base(); color("#c00") ff_guard_lid(55); }
