shader_type spatial;
// Runway surface: asphalt, centreline dashes, threshold piano keys, touchdown zone bars.
render_mode cull_back;

#include "res://shaders/noise.gdshaderinc"

uniform float length_m = 3600.0;
uniform float width_m = 60.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float x = lp.x;            // along runway, -L/2..L/2
	float z = lp.z;            // across, -W/2..W/2
	float hl = length_m * 0.5;
	vec3 col = vec3(0.09, 0.09, 0.1) * (0.8 + 0.3 * fbm(lp * 0.3, 4));
	float paint = 0.0;
	// centreline dashes
	paint += step(abs(z), 0.45) * step(fract(x / 60.0), 0.5) * step(abs(x), hl - 120.0);
	// edge lines
	paint += step(abs(abs(z) - width_m * 0.5 + 1.5), 0.5);
	// threshold piano keys at both ends
	float tk = step(hl - 60.0, abs(x)) * step(abs(x), hl - 15.0) * step(abs(z), width_m * 0.5 - 4.0) * step(0.5, fract(z / 3.6));
	paint += tk;
	// touchdown zone bars
	float tdz = step(hl - 450.0, abs(x)) * step(abs(x), hl - 300.0) * step(abs(abs(z) - 10.0), 3.0) * step(0.5, fract(x / 75.0));
	paint += tdz;
	col = mix(col, vec3(0.9), clamp(paint, 0.0, 1.0) * 0.9);
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
