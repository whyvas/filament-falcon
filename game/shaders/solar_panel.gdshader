shader_type spatial;
// Solar array blanket: blue-black cells with silver busbars, per-cell tint variation,
// cell-edge bumps (procedural normal map) and a strong specular sheen.
render_mode cull_disabled;

uniform vec3 cell_color : source_color = vec3(0.04, 0.07, 0.2);

varying vec3 lp;
varying vec3 ln;

float h21(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.7); }

void fragment() {
	vec3 an = abs(ln);
	vec2 uv = (an.z > an.y && an.z > an.x ? lp.xy : (an.y > an.x ? lp.xz : lp.yz)) * 1.4;
	vec2 cell = floor(uv);
	vec2 g = abs(fract(uv) - 0.5);
	float grid = smoothstep(0.44, 0.48, max(g.x, g.y));
	float bus = smoothstep(0.03, 0.0, abs(fract(uv.x * 4.0) - 0.5) - 0.47);
	float tint = h21(cell);
	vec3 cellc = cell_color * (0.8 + 0.4 * tint) + vec3(0.0, 0.01, 0.03) * tint;
	ALBEDO = mix(cellc, vec3(0.75, 0.75, 0.78), max(grid, bus * 0.6));
	METALLIC = mix(0.35, 0.95, grid);
	ROUGHNESS = mix(0.12 + 0.08 * tint, 0.35, grid);
	SPECULAR = 0.9;
	// the face whose dominant object-space axis is negative is the back of the blanket
	float dom = an.z > an.y && an.z > an.x ? ln.z : (an.y > an.x ? ln.y : ln.x);
	if (dom < 0.0) {
		// back of the blanket: light kapton with a fibreglass grid
		ALBEDO = mix(vec3(0.72, 0.6, 0.4), vec3(0.55, 0.5, 0.42), grid);
		METALLIC = 0.0;
		ROUGHNESS = 0.6;
		SPECULAR = 0.4;
	}
	// tilt each cell very slightly so sunlight glints cell by cell
	vec3 n = normalize(NORMAL);
	vec3 t = normalize(cross(n, vec3(0.0, 1.0, 0.1)));
	vec3 b = cross(n, t);
	NORMAL = normalize(n + (t * (h21(cell + 3.1) - 0.5) + b * (h21(cell + 7.7) - 0.5)) * 0.06 * (1.0 - grid));
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}
