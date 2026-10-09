shader_type spatial;
// Procedural PBR hull for spacecraft and the station. Object-space (triplanar-ish) panels:
// - albedo / roughness variation per panel, panel-line grooves and rivet rows via derivative
//   bump mapping (a procedural normal map), grime in recesses, clearcoat on ceramic paint
// - belly heat-shield tiles (black, rough) on down-facing surfaces when belly_tiles = 1
// - mli = 1 turns it into crinkled gold multi-layer insulation foil
// - heat_glow for reentry
render_mode cull_back;

#include "res://shaders/noise.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.86, 0.87, 0.88);
uniform vec3 stripe_color : source_color = vec3(0.85, 0.25, 0.05);
uniform float belly_tiles = 1.0;
uniform float stripes = 1.0;
uniform float heat_glow = 0.0;
uniform float panel_scale = 1.6;
uniform float mli = 0.0;
uniform float metallic_base = 0.05;
uniform float rough_base = 0.42;
uniform float bump_strength = 1.0;

varying vec3 opos;
varying vec3 onrm;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
}

void fragment() {
	vec3 p = opos * panel_scale;
	vec3 an = abs(normalize(onrm));
	vec2 uv = an.x > an.y && an.x > an.z ? p.yz : (an.y > an.z ? p.xz : p.xy);
	// staggered panels (brick-like) so seams do not form one long grid
	vec2 puv = uv * vec2(1.0, 1.6);
	puv.x += 0.5 * mod(floor(puv.y), 2.0);
	vec2 cell = floor(puv);
	vec2 f = fract(puv);
	vec2 g = abs(f - 0.5);
	float edge_d = 0.5 - max(g.x, g.y);                    // 0 at the seam
	float groove = 1.0 - smoothstep(0.0, 0.018, edge_d);
	// rivet rows just inside the panel edges
	vec2 rq = fract(puv * 10.0) - 0.5;
	float rivet = (1.0 - smoothstep(0.12, 0.2, length(rq))) * (1.0 - smoothstep(0.03, 0.06, edge_d)) * step(0.02, edge_d);
	float pid = hash13(vec3(cell, 7.0));
	float belly = smoothstep(-0.2, -0.45, normalize(onrm).y) * belly_tiles;
	vec2 tg = abs(fract(uv * 2.5) - 0.5);
	float tgroove = 1.0 - smoothstep(0.0, 0.03, 0.5 - max(tg.x, tg.y));
	float grime = fbm(opos * 0.7, 4);
	float fine = fbm(opos * 9.0, 3);
	vec3 col = base_color * (0.93 + 0.07 * pid);
	float stripe = step(abs(opos.y - 0.1), 0.12) * step(0.0, -opos.z) * step(abs(opos.x), 2.3) * stripes;
	col = mix(col, stripe_color, stripe * (1.0 - belly));
	vec3 tile = vec3(0.035) * (0.75 + 0.5 * hash13(floor(vec3(uv * 2.5, 2.0))));
	col = mix(col, tile, belly);
	float rough = rough_base + 0.12 * (pid - 0.5) + grime * 0.08;
	rough = mix(rough, 0.85, belly);
	float metal = metallic_base;
	float h = -groove * 0.6 + rivet * 0.35 - tgroove * belly * 0.5 + fine * 0.05;
	if (mli > 0.5) {
		float crinkle = fbm(opos * 5.0, 5);
		float wr = ridged(opos * 2.2 + 1.0, 4);
		col = vec3(0.92, 0.68, 0.28) * (0.75 + 0.35 * crinkle);
		metal = 1.0;
		rough = 0.22 + 0.25 * wr;
		h = crinkle * 1.2 + wr * 0.8 - groove * 0.3;
		CLEARCOAT = 0.0;
	} else {
		CLEARCOAT = 0.35 * (1.0 - belly);
		CLEARCOAT_ROUGHNESS = 0.3;
	}
	col *= 1.0 - groove * 0.35 - tgroove * belly * 0.4;
	col *= 0.86 + 0.18 * grime;
	col *= 1.0 - groove * grime * 0.25;      // dirt collects in the seams
	// derivative bump mapping (view space)
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 nn = normalize(NORMAL);
	vec3 r1 = cross(dpdy, nn);
	vec3 r2 = cross(nn, dpdx);
	float det = dot(dpdx, r1);
	if (abs(det) > 1e-10) {
		vec3 grad = (dFdx(h) * r1 + dFdy(h) * r2) / det;
		float fade = 1.0 - smoothstep(40.0, 200.0, length(VERTEX));
		NORMAL = normalize(nn - grad * 0.012 * bump_strength * fade);
	}
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	METALLIC = metal;
	EMISSION = vec3(1.0, 0.35, 0.08) * heat_glow * (0.4 + belly) * (0.6 + 0.4 * grime) * 3.0;
}
