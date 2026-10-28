shader_type canvas_item;
render_mode blend_disabled;   // the only quad in its viewport: store straight colour + alpha
// Nav map globe (scripts/ui/nav_globe.gd): a lit, textured planet disc drawn into a small 2D
// SubViewport that only re-renders a few times a second. The map is a top view (world XZ seen
// from +Y), so the visible hemisphere's normal at disc point p is (p.x, sqrt(1 - |p|^2), p.y).
// Earth: Blue Marble day + Black Marble city lights + clouds (+ land mask for ocean glint),
// terminator, limb haze and an atmosphere glow ring. Moon: LROC colour + LOLA relief shading.
// Textures are the ones the 3D world already uses; without them a procedural planet is drawn.
#include "res://shaders/noise.gdshaderinc"

uniform vec2 vp_size = vec2(256.0);
uniform vec2 center_px = vec2(128.0);
uniform float radius_px = 100.0;
uniform float glow_px = 10.0;        // atmosphere ring width (0 = none)
uniform int kind = 0;                // 0 Earth, 1 Moon, 2 other (flat colour)
uniform bool use_tex = false;
uniform bool use_mask = false;
uniform vec3 base_color : source_color = vec3(0.5);
uniform vec3 sun_dir = vec3(0.6, 0.35, -0.7);
uniform mat3 geo_from_game = mat3(1.0);
uniform float cloud_alpha = 0.85;
uniform sampler2D day_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D night_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D height_tex : filter_linear_mipmap, repeat_enable;   // Moon LOLA (16-bit)

vec2 ll_of(vec3 g) {   // (lon, lat) radians of a geo direction
	return vec2(atan(g.x, -g.z), asin(clamp(g.y, -1.0, 1.0)));
}

vec2 uv_of(vec2 ll) {
	return vec2(ll.x / 6.2831853 + 0.5, 0.5 - ll.y / 3.1415927);
}

vec4 samp(sampler2D t, vec2 uv) {   // seam-safe across the 0/1 longitude wrap
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	dx.x -= round(dx.x);
	dy.x -= round(dy.x);
	return textureGrad(t, uv, dx, dy);
}

vec3 atmo_col(float mu) {   // sunlit blue, orange at the terminator, nothing on the night side
	return mix(vec3(1.0, 0.42, 0.16), vec3(0.32, 0.58, 1.0), smoothstep(-0.02, 0.35, mu)) * smoothstep(-0.28, 0.08, mu);
}

vec3 earth(vec3 n, vec3 sd) {
	vec3 g = normalize(geo_from_game * n);
	vec2 ll = ll_of(g);
	vec2 uv = uv_of(ll);
	float mu = dot(n, sd);
	vec3 day;
	float cl;
	float city;
	float ocean;
	if (use_tex) {
		day = samp(day_tex, uv).rgb;
		cl = samp(cloud_tex, uv).r;
		vec3 nl = samp(night_tex, uv).rgb;
		city = smoothstep(0.05, 0.6, dot(nl, vec3(0.3, 0.5, 0.2)));
		ocean = use_mask ? 1.0 - samp(mask_tex, uv).r : smoothstep(0.02, 0.1, day.b - max(day.r, day.g));
	} else {   // procedural stand-in (assets not fetched yet)
		float el = fbm(g * 2.2, 5) + 0.25 * fbm(g * 9.0, 3);
		float land = smoothstep(0.56, 0.6, el);
		float ice = smoothstep(0.82, 0.9, abs(g.y) + 0.05 * fbm(g * 12.0, 2));
		day = mix(vec3(0.02, 0.07, 0.2), mix(vec3(0.16, 0.3, 0.1), vec3(0.42, 0.35, 0.22), smoothstep(0.62, 0.75, el)), land);
		day = mix(day, vec3(0.9), ice);
		cl = smoothstep(0.5, 0.75, fbm(g * 4.0 + vec3(3.0), 5)) ;
		city = land * (1.0 - ice) * smoothstep(0.7, 0.8, fbm(g * 40.0, 3)) * 0.6;
		ocean = 1.0 - land;
	}
	float lit = clamp(mu, 0.0, 1.0);
	float dayf = smoothstep(-0.1, 0.12, mu);
	vec3 col = day * (0.015 + 1.25 * pow(lit, 0.75)) * mix(vec3(1.0, 0.75, 0.55), vec3(1.0), smoothstep(0.0, 0.3, mu));
	vec3 h = normalize(sd + vec3(0.0, 1.0, 0.0));     // viewer straight above (+Y)
	col += vec3(1.0, 0.9, 0.75) * pow(max(dot(n, h), 0.0), 90.0) * ocean * (1.0 - cl) * 0.7 * dayf;
	vec3 ccol = mix(vec3(1.0, 0.62, 0.38), vec3(1.0), smoothstep(0.0, 0.3, mu)) * (0.02 + 1.05 * lit);
	col = mix(col, ccol, clamp(cl * cloud_alpha, 0.0, 1.0));
	col += vec3(1.0, 0.68, 0.34) * city * (1.0 - smoothstep(-0.12, 0.04, mu)) * (1.0 - 0.7 * cl) * 1.5;
	float fres = pow(1.0 - n.y, 2.5);
	col = mix(col, atmo_col(mu) * 1.1, fres * 0.65);
	return col;
}

