shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

#include "res://shaders/noise.gdshaderinc"

uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform float time = 0.0;
uniform float cloud_rot = 0.0;
uniform float opacity = 1.0;

varying vec3 obj_dir;
varying vec3 world_n;

mat3 rot_y(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }

void vertex() {
	obj_dir = normalize(VERTEX);
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 d = normalize(obj_dir);
	vec3 q = rot_y(cloud_rot) * d;
	float c = fbm(q * 4.0 + vec3(0.0, time * 0.002, 0.0), 7);
	float bands = 0.5 + 0.5 * sin(q.y * 9.0 + fbm(q * 2.0, 3) * 4.0);
	float a = smoothstep(0.5, 0.75, c * (0.75 + 0.35 * bands));
	float detail = fbm(q * 40.0, 4);
	a *= 0.7 + 0.5 * detail;
	float ndl = dot(normalize(world_n), normalize(sun_dir));
	float lit = smoothstep(-0.1, 0.25, ndl);
	vec3 col = mix(vec3(0.02, 0.02, 0.03), vec3(1.0, 0.98, 0.95) * 2.2, lit);
	col = mix(col, vec3(1.0, 0.55, 0.3) * 1.5, exp(-pow(ndl / 0.08, 2.0)) * 0.5);
	ALBEDO = col * (0.85 + 0.3 * detail);
	ALPHA = clamp(a * opacity, 0.0, 0.95);
}
