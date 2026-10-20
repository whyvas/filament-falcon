shader_type spatial;
// Single-scattering (Rayleigh + Mie + ozone absorption) atmosphere, ray-marched inside a shell around the
// planet. Works from orbit (blue limb, sunsets on the terminator) and from the ground
// (blue sky, red sunrise), and uses the depth buffer for aerial perspective on terrain.
render_mode unshaded, blend_add, cull_front, depth_draw_never, depth_test_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform vec3 planet_center = vec3(0.0);   // world metres (real scale)
uniform float space_scale = 1.0;          // scale applied to the planet mesh (scaled space)
#include "res://shaders/atmo_common.gdshaderinc"
uniform float g_mie = 0.76;
uniform float intensity = 22.0;
uniform int steps = 16;
uniform int light_steps = 6;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 ray_sphere(vec3 ro, vec3 rd, float r) { return ray_sph(ro, rd, r); }

void fragment() {
	vec3 center = planet_center;
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 ro = (cam - center) * 0.001;
	vec3 rd = normalize(world_pos - cam);
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV * 2.0 - 1.0, depth), 1.0);
	vp.xyz /= vp.w;
	float scene_km = length(vp.xyz) * 0.001;
	if (depth <= 0.0000001) scene_km = 1e9;
	vec2 at = ray_sphere(ro, rd, atmo_r_km);
	if (at.x > at.y) discard;
	// Opaque pixels far beyond half the scaled distance to the air belong to the scaled planet.
	if (space_scale < 0.999 && scene_km > 0.5 * max(at.x, 0.0) * space_scale) scene_km /= space_scale;
	float t0 = max(at.x, 0.0);
	float t1 = at.y;
	vec2 pl = ray_sphere(ro, rd, planet_r_km);
	if (pl.x > 0.0 && pl.x < t1) t1 = pl.x;
	t1 = min(t1, scene_km);
	if (t1 <= t0) discard;
	vec3 L = normalize(sun_dir);
	float mu = dot(rd, L);
	float pr = 3.0 / (16.0 * PI) * (1.0 + mu * mu);
	float g2 = g_mie * g_mie;
	float pm = 3.0 / (8.0 * PI) * ((1.0 - g2) * (1.0 + mu * mu)) / ((2.0 + g2) * pow(1.0 + g2 - 2.0 * g_mie * mu, 1.5));
	float seg = (t1 - t0) / float(steps);
	vec3 sum_r = vec3(0.0);
	vec3 sum_m = vec3(0.0);
	float od_r = 0.0;
	float od_m = 0.0;
	for (int i = 0; i < 32; i++) {
		if (i >= steps) break;
		vec3 p = ro + rd * (t0 + seg * (float(i) + 0.5));
		float h = length(p) - planet_r_km;
		float dr = exp(-h / h_r) * seg;
		float dm = exp(-h / h_m) * seg;
		od_r += dr;
		od_m += dm;
		vec2 ls = ray_sphere(p, L, atmo_r_km);
		vec2 lp = ray_sphere(p, L, planet_r_km);
		if (lp.x > 0.0) continue; // in planet shadow
		float lseg = ls.y / float(light_steps);
		float lr = 0.0;
		float lm = 0.0;
		for (int j = 0; j < 12; j++) {
			if (j >= light_steps) break;
			vec3 q = p + L * (lseg * (float(j) + 0.5));
			float hq = max(length(q) - planet_r_km, 0.0);
			lr += exp(-hq / h_r) * lseg;
			lm += exp(-hq / h_m) * lseg;
		}
		vec3 tau = (beta_r + beta_o) * (od_r + lr) + beta_m * 1.1 * (od_m + lm);
		vec3 att = exp(-tau);
		sum_r += dr * att;
		sum_m += dm * att;
	}
	vec3 col = intensity * (sum_r * beta_r * pr + sum_m * beta_m * pm);
	ALBEDO = col;
}