vec3 moon(vec3 n, vec3 sd) {   // day_tex = LROC colour, height_tex = LOLA elevation
	vec2 ll = ll_of(n);
	vec2 uv = uv_of(ll);
	vec3 east = vec3(cos(ll.x), 0.0, sin(ll.x));
	vec3 north = vec3(-sin(ll.y) * sin(ll.x), cos(ll.y), sin(ll.y) * cos(ll.x));
	vec3 base;
	vec3 sn = n;
	if (use_tex) {
		base = samp(day_tex, uv).rgb;
		// relief from the elevation gradient, one texel each way at the size shown on screen
		vec2 ts = vec2(textureSize(height_tex, 0));
		float px = clamp(ts.x / (6.2831853 * max(radius_px, 1.0)), 1.0, 8.0);
		vec2 du = vec2(px / ts.x, 0.0);
		vec2 dv = vec2(0.0, px / ts.y);
		float hx = textureLod(height_tex, uv + du, 0.0).r - textureLod(height_tex, uv - du, 0.0).r;
		float hy = textureLod(height_tex, uv - dv, 0.0).r - textureLod(height_tex, uv + dv, 0.0).r;
		float k = 9.0 / px;
		sn = normalize(n - (east * hx / max(cos(ll.y), 0.05) + north * hy) * k);
	} else {
		vec2 cr = cellular(n * 14.0);
		float crater = smoothstep(0.0, 0.25, cr.x) - 0.5 * smoothstep(0.25, 0.32, cr.x);
		float mare = smoothstep(0.5, 0.62, fbm(n * 1.8 + vec3(7.0), 4));
		base = mix(vec3(0.62, 0.6, 0.57), vec3(0.3, 0.3, 0.31), mare) * (0.85 + 0.15 * crater + 0.1 * fbm(n * 30.0, 3));
	}
	float mu0 = max(dot(sn, sd), 0.0);
	float mv = max(n.y, 0.05);
	float ls = 2.0 * mu0 / (mu0 + mv);            // Lommel-Seeliger: the flat-looking full Moon
	float light = mix(mu0, ls, 0.55) * smoothstep(-0.02, 0.06, dot(n, sd));
	return base * (0.012 + 1.15 * light);
}

void fragment() {
	vec2 p = (UV * vp_size - center_px) / max(radius_px, 0.5);
	float r = length(p);
	vec3 sd = normalize(sun_dir);
	float edge = clamp((1.0 - r) * radius_px + 0.5, 0.0, 1.0);    // 1 px anti-aliased limb
	vec4 o = vec4(0.0);
	if (r < 1.0 + 1.5 / max(radius_px, 0.5)) {
		vec2 q = p / max(r, 1.0);
		vec3 n = vec3(q.x, sqrt(max(1.0 - dot(q, q), 0.0)), q.y);
		vec3 c;
		if (kind == 0) {
			c = earth(n, sd);
		} else if (kind == 1) {
			c = moon(n, sd);
		} else {
			c = base_color * (0.05 + 1.0 * max(dot(n, sd), 0.0));
		}
		o = vec4(c, edge);
	}
	if (glow_px > 0.0 && r > 0.9) {
		float t = (r - 1.0) * radius_px / glow_px;     // 0 at the limb, 1 at the outer edge
		vec3 nl = vec3(p.x / r, 0.0, p.y / r);
		float mu = dot(nl, sd);
		float a = t < 0.0 ? 1.0 : exp(-t * 3.2) * (1.0 - smoothstep(0.7, 1.0, t));
		vec3 gc = atmo_col(mu) * 1.3;
		float ga = a * clamp(max(gc.r, max(gc.g, gc.b)), 0.0, 1.0);
		o.rgb = mix(gc, o.rgb, o.a);
		o.a = max(o.a, ga);
	}
	COLOR = o;
}
