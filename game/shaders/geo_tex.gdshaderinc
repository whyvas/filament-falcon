// Equirectangular lookups for the NASA textures (tools/fetch_assets.sh). geo_from_game rotates a
// game-planet direction into real-world orientation (see scripts/geo/geo.gd).
uniform mat3 geo_from_game = mat3(1.0);

vec2 geo_uv(vec3 d) {
	vec3 g = normalize(geo_from_game * d);
	float lon = atan(g.x, -g.z);
	float lat = asin(clamp(g.y, -1.0, 1.0));
	return vec2(lon / 6.2831853 + 0.5, 0.5 - lat / 3.1415927);
}

// seam-safe sample: unwrap the u derivative across the 0/1 longitude seam
vec4 geo_sample(sampler2D t, vec2 uv) {
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	dx.x -= round(dx.x);
	dy.x -= round(dy.x);
	return textureGrad(t, uv, dx, dy);
}

// same, blurred: the footprint is widened (soft cloud shadows) and never sharper than min_px texels
vec4 geo_sample_soft(sampler2D t, vec2 uv, float widen) {
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	dx.x -= round(dx.x);
	dy.x -= round(dy.x);
	return textureGrad(t, uv, dx * widen, dy * widen);
}

// East / north / up of the texture frame at game direction d, returned in GAME object space
// (columns), for tangent-space normal maps baked in (east, north, up).
mat3 geo_tbn(vec3 d) {
	vec3 g = normalize(geo_from_game * d);
	float lon = atan(g.x, -g.z);
	float lat = asin(clamp(g.y, -1.0, 1.0));
	vec3 east = vec3(cos(lon), 0.0, sin(lon));
	vec3 north = vec3(-sin(lat) * sin(lon), cos(lat), sin(lat) * cos(lon));
	mat3 inv = transpose(geo_from_game);   // rotation: inverse = transpose
	return mat3(inv * east, inv * north, d);
}
