shader_type spatial;
// Detail-region water (scripts/geo/region_view.gd): a deep blue body, Fresnel reflection of the
// sky colour (sky_col, set per frame from the sun's height), the sun's glint from the lit
// GGX specular with a low roughness, and small wind waves. UV = region-local metres (x, z),
// so the wave phase is stable on the real-size planet (no float jitter).
render_mode specular_schlick_ggx;

uniform vec3 deep_col : source_color = vec3(0.015, 0.05, 0.09);
uniform vec3 shallow_col : source_color = vec3(0.03, 0.11, 0.15);
uniform vec3 sky_col : source_color = vec3(0.42, 0.6, 0.85);
uniform float wave_amp = 0.05;

vec2 slope(vec2 p, float t) {
	vec2 s = vec2(0.0);
	vec2 d[4] = vec2[](vec2(0.8, 0.6), vec2(-0.5, 0.86), vec2(0.96, -0.28), vec2(0.1, -0.99));
	float k[4] = float[](0.21, 0.37, 0.83, 1.9);
	for (int i = 0; i < 4; i++) {
		float ph = dot(d[i], p) * k[i] - t * sqrt(9.81 * k[i]);
		s += d[i] * cos(ph) * wave_amp / (1.0 + float(i) * 0.7);
	}
	return s;
}

void fragment() {
	float dist = length(VERTEX);
	vec2 sl = slope(UV, TIME) * (1.0 - smoothstep(300.0, 4000.0, dist));
	// region frame axes in view space: x = east, z = south
	vec3 ex = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	vec3 ez = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	vec3 n = normalize(NORMAL - ex * sl.x - ez * sl.y);
	NORMAL = n;
	float ndv = clamp(dot(n, VIEW), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	vec3 body = mix(shallow_col, deep_col, smoothstep(50.0, 600.0, dist));
	ALBEDO = body * (1.0 - fres);
	EMISSION = sky_col * fres * 0.9;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
