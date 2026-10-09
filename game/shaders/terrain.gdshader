shader_type spatial;
// Local high-detail ground patch (launch site, runway region, lunar landing site).
// Earth: farm plots with hedgerows and roads, forest / meadow / scrub mix, rock on slopes.
// Moon: regolith with craterlets, pebbles and ejecta streaks. Both use derivative bump
// mapping (a procedural normal map) and procedural roughness.
render_mode cull_back;

#include "res://shaders/noise.gdshaderinc"

uniform bool lunar = false;
uniform vec3 tint_a : source_color = vec3(0.2, 0.3, 0.1);
uniform vec3 tint_b : source_color = vec3(0.35, 0.33, 0.22);
uniform float edge_fade = 1.0;
uniform float bump = 1.0;

varying vec3 lpos;
varying vec3 lnrm;

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
}

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec3 p = lpos;
	float dist = length(VERTEX);
	float n1 = fbm(p * 0.0015, 5);
	float n2 = fbm(p * 0.03, 4);
	float n3 = fbm(p * 0.6, 3);
	float slope = 1.0 - clamp(normalize(lnrm).y, 0.0, 1.0);
	vec3 col;
	float h = 0.0;
	float rough = 0.9;
	if (lunar) {
		vec2 c1 = cellular(p * 0.02);
		vec2 c2 = cellular(p * 0.11 + 3.0);
		float crater = smoothstep(0.32, 0.05, c1.x) * 0.6 + smoothstep(0.3, 0.05, c2.x) * 0.3;
		float rim = exp(-pow((c1.x - 0.34) / 0.05, 2.0)) * 0.5 + exp(-pow((c2.x - 0.32) / 0.05, 2.0)) * 0.25;
		float pebbles = smoothstep(0.75, 0.9, vnoise(p * 3.0)) * (1.0 - smoothstep(30.0, 120.0, dist));
		h = n2 * 1.2 - crater + rim + n3 * 0.25 + pebbles * 0.4;
		float ejecta = smoothstep(0.55, 0.8, fbm(vec3(atan(p.z, p.x) * 12.0, length(p.xz) * 0.002, 0.0), 3)) * 0.12;
		col = vec3(0.3, 0.295, 0.285) * (0.72 + 0.35 * n1 + 0.15 * n2 + 0.08 * n3 + rim * 0.25 + ejecta - crater * 0.12);
		rough = 0.97;
	} else {
		// farm plots: ~180 m cells, slightly rotated grid, crop colour per cell
		vec2 fp = mat2(vec2(0.96, 0.28), vec2(-0.28, 0.96)) * p.xz / 180.0;
		vec2 cell = floor(fp + n1 * 0.6);
		vec2 f = fract(fp + n1 * 0.6);
		float hc = hash2(cell);
		vec3 crop = hc < 0.25 ? vec3(0.42, 0.40, 0.17) : (hc < 0.5 ? vec3(0.17, 0.30, 0.07) : (hc < 0.7 ? vec3(0.33, 0.25, 0.15) : vec3(0.25, 0.36, 0.11)));
		float rows = 0.5 + 0.5 * sin((hc > 0.5 ? f.x : f.y) * 120.0);
		crop *= 0.92 + 0.08 * rows * (1.0 - smoothstep(200.0, 900.0, dist));
		float hedge = smoothstep(0.035, 0.0, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
		float farmland = smoothstep(0.45, 0.6, n1) * (1.0 - smoothstep(0.35, 0.6, slope));
		vec3 wild = mix(vec3(0.08, 0.16, 0.05), vec3(0.24, 0.30, 0.12), smoothstep(0.4, 0.65, n2));   // forest / meadow
		wild = mix(wild, tint_b, smoothstep(0.62, 0.8, n1) * 0.5);
		col = mix(wild, crop, farmland);
		col = mix(col, vec3(0.06, 0.12, 0.04), hedge * farmland * 0.8);
		// country roads
		float road = smoothstep(4.0, 2.5, abs(fract(p.x / 2600.0 + n1 * 0.4) - 0.5) * 2600.0) + smoothstep(4.0, 2.5, abs(fract(p.z / 3100.0 + n2 * 0.1) - 0.5) * 3100.0);
		col = mix(col, vec3(0.32, 0.31, 0.3), clamp(road, 0.0, 1.0) * 0.85);
		col = mix(col, vec3(0.34, 0.31, 0.27), smoothstep(0.25, 0.5, slope));   // rock on steep ground
		col *= 0.8 + 0.25 * n2 + 0.12 * n3;
		h = n2 * 1.5 + n3 * 0.4 + (1.0 - farmland) * vnoise(p * 0.12) * 0.8 - hedge * farmland * -0.6;
		rough = mix(0.85, 0.97, n3);
	}
	// derivative bump mapping in view space (procedural normal map)
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 nn = normalize(NORMAL);
	vec3 r1 = cross(dpdy, nn);
	vec3 r2 = cross(nn, dpdx);
	float det = dot(dpdx, r1);
	if (abs(det) > 1e-8) {
		vec3 grad = (dFdx(h) * r1 + dFdy(h) * r2) / det;
		NORMAL = normalize(nn - grad * bump * 1.5 * (1.0 - smoothstep(800.0, 4000.0, dist)));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
