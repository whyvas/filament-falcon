shader_type sky;
// Procedural star field + Milky Way band + sun disk. HDR values feed the glow/bloom.

#include "res://shaders/noise.gdshaderinc"

uniform float star_intensity = 1.0;
uniform float milky_intensity = 1.0;
uniform vec3 galaxy_normal = vec3(0.28, 0.86, 0.42);
uniform vec3 galaxy_core = vec3(-0.55, 0.12, 0.83);
uniform float sun_disk_scale = 1.0;

vec3 star_layer(vec3 d, float scale, float density, float size) {
	vec3 p = d * scale;
	vec3 cell = floor(p);
	vec3 col = vec3(0.0);
	for (int i = 0; i < 1; i++) {
		vec3 h = hash33(cell);
		float present = step(1.0 - density, hash13(cell + 3.7));
		vec3 sp = cell + h;
		vec3 dir_s = normalize(sp);
		float ang = acos(clamp(dot(d, dir_s), -1.0, 1.0)) * scale;
		float mag = pow(hash13(cell + 9.1), 6.0);
		float tempv = hash13(cell + 1.3);
		vec3 tint = mix(vec3(1.0, 0.75, 0.55), vec3(0.65, 0.8, 1.0), tempv);
		float core = exp(-ang * ang / (size * size));
		col += tint * core * (0.25 + 6.0 * mag) * present;
	}
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = vec3(0.0);
	// Milky Way band
	float lat = dot(d, normalize(galaxy_normal));
	float band = exp(-lat * lat / 0.018);
	float wide = exp(-lat * lat / 0.09);
	float core = pow(max(dot(d, normalize(galaxy_core)), 0.0), 6.0);
	float n = fbm(d * 7.0, 6);
	float dust = smoothstep(0.42, 0.62, fbm(d * 13.0 + 4.0, 5));
	float lane = 1.0 - 0.75 * dust * exp(-lat * lat / 0.004);
	vec3 mw = vec3(0.55, 0.6, 0.85) * band * (0.35 + n) + vec3(1.0, 0.8, 0.55) * core * band * 1.6 + vec3(0.25, 0.3, 0.5) * wide * 0.15;
	col += mw * lane * 0.22 * milky_intensity;
	// faint nebula tint
	float neb = smoothstep(0.55, 0.85, fbm(d * 3.0 + 11.0, 5));
	col += vec3(0.5, 0.15, 0.35) * neb * 0.03 * milky_intensity;
	if (!AT_CUBEMAP_PASS) {
		vec3 stars = star_layer(d, 90.0, 0.10, 0.07) + star_layer(d, 220.0, 0.22, 0.09) * 0.6 + star_layer(d, 480.0, 0.4, 0.12) * 0.35 * (0.6 + band * 1.5);
		col += stars * star_intensity;
	}
	// Sun disk + corona
	if (LIGHT0_ENABLED) {
		float c = dot(d, LIGHT0_DIRECTION);
		float disk = smoothstep(0.99996 - 0.00002 * sun_disk_scale, 0.99999, c);
		float corona = pow(max(c, 0.0), 900.0) * 4.0 + pow(max(c, 0.0), 80.0) * 0.25;
		col += LIGHT0_COLOR * (disk * 60.0 + corona) * (AT_CUBEMAP_PASS ? 0.05 : 1.0);
	}
	COLOR = col;
}
