shader_type spatial;
// Earth seen from orbit and from the air. Unshaded: lit here so the 600 km sphere looks right at
// any distance and in scaled space (VR far plane). Physically motivated:
//  - sunlight reaches the ground through the same Rayleigh/Mie/ozone air as the sky
//    (atmo_common): white at noon, orange-red along the terminator;
//  - the ground you look at is dimmed by the air between you and it (aerial perspective);
//    atmosphere.gdshader adds the in-scattered blue on top;
//  - oceans: Fresnel sky reflection + a GGX sun glint (Blue Marble ocean colour + a land mask);
//  - relief from a DEM normal map (GEBCO, baked by tools/fetch_assets.sh);
//  - soft cloud shadows cast along the sun direction from the 4.5 km deck;
//  - Black Marble city lights fading in through the terminator.
// The procedural planet stays as the fallback when no NASA textures are installed.
// lod = true: drawn on the real-size LOD terrain chunks (scripts/world/planet_lod.gd): the
// direction + height come per vertex (CUSTOM0), the ground normal from the mesh, water and
// area-pack coverage from UV2; area packs (tools/area_manager.py) add Sentinel-2 imagery.
render_mode unshaded, cull_back;

#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/geo_tex.gdshaderinc"
#include "res://shaders/atmo_common.gdshaderinc"

uniform bool use_tex = false;
uniform bool use_normal = false;   // DEM normal map + land mask present
uniform sampler2D day_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D night_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D height_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : filter_linear_mipmap, repeat_enable;   // RG = east, north slope (BC5)
uniform sampler2D mask_tex : filter_linear_mipmap, repeat_enable;   // 1 = land

uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform float time = 0.0;
uniform vec3 site_a = vec3(1.0, 0.0, 0.0);
uniform vec3 site_b = vec3(0.0, 0.0, 1.0);
uniform float cloud_rot = 0.0;
uniform float detail = 1.0;
uniform float relief = 1.0;
uniform float cloud_h_km = 4.5;
uniform float city_gain = 1.4;
// ---- LOD terrain mode
uniform bool lod = false;
uniform vec3 cam_planet_km = vec3(0.0, 0.0, 7000.0);   // camera, planet-centred, km
uniform vec3 wave_shift = vec3(0.0);                  // camera planet position mod 4096 m
uniform float lod_scale = 1.0;                         // scaled-space factor (world units -> m)
uniform int pack_count = 0;
uniform vec4 pack_box0 = vec4(0.0);    // S, W, N, E (degrees)
uniform vec4 pack_box1 = vec4(0.0);
uniform vec4 pack_box2 = vec4(0.0);
uniform vec4 pack_box3 = vec4(0.0);
uniform sampler2D pack_tex0 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D pack_tex1 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D pack_tex2 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D pack_tex3 : source_color, filter_linear_mipmap, repeat_disable;
varying vec4 lod_c;      // dir.xyz, height m
varying vec2 lod_w;      // water 0..1, pack coverage 0..1
varying vec3 lod_n;
varying vec3 wpos;

varying vec3 obj_dir;
varying vec3 cam_obj_km;    // camera, planet-centred object space, km (scale removed)
varying vec3 sun_obj;       // sun direction in object space

mat3 rot_y(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }

float land_mask(vec3 d) {
	float c = fbm(d * 1.8 + vec3(2.0, 0.0, 5.0), 7);
	c += 0.12 * fbm(d * 9.0, 4) * detail;
	float m = c;
	m = max(m, 0.62 - 3.0 * distance(d, site_a));
	m = max(m, 0.62 - 2.5 * distance(d, site_b));
	return m;
}

float clear_sites(vec3 d) {
	float a = smoothstep(0.05, 0.11, acos(clamp(dot(d, normalize(site_a)), -1.0, 1.0)));
	return a * smoothstep(0.05, 0.11, acos(clamp(dot(d, normalize(site_b)), -1.0, 1.0)));
}

float clouds_at(vec3 d, float widen) {
	vec3 q = rot_y(cloud_rot) * d;
	if (use_tex) {
		float ct = geo_sample_soft(cloud_tex, geo_uv(q), widen).r;
		return smoothstep(0.12, 0.9, ct) * clear_sites(d);
	}
	float c = fbm(q * 4.0 + vec3(0.0, time * 0.002, 0.0), 6);
	float bands = 0.5 + 0.5 * sin(q.y * 9.0 + fbm(q * 2.0, 3) * 4.0);
	return smoothstep(0.65, 0.82, c * (0.75 + 0.35 * bands)) * clear_sites(d);
}

