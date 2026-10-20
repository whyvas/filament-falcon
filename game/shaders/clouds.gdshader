shader_type spatial;
// Cloud deck on its own transparent sphere 4.5 km up (real parallax over the ground; the ground
// gets soft shadows from the same map, see planet.gdshader). Lit by sunlight that has crossed
// the air (orange at the terminator), thick cores are darker than the thin edges, forward
// scattering gives a silver lining toward the sun, and the air between you and the clouds
// dims them like the ground. From below: grey flat bases, clear sky over the launch site
// and the runway (so ascents and landings have a view).
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/geo_tex.gdshaderinc"
#include "res://shaders/atmo_common.gdshaderinc"
uniform bool use_tex = false;
uniform sampler2D cloud_tex : filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform float time = 0.0;
uniform float cloud_rot = 0.0;
uniform float opacity = 1.0;
uniform vec3 site_a = vec3(1.0, 0.0, 0.0);
uniform vec3 site_b = vec3(0.0, 0.0, 1.0);
uniform float clear_radius = 0.05;   // radians on the planet (~30 km at R = 600 km)
uniform float cloud_h_km = 4.5;

varying vec3 obj_dir;
varying vec3 cam_obj_km;
varying vec3 sun_obj;

mat3 rot_y(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }

void vertex() {
	obj_dir = normalize(VERTEX);
	mat4 inv = inverse(MODEL_MATRIX);
	cam_obj_km = (inv * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz * 0.001;
	sun_obj = normalize((inv * vec4(sun_dir, 0.0)).xyz);
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
	float raw = cov;
	if (use_tex) {   // NASA cloud map, drifting with cloud_rot, broken up by the procedural cells
		raw = geo_sample(cloud_tex, geo_uv(q)).r;
		a = smoothstep(0.12, 0.9, raw + (cells - 0.5) * 0.12);
	}
	float detail = fbm(q * 160.0, 3);
	a *= 0.75 + 0.4 * detail;
	float clear_a = smoothstep(clear_radius, clear_radius * 2.2, acos(clamp(dot(d, normalize(site_a)), -1.0, 1.0)));
	float clear_b = smoothstep(clear_radius, clear_radius * 2.2, acos(clamp(dot(d, normalize(site_b)), -1.0, 1.0)));
	a *= clear_a * clear_b;
	vec3 L = normalize(sun_obj);
	float mu_s = dot(d, L);
	vec3 p_km = d * (planet_r_km + cloud_h_km);
	vec3 V = normalize(cam_obj_km - p_km);
	vec3 sunlight = sun_intensity * trans_to_space(p_km, L) * smoothstep(-0.06, 0.02, mu_s);
	// thickness: dense cores self-shadow, thin edges glow; Henyey-Greenstein forward lobe
	float thick = smoothstep(0.3, 1.0, raw);
	float g = 0.6;
	float cosv = dot(-V, L);
	float hg = (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * cosv, 1.5) * 0.08;
	vec3 top = sunlight * (0.72 * (1.0 - 0.35 * thick) + hg * (1.0 - a) * 2.0);
	vec3 sky = vec3(0.35, 0.5, 0.9) * 0.12 * sun_intensity * smoothstep(-0.1, 0.25, mu_s);
	vec3 base = sunlight * 0.22 * (1.0 - 0.5 * thick) + sky;   // shaded flat bases seen from below
	vec3 col = (FRONT_FACING ? top : mix(base, top * 0.6, (1.0 - a) * 0.6)) + sky * 0.5;
	col *= 0.88 + 0.24 * detail;
	col *= trans_between(cam_obj_km, p_km);
	ALBEDO = col;
	ALPHA = clamp(a * opacity, 0.0, 0.97);
}
