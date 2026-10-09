shader_type spatial;
// Procedural Moon: maria, crater fields with rims and ray systems, lit manually.
render_mode unshaded, cull_back;

#include "res://shaders/noise.gdshaderinc"

uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform float detail = 1.0;

varying vec3 obj_dir;
varying vec3 world_n;

void vertex() {
	obj_dir = normalize(VERTEX);
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float craters(vec3 p, float scale) {
	vec2 c = cellular(p * scale);
	float r = 0.25 + 0.3 * c.y;
	float bowl = smoothstep(r, r * 0.6, c.x);
	float rim = exp(-pow((c.x - r) / (r * 0.18), 2.0));
	return rim * 0.6 - bowl * 0.5;
}

void fragment() {
	vec3 d = normalize(obj_dir);
	float maria = smoothstep(0.48, 0.58, fbm(d * 2.2 + 7.0, 6));
	vec3 base = mix(vec3(0.42, 0.41, 0.39), vec3(0.2, 0.2, 0.21), maria);
	float cr = craters(d, 9.0) + craters(d, 23.0) * 0.6 + craters(d, 61.0) * 0.4 * detail;
	base *= 0.85 + 0.25 * fbm(d * 80.0, 4);
	// crater shading: fake slope from the crater field gradient toward the sun
	vec3 L = normalize(sun_dir);
	float eps = 0.002;
	vec3 t = normalize(L - d * dot(L, d));
	float slope = (craters(normalize(d + t * eps), 9.0) - craters(d, 9.0)) / eps * 0.004;
	vec3 n = normalize(world_n);
	float ndl = max(dot(n, L), 0.0);
	float lit = ndl * (1.0 + clamp(slope * 2.0, -0.8, 0.8)) * (1.0 + cr * 0.4);
	ALBEDO = base * max(lit, 0.0) * 1.9;
}