void vertex() {
	if (lod) {   // chunk nodes are never rotated: world axes = planet axes
		lod_c = CUSTOM0;
		obj_dir = CUSTOM0.xyz;
		lod_w = UV2;
		lod_n = NORMAL;
		cam_obj_km = cam_planet_km;
		sun_obj = sun_dir;
		wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	} else {
		obj_dir = normalize(VERTEX);
		mat4 inv = inverse(MODEL_MATRIX);
		cam_obj_km = (inv * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz * 0.001;
		sun_obj = normalize((inv * vec4(sun_dir, 0.0)).xyz);
		lod_c = vec4(obj_dir, 0.0);
		lod_w = vec2(0.0);
		lod_n = obj_dir;
		wpos = vec3(0.0);
	}
}

vec4 pack_color(vec2 ll, vec4 box, sampler2D t) {
	vec2 uv = vec2((ll.y - box.y) / (box.w - box.y), (box.z - ll.x) / (box.z - box.x));
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec4(0.0);
	vec2 e = min(uv, 1.0 - uv);
	return vec4(texture(t, uv).rgb, smoothstep(0.0, 0.01, min(e.x, e.y)));
}

// small wind waves near the camera: sines with periods dividing 4096 m (wave_shift keeps the
// phase continuous and precise on a 6371 km planet); returns a tangent-plane slope
vec2 wave_slope(vec3 p, float t) {
	vec2 s = vec2(0.0);
	vec2 q = vec2(p.x + p.y * 0.37, p.z - p.y * 0.21);
	float k0 = 6.2831853 / 4096.0;
	vec2 dirs[5] = vec2[](vec2(0.8, 0.6), vec2(-0.45, 0.89), vec2(0.97, -0.24), vec2(0.2, -0.98), vec2(-0.7, -0.71));
	float ns[5] = float[](64.0, 112.0, 192.0, 320.0, 576.0);
	for (int i = 0; i < 5; i++) {
		float k = k0 * ns[i];
		float a = 0.06 / (1.0 + float(i) * 0.6);
		float ph = dot(dirs[i], q) * k - t * sqrt(9.81 * k);
		s += dirs[i] * cos(ph) * a;
	}
	return s;
}

void fragment() {
	vec3 d = normalize(obj_dir);
	vec3 L = normalize(sun_obj);
	vec3 p_km = d * (planet_r_km + lod_c.w * 0.001);
	vec3 V = lod ? normalize(CAMERA_POSITION_WORLD - wpos) : normalize(cam_obj_km - p_km);
	float mu_s = dot(d, L);                // sun elevation (geometric) at this point
	// --- albedo + land/water ---------------------------------------------------------------
	float m = land_mask(d);
	float is_land = smoothstep(0.495, 0.505, m);
	float shore = smoothstep(0.47, 0.5, m) * (1.0 - is_land);
	float lat = abs(d.y);
	float moist = fbm(d * 5.0 + 20.0, 5);
	float mount = ridged(d * 6.0 + 3.0, 5) * smoothstep(0.52, 0.65, m);
	vec3 land = mix(vec3(0.5, 0.4, 0.27), mix(vec3(0.2, 0.3, 0.1), vec3(0.07, 0.16, 0.05), smoothstep(0.45, 0.65, moist)), smoothstep(0.38, 0.52, moist + lat * 0.4));
	land = mix(land, vec3(0.35, 0.3, 0.26), smoothstep(0.25, 0.55, mount));
	land = mix(land, vec3(0.9, 0.93, 0.96), smoothstep(0.72, 0.82, lat + mount * 0.25));
	float fw = length(fwidth(d));
	float near1 = 1.0 - smoothstep(0.0004, 0.002, fw);
	float near2 = 1.0 - smoothstep(0.00005, 0.0003, fw);
	float fine = fbm(d * 40.0, 4);
	fine = mix(fine, fine * 0.6 + 0.4 * fbm(d * 400.0, 4), near1 * detail);
	fine = mix(fine, fine * 0.7 + 0.3 * fbm(d * 3000.0, 3), near2 * detail);
	land *= 0.8 + 0.4 * fine;
	vec3 ocean = mix(vec3(0.01, 0.04, 0.12), vec3(0.03, 0.22, 0.3), shore);
	float ice = smoothstep(0.86, 0.9, lat + 0.05 * fbm(d * 12.0, 3));
	vec3 albedo = mix(mix(ocean, land, is_land), vec3(0.9, 0.93, 0.96), ice);
	vec2 guv = geo_uv(d);
	float tex_h = 0.0;
	if (use_tex) {
		tex_h = geo_sample(height_tex, guv).r;
		vec3 dayc = geo_sample(day_tex, guv).rgb;
		if (use_normal) {
			is_land = geo_sample(mask_tex, guv).r;
		} else {   // land / water from the day image (water is dark and blue-dominant)
			float water = smoothstep(0.02, 0.06, dayc.b - max(dayc.r, dayc.g) * 0.9) * (1.0 - smoothstep(0.003, 0.02, tex_h));
			is_land = 1.0 - water;
		}
		ice = smoothstep(0.55, 0.75, min(dayc.r, min(dayc.g, dayc.b)));
		albedo = dayc * mix(1.0, 0.92 + 0.16 * fine, is_land);
	}
	if (lod) {
		float cov = lod_w.y;
		// downloaded area: its own water mask (OSM lakes/rivers + DEM sea) and Sentinel-2 imagery
		is_land = mix(is_land, 1.0 - smoothstep(0.35, 0.65, lod_w.x), cov);
		if (pack_count > 0) {
			vec3 g = normalize(geo_from_game * d);
			vec2 ll = vec2(degrees(asin(clamp(g.y, -1.0, 1.0))), degrees(atan(g.x, -g.z)));
			vec4 pc = pack_color(ll, pack_box0, pack_tex0);
			if (pack_count > 1 && pc.a <= 0.0) pc = pack_color(ll, pack_box1, pack_tex1);
			if (pack_count > 2 && pc.a <= 0.0) pc = pack_color(ll, pack_box2, pack_tex2);
			if (pack_count > 3 && pc.a <= 0.0) pc = pack_color(ll, pack_box3, pack_tex3);
			albedo = mix(albedo, pc.rgb * (0.94 + 0.12 * fine), pc.a);
			ice *= 1.0 - pc.a;
		}
	}
	float water = (1.0 - is_land) * (1.0 - ice);
	// water is water: deep blue body colour whatever the imagery shows (silt, algae, shadow)
	albedo = mix(albedo, mix(vec3(0.012, 0.04, 0.075), vec3(0.03, 0.1, 0.14), shore), water * 0.85);
	// --- normal ----------------------------------------------------------------------------
	vec3 n = d;
	if (lod) {   // real relief from the LOD mesh; the DEM normal map adds detail from far away
		n = normalize(lod_n);
		if (use_tex && use_normal) {
			vec3 nt;
			nt.xy = geo_sample(normal_tex, guv).rg * 2.0 - 1.0;
			nt.xy *= relief * is_land * (1.0 - near1) * 0.6;
			nt.z = sqrt(max(1.0 - dot(nt.xy, nt.xy), 0.05));
			n = normalize(n + geo_tbn(d) * nt - d);
		}
	} else if (use_tex && use_normal) {
		vec3 nt;
		nt.xy = geo_sample(normal_tex, guv).rg * 2.0 - 1.0;
		nt.xy *= relief * is_land;
		nt.z = sqrt(max(1.0 - dot(nt.xy, nt.xy), 0.05));
		n = normalize(geo_tbn(d) * nt);
	} else {   // derivative bump mapping from the (procedural or 8-bit) height
		float hgt = use_tex ? tex_h * 6.0 + fine * 0.25 * is_land : (mount * 1.5 + fine * 0.6) * is_land;
		vec3 dpdx = dFdx(d);
		vec3 dpdy = dFdy(d);
		vec3 r1 = cross(dpdy, d);
		vec3 r2 = cross(d, dpdx);
		float det = dot(dpdx, r1);
		if (abs(det) > 1e-20) {
			vec3 grad = (dFdx(hgt) * r1 + dFdy(hgt) * r2) / det;
			n = normalize(d - grad * 0.004 * (0.3 + 0.7 * near1) * (1.0 - smoothstep(0.003, 0.02, fw)));
		}
	}
	// --- light -----------------------------------------------------------------------------
	vec3 T_sun = trans_to_space(p_km + d * 0.05, L);
	vec3 sunlight = sun_intensity * T_sun * smoothstep(-0.02, 0.02, mu_s);   // planet shadow (soft edge)
	// blue skylight fill: the lit sky dome over this point (also reddens / dies with the sun)
	vec3 sky = vec3(0.32, 0.5, 0.95) * 0.09 * sun_intensity * smoothstep(-0.1, 0.25, mu_s) * mix(vec3(1.0), T_sun, 0.5);
	// cloud shadow: the cloud above along the sun ray (4.5 km up), blurred into a soft penumbra
	vec3 lt = L - d * mu_s;
	vec3 sh_dir = normalize(d + lt * (cloud_h_km / planet_r_km) / max(mu_s, 0.1));
	float cs = clouds_at(sh_dir, 4.0);
	float shadow = 1.0 - 0.7 * cs;
	float ndl = max(dot(n, L), 0.0);
	vec3 col = albedo * (sunlight * ndl * shadow + sky * (1.0 - 0.3 * cs));
	// --- ocean: Fresnel sky reflection + GGX sun glint -------------------------------------
	if (water > 0.001) {
		vec3 nw = d;
		nw = normalize(nw + (vec3(fbm(d * 900.0 + time * 0.01, 3), fbm(d * 900.0 + 31.0 - time * 0.01, 3), 0.5) - 0.5) * 0.04 * near1);
		if (lod) {   // wind waves within a few km of the camera
			float dist_m = length(wpos) / max(lod_scale, 1e-6);
			float wk = 1.0 - smoothstep(1500.0, 9000.0, dist_m);
			if (wk > 0.0) {
				vec2 sl = wave_slope(wpos / max(lod_scale, 1e-6) + wave_shift, time);
				vec3 t1 = normalize(cross(d, vec3(0.0, 0.0, 1.0)) + vec3(1e-4, 0.0, 0.0));
				vec3 t2 = cross(d, t1);
				nw = normalize(nw - (t1 * sl.x + t2 * sl.y) * wk);
			}
		}
		float ndv = max(dot(nw, V), 1e-3);
		float ndl_w = max(dot(nw, L), 0.0);
		vec3 H = normalize(L + V);
		float ndh = max(dot(nw, H), 0.0);
		float vdh = max(dot(V, H), 0.0);
		float rough = mix(0.22, lod ? 0.06 : 0.09, near1);              // wave slopes: wider glint from orbit
		float a2 = rough * rough * rough * rough;
		float dd = ndh * ndh * (a2 - 1.0) + 1.0;
		float D = a2 / (PI * dd * dd);
		float k = rough * rough * 0.5;
		float G = (ndv / (ndv * (1.0 - k) + k)) * (ndl_w / (ndl_w * (1.0 - k) + k));
		float F = 0.02 + 0.98 * pow(1.0 - vdh, 5.0);
		float spec = min(D * G * F / (4.0 * ndv * max(ndl_w, 1e-3)), 40.0) * ndl_w;
		float Fv = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
		vec3 sky_refl = vec3(0.3, 0.48, 0.85) * 0.35 * sun_intensity * smoothstep(-0.1, 0.3, mu_s) * mix(vec3(1.0), T_sun, 0.6);
		col = mix(col, col * (1.0 - Fv) + sky_refl * Fv + sunlight * spec * shadow, water);
	}
	// --- night: city lights fade in through the terminator ---------------------------------
	float night = 1.0 - smoothstep(-0.12, 0.04, mu_s);
	float city;
	if (use_tex) {
		vec3 nl = geo_sample(night_tex, guv).rgb;
		city = smoothstep(0.06, 0.6, dot(nl, vec3(0.3, 0.5, 0.2)));
	} else {
		city = smoothstep(0.62, 0.8, fbm(d * 60.0, 4)) * smoothstep(0.35, 0.6, fbm(d * 7.0 + 5.0, 3));
		city *= is_land * (1.0 - ice) * (1.0 - smoothstep(0.25, 0.4, 1.0 - moist));
	}
	city *= 1.0 - 0.75 * clouds_at(d, 2.0);     // clouds over the city scatter its light away
	col += vec3(1.0, 0.68, 0.34) * city * night * city_gain;
	// --- aerial perspective: the air between the camera and the ground ---------------------
	col *= trans_between(cam_obj_km, p_km + d * 0.05);
	ALBEDO = col;
}
