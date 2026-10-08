shader_type spatial;
render_mode cull_disabled;

uniform vec3 cell_color : source_color = vec3(0.05, 0.09, 0.25);

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 uv = lp.xz * 1.6;
	vec2 g = abs(fract(uv) - 0.5);
	float grid = smoothstep(0.44, 0.48, max(g.x, g.y));
	ALBEDO = mix(cell_color, vec3(0.75, 0.75, 0.78), grid);
	METALLIC = mix(0.6, 0.9, grid);
	ROUGHNESS = mix(0.18, 0.4, grid);
	SPECULAR = 0.8;
}
