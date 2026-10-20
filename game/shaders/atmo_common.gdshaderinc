// Shared atmosphere optics (km, game planet). Same coefficients as atmosphere.gdshader so the
// ground, the clouds and the sky agree: sunlight reddens through the same air you look through.
uniform float planet_r_km = 600.0;
uniform float atmo_r_km = 690.0;
uniform vec3 beta_r = vec3(5.8e-3, 13.5e-3, 33.1e-3);
uniform float beta_m = 3.5e-3;
uniform vec3 beta_o = vec3(0.65e-3, 1.881e-3, 0.085e-3);   // ozone (follows the Rayleigh density here)
uniform float h_r = 5.6;
uniform float h_m = 1.1;
uniform float sun_intensity = 1.9;

vec2 ray_sph(vec3 ro, vec3 rd, float r) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - r * r;
	float h = b * b - c;
	if (h < 0.0) return vec2(1e9, -1e9);
	h = sqrt(h);
	return vec2(-b - h, -b + h);
}

vec3 extinction(float od_r, float od_m) {
	return exp(-((beta_r + beta_o) * od_r + beta_m * 1.1 * od_m));
}

// Transmittance from p (km, planet-centred) toward the sun / along rd to the top of the air.
vec3 trans_to_space(vec3 p, vec3 rd) {
	float len = ray_sph(p, rd, atmo_r_km).y;
	if (len <= 0.0) return vec3(1.0);
	float seg = len / 6.0;
	float od_r = 0.0;
	float od_m = 0.0;
	for (int i = 0; i < 6; i++) {
		float h = max(length(p + rd * (seg * (float(i) + 0.5))) - planet_r_km, 0.0);
		od_r += exp(-h / h_r) * seg;
		od_m += exp(-h / h_m) * seg;
	}
	return extinction(od_r, od_m);
}

// Transmittance between two points (the part of the segment inside the air).
vec3 trans_between(vec3 a, vec3 b) {
	vec3 rd = b - a;
	float L = length(rd);
	if (L < 1e-4) return vec3(1.0);
	rd /= L;
	vec2 at = ray_sph(a, rd, atmo_r_km);
	float t0 = max(at.x, 0.0);
	float t1 = min(at.y, L);
	if (t1 <= t0) return vec3(1.0);
	float seg = (t1 - t0) / 8.0;
	float od_r = 0.0;
	float od_m = 0.0;
	for (int i = 0; i < 8; i++) {
		float h = max(length(a + rd * (t0 + seg * (float(i) + 0.5))) - planet_r_km, 0.0);
		od_r += exp(-h / h_r) * seg;
		od_m += exp(-h / h_m) * seg;
	}
	return extinction(od_r, od_m);
}
