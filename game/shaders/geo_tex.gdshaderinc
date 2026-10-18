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
