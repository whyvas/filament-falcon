shader_type sky;
// Procedural star field + Milky Way band + sun disk. HDR values feed the glow/bloom.

#include "res://shaders/noise.gdshaderinc"

uniform float star_intensity = 1.0;
uniform float milky_intensity = 1.0;
uniform vec3 galaxy_normal = vec3(0.28, 0.86, 0.42);
uniform vec3 galaxy_core = vec3(-0.55, 0.12, 0.83);
uniform float sun_disk_scale = 1.0;

// Star colour from a rough temperature (2800 K red dwarf .. 30000 K blue giant).
vec3 star_tint(float t) {
	vec3 red = vec3(1.0, 0.62, 0.38);
	vec3 sun = vec3(1.0, 0.93, 0.84);
	vec3 blue = vec3(0.68, 0.78, 1.0);
	return t < 0.6 ? mix(red, sun, t / 0.6) : mix(sun, blue, (t - 0.6) / 0.4);
}

// One star per (randomly rotated) grid cell: each layer gets its own rotation, so the cubic
// lattice never lines up between layers and no tiling or axis rows show. Magnitudes follow a
// steep power law (many faint, very few bright), like a real catalogue.
vec3 star_layer(vec3 d, mat3 rot, float scale, float density, float size, float seed) {
	vec3 p = rot * d * scale;
	vec3 cell = floor(p);
	vec3 h = hash33(cell + seed);
	float present = step(1.0 - density, hash13(cell + 3.7 + seed));
	vec3 dir_s = normalize(cell + 0.15 + h * 0.7);
	float ang = acos(clamp(dot(normalize(p), dir_s), -1.0, 1.0)) * scale;
	float m = hash13(cell + 9.1 + seed);
	float bright = pow(m, 14.0) * 40.0 + pow(m, 4.0) * 0.6 + 0.05;
	float tempv = pow(hash13(cell + 1.3 + seed), 0.7);
	float sz = size * (0.8 + 0.6 * pow(m, 8.0));
	float core = exp(-ang * ang / (sz * sz));
	float twinkle = 1.0;  // no twinkle in vacuum
	return star_tint(tempv) * core * bright * present * twinkle;
}

mat3 rot_of(vec3 axis, float a) {
	axis = normalize(axis);
	float s = sin(a), c = cos(a), oc = 1.0 - c;
	return mat3(vec3(oc * axis.x * axis.x + c, oc * axis.x * axis.y + axis.z * s, oc * axis.z * axis.x - axis.y * s),
		vec3(oc * axis.x * axis.y - axis.z * s, oc * axis.y * axis.y + c, oc * axis.y * axis.z + axis.x * s),
		vec3(oc * axis.z * axis.x + axis.y * s, oc * axis.y * axis.z - axis.x * s, oc * axis.z * axis.z + c));
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
		float mwb = 0.5 + band * 2.0;   // more faint stars along the Milky Way
		vec3 stars = star_layer(d, rot_of(vec3(0.3, 1.0, 0.2), 0.7), 70.0, 0.12, 0.08, 0.0)
			+ star_layer(d, rot_of(vec3(1.0, 0.1, 0.6), 1.9), 170.0, 0.25, 0.10, 17.0) * 0.6
			+ star_layer(d, rot_of(vec3(0.2, 0.5, 1.0), 2.6), 380.0, 0.35, 0.13, 41.0) * 0.35 * mwb
			+ star_layer(d, rot_of(vec3(0.8, 0.9, 0.1), 4.1), 800.0, 0.45, 0.16, 73.0) * 0.2 * mwb;
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
