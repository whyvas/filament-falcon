shader_type spatial;
// Local high-detail ground patch (launch site, runway region, lunar landing site).
render_mode cull_back;

#include "res://shaders/noise.gdshaderinc"

uniform bool lunar = false;
uniform vec3 tint_a : source_color = vec3(0.2, 0.3, 0.1);
uniform vec3 tint_b : source_color = vec3(0.35, 0.33, 0.22);
uniform float edge_fade = 1.0;

varying vec3 lpos;
varying float edge;

void vertex() {
	lpos = VERTEX;
	edge = UV.x;
}

void fragment() {
	vec3 p = lpos;
	float n1 = fbm(p * 0.002, 5);
	float n2 = fbm(p * 0.05, 4);
	float n3 = vnoise(p * 1.3);
	vec3 col;
	if (lunar) {
		vec2 c = cellular(p * 0.02);
		float pits = smoothstep(0.35, 0.1, c.x) * 0.25;
		col = vec3(0.5, 0.49, 0.47) * (0.75 + 0.35 * n1 + 0.15 * n2 + 0.08 * n3 - pits);
		ROUGHNESS = 0.95;
	} else {
		col = mix(tint_a, tint_b, smoothstep(0.35, 0.65, n1));
		col *= 0.75 + 0.35 * n2 + 0.1 * n3;
		float fields = step(0.5, fract(p.x * 0.004 + n1)) * 0.06;
		col += vec3(fields * 0.4, fields, 0.0);
		ROUGHNESS = 0.9;
	}
	ALBEDO = col;
	SPECULAR = 0.2;
	ALPHA = 1.0;
}
