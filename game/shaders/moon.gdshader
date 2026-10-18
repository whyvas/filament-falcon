shader_type spatial;
// Procedural Moon: maria, crater fields with rims and ray systems, lit manually.
render_mode unshaded, cull_back;

#include "res://shaders/noise.gdshaderinc"

uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform float detail = 1.0;
// LRO: LROC colour + LOLA elevation (tools/fetch_assets.sh); procedural craters as fallback/detail
uniform bool use_tex = false;
uniform sampler2D color_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_tex : filter_linear_mipmap, repeat_enable;
uniform float height_scale = 0.012;   // LOLA range (~20 km) relative to the 200 km game Moon, exaggerated
uniform vec3 site_dir = vec3(1.0, 0.0, 0.0);   // lunar landing patch: no displacement there
vec2 moon_uv(vec3 d) {
	float lon = atan(d.x, -d.z);
	return vec2(lon / 6.2831853 + 0.5, 0.5 - asin(clamp(d.y, -1.0, 1.0)) / 3.1415927);
}

varying vec3 obj_dir;
varying vec3 world_n;

void vertex() {
	obj_dir = normalize(VERTEX);
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (use_tex) {   // displacement from LOLA (the sphere is dense enough at high quality)
		float h = textureLod(height_tex, moon_uv(obj_dir), 0.0).r;
		float keep = smoothstep(0.12, 0.3, acos(clamp(dot(obj_dir, normalize(site_dir)), -1.0, 1.0)));
		VERTEX += NORMAL * (h - 0.5) * height_scale * length(VERTEX) * keep - NORMAL * 0.004 * length(VERTEX) * keep;
	}
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
	if (use_tex) {
		vec2 uv = moon_uv(d);
		vec2 du = dFdx(uv); vec2 dv = dFdy(uv);
		du.x -= round(du.x); dv.x -= round(dv.x);
		base = textureGrad(color_tex, uv, du, dv).rgb * (0.9 + 0.2 * fbm(d * 80.0, 4) * detail);
		// normal from the LOLA height (central differences on the sphere)
		vec3 e1 = normalize(cross(d, vec3(0.0, 1.0, 0.0001)));
		vec3 e2 = cross(d, e1);
		float s = 0.0015;
		float h0 = textureLod(height_tex, moon_uv(d), 0.0).r;
		float hx = textureLod(height_tex, moon_uv(normalize(d + e1 * s)), 0.0).r;
		float hy = textureLod(height_tex, moon_uv(normalize(d + e2 * s)), 0.0).r;
		vec3 nobj = normalize(d - (e1 * (hx - h0) + e2 * (hy - h0)) * height_scale / s * 6.0);
		vec3 nw = normalize((MODEL_MATRIX * vec4(nobj, 0.0)).xyz);
		lit = max(dot(nw, L), 0.0) * (1.0 + cr * 0.15);
	}
	ALBEDO = base * max(lit, 0.0) * 1.9;
}
