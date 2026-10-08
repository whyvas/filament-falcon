shader_type spatial;
// Spacecraft hull: white ceramic panels with panel lines, black heat-shield tiles on the
// belly (object-space normal facing down), red/blue stripes, grime, and heat glow.
render_mode cull_back;

#include "res://shaders/noise.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.86, 0.87, 0.88);
uniform vec3 stripe_color : source_color = vec3(0.85, 0.25, 0.05);
uniform float belly_tiles = 1.0;
uniform float heat_glow = 0.0;
uniform float panel_scale = 1.6;

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
	vec2 g = abs(fract(uv) - 0.5);
	float line = smoothstep(0.485, 0.497, max(g.x, g.y));
	float belly = smoothstep(-0.2, -0.45, normalize(onrm).y) * belly_tiles;
	vec2 tg = abs(fract(uv * 2.5) - 0.5);
	float tline = smoothstep(0.46, 0.49, max(tg.x, tg.y));
	vec3 col = base_color * (0.92 + 0.08 * hash13(floor(vec3(uv, 1.0))));
	float stripe = step(abs(opos.y - 0.1), 0.12) * step(0.0, -opos.z) * step(abs(opos.x), 2.3);
	col = mix(col, stripe_color, stripe * (1.0 - belly));
	vec3 tile = vec3(0.04) * (0.8 + 0.4 * hash13(floor(vec3(uv * 2.5, 2.0))));
	col = mix(col, tile, belly);
	col *= 1.0 - line * 0.55 - tline * belly * 0.5;
	float grime = fbm(opos * 0.7, 4);
	col *= 0.85 + 0.2 * grime;
	ALBEDO = col;
	ROUGHNESS = mix(0.45, 0.8, belly) + grime * 0.1;
	METALLIC = 0.05;
	EMISSION = vec3(1.0, 0.35, 0.08) * heat_glow * (0.4 + belly) * (0.6 + 0.4 * grime) * 3.0;
}
