shader_type spatial;
// Procedural Earth-like planet surface: continents, biomes, polar ice, ocean glint,
// cloud shadows, terminator glow and night-side city lights. Unshaded: lighting is
// computed here so the 600 km sphere looks right at any distance.
render_mode unshaded, cull_back;

#include "res://shaders/noise.gdshaderinc"

uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform float time = 0.0;
uniform vec3 site_a = vec3(1.0, 0.0, 0.0);
uniform vec3 site_b = vec3(0.0, 0.0, 1.0);
uniform float cloud_rot = 0.0;
uniform float detail = 1.0;

varying vec3 obj_dir;
varying vec3 world_n;
varying vec3 world_p;

mat3 rot_y(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }

float land_mask(vec3 d) {
	float c = fbm(d * 1.8 + vec3(2.0, 0.0, 5.0), 7);
	c += 0.12 * fbm(d * 9.0, 4) * detail;
	float m = c;
	m = max(m, 0.62 - 3.0 * distance(d, site_a));
	m = max(m, 0.62 - 2.5 * distance(d, site_b));
	return m;
}

float clouds(vec3 d) {
	vec3 q = rot_y(cloud_rot) * d;
	float c = fbm(q * 4.0 + vec3(0.0, time * 0.002, 0.0), 6);
	float bands = 0.5 + 0.5 * sin(q.y * 9.0 + fbm(q * 2.0, 3) * 4.0);
	float a = smoothstep(0.65, 0.82, c * (0.75 + 0.35 * bands));
	a *= smoothstep(0.05, 0.11, acos(clamp(dot(d, normalize(site_a)), -1.0, 1.0)));
	a *= smoothstep(0.05, 0.11, acos(clamp(dot(d, normalize(site_b)), -1.0, 1.0)));
	return a;
}

void vertex() {
	obj_dir = normalize(VERTEX);
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 d = normalize(obj_dir);
	vec3 n = normalize(world_n);
	vec3 L = normalize(sun_dir);
	vec3 V = normalize(CAMERA_POSITION_WORLD - (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float m = land_mask(d);
	float is_land = smoothstep(0.495, 0.505, m);
	float shore = smoothstep(0.47, 0.5, m) * (1.0 - is_land);
	float lat = abs(d.y);
	float moist = fbm(d * 5.0 + 20.0, 5);
	float mount = ridged(d * 6.0 + 3.0, 5) * smoothstep(0.52, 0.65, m);
	vec3 forest = vec3(0.07, 0.16, 0.05);
	vec3 grass = vec3(0.2, 0.3, 0.1);
	vec3 desert = vec3(0.5, 0.4, 0.27);
	vec3 rock = vec3(0.35, 0.3, 0.26);
	vec3 snow = vec3(0.9, 0.93, 0.96);
	vec3 land = mix(desert, mix(grass, forest, smoothstep(0.45, 0.65, moist)), smoothstep(0.38, 0.52, moist + lat * 0.4));
	land = mix(land, rock, smoothstep(0.25, 0.55, mount));
	land = mix(land, snow, smoothstep(0.72, 0.82, lat + mount * 0.25));
	// fine detail fades in as the camera gets close (pixel footprint from derivatives)
	float fw = length(fwidth(d));
	float near1 = 1.0 - smoothstep(0.0004, 0.002, fw);
	float near2 = 1.0 - smoothstep(0.00005, 0.0003, fw);
	float fine = fbm(d * 40.0, 4);
	fine = mix(fine, fine * 0.6 + 0.4 * fbm(d * 400.0, 4), near1 * detail);
	fine = mix(fine, fine * 0.7 + 0.3 * fbm(d * 3000.0, 3), near2 * detail);
	land *= 0.8 + 0.4 * fine;
	vec3 ocean = mix(vec3(0.01, 0.04, 0.12), vec3(0.03, 0.22, 0.3), shore);
	float ice = smoothstep(0.86, 0.9, lat + 0.05 * fbm(d * 12.0, 3));
	vec3 albedo = mix(ocean, land, is_land);
	albedo = mix(albedo, snow, ice);
	// relief: derivative bump mapping from the terrain height (mountains, hills, fine detail)
	float hgt = (mount * 1.5 + fine * 0.6) * is_land;
	vec3 pu = normalize(world_p - MODEL_MATRIX[3].xyz);   // unit sphere, world orientation
	vec3 dpdx = dFdx(pu);
	vec3 dpdy = dFdy(pu);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	if (abs(det) > 1e-20) {
		vec3 grad = (dFdx(hgt) * r1 + dFdy(hgt) * r2) / det;
		float relief = 0.004 * (0.3 + 0.7 * near1);   // ~2.5 km of apparent relief on R = 600 km
		n = normalize(n - grad * relief * (1.0 - smoothstep(0.003, 0.02, fw)));
	}
	float ndl = dot(n, L);
	float day = smoothstep(-0.08, 0.15, ndl);
	// cloud shadow
	float cs = clouds(normalize(d + L * 0.01));
	float light = max(ndl, 0.0) * (1.0 - 0.6 * cs);
	vec3 col = albedo * light * 1.7;
	// ocean glint
	vec3 H = normalize(L + V);
	vec3 ng = normalize(world_n);
	float fres = 0.02 + 0.98 * pow(1.0 - max(dot(ng, V), 0.0), 5.0);
	float wave = 0.85 + 0.3 * fbm(d * 900.0 + time * 0.01, 3) * near1;
	float spec = (pow(max(dot(ng, H), 0.0), 220.0 * wave) * 5.0 + pow(max(dot(ng, H), 0.0), 18.0) * 0.12) * (1.0 - is_land) * (1.0 - ice);
	col += vec3(1.0, 0.92, 0.8) * spec * (0.3 + fres * 2.0) * step(0.0, dot(ng, L)) * (1.0 - 0.8 * cs);
	col = mix(col, col + vec3(0.04, 0.08, 0.14) * day, fres * (1.0 - is_land) * 0.6);
	// terminator warmth
	col += vec3(0.6, 0.25, 0.08) * exp(-pow(ndl / 0.06, 2.0)) * 0.12;
	// city lights on the night side
	float city = smoothstep(0.62, 0.8, fbm(d * 60.0, 4)) * smoothstep(0.35, 0.6, fbm(d * 7.0 + 5.0, 3));
	city *= is_land * (1.0 - ice) * (1.0 - smoothstep(0.25, 0.4, 1.0 - moist));
	col += vec3(1.0, 0.65, 0.3) * city * (1.0 - day) * 1.6;
	ALBEDO = col;
}
