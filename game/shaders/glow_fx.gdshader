shader_type spatial;
// Generic additive energy effect: tractor beam, laser, plasma sheath, hyperspace tunnel.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/noise.gdshaderinc"

uniform vec4 color : source_color = vec4(0.3, 0.7, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float time = 0.0;
uniform int mode = 0; // 0 beam, 1 laser, 2 plasma, 3 hyperspace
uniform vec3 flow_dir = vec3(0.0, 0.0, -1.0);

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float fres = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = 0.0;
	if (mode == 0) {
		float rings = 0.5 + 0.5 * sin(lp.y * 6.0 + time * 10.0);
		a = pow(fres, 2.0) * (0.35 + 0.65 * rings);
	} else if (mode == 1) {
		a = pow(fres, 3.0) * 3.0;
	} else if (mode == 2) {
		vec3 n = normalize(lp);
		float front = max(dot(n, normalize(flow_dir)), 0.0);
		float turb = fbm(lp * 0.6 + vec3(0.0, 0.0, time * 6.0), 4);
		a = pow(front, 2.0) * (0.4 + turb) * (1.0 - pow(fres, 3.0) * 0.5);
	} else {
		float ang = atan(lp.x, lp.z);
		float streak = pow(vnoise(vec3(ang * 20.0, lp.y * 0.05 - time * 8.0, 0.0)), 6.0);
		float swirl = fbm(vec3(ang * 3.0, lp.y * 0.02 - time * 2.0, time * 0.3), 4);
		a = streak * 6.0 + swirl * 0.4;
	}
	ALBEDO = color.rgb * a * intensity;
}
