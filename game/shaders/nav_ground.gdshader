shader_type canvas_item;
// Nav map "ground track" inset (scripts/ui/nav_globe.gd): a north-up gnomonic close-up of the
// ground under the ship, from the same NASA textures as the globe, plus the nearest area pack's
// imagery and the OSM overlay that tools/nav_overlay.py rasterizes from the cached area extracts
// (water, roads, built-up areas). Day / night follows the real terminator; roads glow at night.
#include "res://shaders/noise.gdshaderinc"

uniform vec3 up_geo = vec3(0.0, 1.0, 0.0);     // geo direction under the ship
uniform vec3 east_geo = vec3(1.0, 0.0, 0.0);
uniform vec3 north_geo = vec3(0.0, 0.0, -1.0);
uniform float half_r = 0.01;                    // half width / body radius
uniform int kind = 0;                           // 0 Earth, 1 Moon
uniform bool use_tex = false;
uniform bool use_mask = false;
uniform vec3 sun_dir = vec3(0.6, 0.35, -0.7);
uniform mat3 geo_from_game = mat3(1.0);
uniform float cloud_alpha = 0.4;
uniform sampler2D day_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D night_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_tex : filter_linear_mipmap, repeat_enable;
uniform bool use_pack = false;
uniform vec4 pack_box = vec4(0.0);              // S, W, N, E degrees
uniform sampler2D pack_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform bool use_osm = false;
uniform vec4 osm_box = vec4(0.0);
uniform sampler2D osm_tex : source_color, filter_linear_mipmap, repeat_disable;

vec4 samp(sampler2D t, vec2 uv) {
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	dx.x -= round(dx.x);
	dy.x -= round(dy.x);
	return textureGrad(t, uv, dx, dy);
}

float box_fade(vec2 bu) {   // 1 inside the box, fading out over its outer 2 %
	vec2 e = min(bu, 1.0 - bu);
	return smoothstep(0.0, 0.02, min(e.x, e.y));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec3 g = normalize(up_geo + (east_geo * p.x - north_geo * p.y) * half_r);
	float lon = atan(g.x, -g.z);
	float lat = asin(clamp(g.y, -1.0, 1.0));
	vec2 uv = vec2(lon / 6.2831853 + 0.5, 0.5 - lat / 3.1415927);
	vec2 ll = vec2(degrees(lat), degrees(lon));
	vec3 n = transpose(geo_from_game) * g;           // game direction (lighting)
	float mu = dot(n, normalize(sun_dir));
	float lit = clamp(mu, 0.0, 1.0);
	float dayf = smoothstep(-0.1, 0.12, mu);
	vec3 col;
	float cl = 0.0;
	float city = 0.0;
	if (use_tex) {
		col = samp(day_tex, uv).rgb;
		if (kind == 0) {
			cl = samp(cloud_tex, uv).r;
			city = smoothstep(0.05, 0.6, dot(samp(night_tex, uv).rgb, vec3(0.3, 0.5, 0.2)));
		}
	} else if (kind == 0) {
		float h = fbm(g * 2.2, 5) + 0.25 * fbm(g * 9.0, 3) + 0.05 * fbm(g * 400.0, 3);
		col = mix(vec3(0.02, 0.07, 0.2), vec3(0.2, 0.32, 0.12), smoothstep(0.56, 0.6, h));
	} else {
		col = vec3(0.55, 0.54, 0.52) * (0.8 + 0.3 * fbm(g * 300.0, 4));
	}
	if (use_pack) {
		vec2 bu = vec2((ll.y - pack_box.y) / (pack_box.w - pack_box.y), (pack_box.z - ll.x) / (pack_box.z - pack_box.x));
		if (bu.x > 0.0 && bu.x < 1.0 && bu.y > 0.0 && bu.y < 1.0) {
			col = mix(col, texture(pack_tex, bu).rgb, box_fade(bu));
		}
	}
	vec4 osm = vec4(0.0);
	if (use_osm) {
		vec2 bu = vec2((ll.y - osm_box.y) / (osm_box.w - osm_box.y), (osm_box.z - ll.x) / (osm_box.z - osm_box.x));
		if (bu.x > 0.0 && bu.x < 1.0 && bu.y > 0.0 && bu.y < 1.0) {
			osm = texture(osm_tex, bu);
			osm.a *= box_fade(bu);
		}
	}
	col = col * (0.03 + 1.2 * pow(lit, 0.75));
	col = mix(col, vec3(0.02 + 1.0 * lit), clamp(cl * cloud_alpha, 0.0, 1.0));
	col += vec3(1.0, 0.68, 0.34) * city * (1.0 - dayf) * 1.2;
	// OSM layer: readable by day, its roads light up at night
	col = mix(col, osm.rgb * (0.35 + 0.75 * lit), osm.a * 0.85);
	col += vec3(1.0, 0.7, 0.35) * osm.a * smoothstep(0.6, 0.9, osm.r) * (1.0 - dayf) * 0.5;
	// faint lat/lon graticule every degree
	vec2 fr = abs(fract(ll + 0.5) - 0.5) / fwidth(ll);
	col = mix(col, vec3(0.4, 0.7, 1.0), (1.0 - clamp(min(fr.x, fr.y), 0.0, 1.0)) * 0.25);
	COLOR = vec4(col, 1.0);
}
