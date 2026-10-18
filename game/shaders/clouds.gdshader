shader_type spatial;
// Cloud deck on a sphere 4.5 km up. Seen from space: bright sunlit tops with soft edges and
// a warm terminator. Seen from below: grey flat bases, broken cumulus, and clear sky over
// the launch site and runway (so ascents and landings have a view).
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/geo_tex.gdshaderinc"
uniform bool use_tex = false;
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;

uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform float time = 0.0;
uniform float cloud_rot = 0.0;
uniform float opacity = 1.0;
uniform vec3 site_a = vec3(1.0, 0.0, 0.0);
uniform vec3 site_b = vec3(0.0, 0.0, 1.0);
uniform float clear_radius = 0.05;   // radians on the planet (~30 km at R = 600 km)

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
	float cov = c * (0.75 + 0.35 * bands);
	// small cumulus cells break up the big systems
	float cells = fbm(q * 55.0 + 7.0, 4);
	float a = smoothstep(0.65, 0.82, cov + (cells - 0.5) * 0.18);
	if (use_tex) {   // NASA cloud map, drifting with cloud_rot, broken up by the procedural cells
		a = smoothstep(0.12, 0.9, geo_sample(cloud_tex, geo_uv(q)).r + (cells - 0.5) * 0.12);
	}
	float detail = fbm(q * 160.0, 3);
	a *= 0.75 + 0.4 * detail;
	// clear weather over the launch site and the runway
	float clear_a = smoothstep(clear_radius, clear_radius * 2.2, acos(clamp(dot(d, normalize(site_a)), -1.0, 1.0)));
	float clear_b = smoothstep(clear_radius, clear_radius * 2.2, acos(clamp(dot(d, normalize(site_b)), -1.0, 1.0)));
	a *= clear_a * clear_b;
	float ndl = dot(normalize(world_n), normalize(sun_dir));
	float lit = smoothstep(-0.1, 0.25, ndl);
	vec3 top = vec3(1.0, 0.985, 0.96) * 1.35;          // sunlit tops (HDR ~1.35 before tonemap)
	vec3 base = vec3(0.55, 0.58, 0.64);                // shaded flat bases seen from below
	vec3 col = FRONT_FACING ? top : mix(base, top * 0.8, (1.0 - a) * 0.6);
	col *= mix(0.03, 1.0, lit);
	col = mix(col, vec3(1.0, 0.55, 0.3) * 1.2, exp(-pow(ndl / 0.08, 2.0)) * 0.45);
	ALBEDO = col * (0.88 + 0.24 * detail);
	ALPHA = clamp(a * opacity, 0.0, 0.97);
}
