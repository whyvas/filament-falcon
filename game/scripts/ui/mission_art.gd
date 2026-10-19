class_name MissionArt
extends Control
## Vector illustrations for the MISSIONS page, drawn with _draw (no image files): a diagram of
## each mission (orbits, ship + target, route) or, with `patch = true`, a round mission patch.
## Everything is drawn on a 1000 x 600 canvas (patch: 200 x 200) scaled to fit.

var art := "free":
	set(v):
		art = v
		queue_redraw()
var patch := false
var accent := Color(0.4, 0.85, 1.0)
var caption := ""
var mask := Color(0.04, 0.09, 0.15)     # panel colour around a patch

const SPACE := Color(0.02, 0.04, 0.09)
const LINE := Color(0.75, 0.9, 1.0)
const ORANGE := Color(1.0, 0.55, 0.15)
const RED := Color(1.0, 0.3, 0.25)
const GREEN := Color(0.35, 1.0, 0.5)
const YELLOW := Color(1.0, 0.88, 0.35)


func _ready() -> void:
	clip_contents = true
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := 200.0 if patch else 1000.0
	var h := 200.0 if patch else 600.0
	var sc := minf(size.x / w, size.y / h)
	if sc <= 0.0:
		return
	var off := (size - Vector2(w, h) * sc) * 0.5
	draw_set_transform(off, 0.0, Vector2(sc, sc))
	if patch:
		draw_circle(Vector2(100, 100), 98, accent)
		draw_circle(Vector2(100, 100), 90, SPACE)
		_stars(Rect2(20, 20, 160, 160), 14, art.hash())
		draw_set_transform(off + Vector2(100 - 70, 100 - 52) * sc, 0.0, Vector2(sc, sc) * 0.14)
		_scene()
		draw_set_transform(off, 0.0, Vector2(sc, sc))
		draw_arc(Vector2(100, 100), 140, 0, TAU, 96, mask, 100.0)     # hide what spills out of the badge
		draw_arc(Vector2(100, 100), 94, 0, TAU, 96, accent, 8.0)
		draw_arc(Vector2(100, 100), 90, 0, TAU, 64, accent.darkened(0.3), 3.0)
		if caption != "":
			_text(Vector2(100, 178), caption, 15, Color.WHITE)
		return
	draw_rect(Rect2(0, 0, w, h), SPACE)
	_stars(Rect2(0, 0, w, h), 70, art.hash())
	_scene()


# ======================================================================== scenes
func _scene() -> void:
	match art:
		"launch":
			_earth_arc(520.0, Color(0.2, 0.45, 0.9))
			draw_rect(Rect2(150, 495, 70, 12), Color(0.5, 0.5, 0.55))
			_route([Vector2(185, 470), Vector2(260, 300), Vector2(430, 160), Vector2(700, 110)], YELLOW)
			_orbit(Vector2(500, 700), 560, 600, accent)
			_ship(Vector2(300, 260), 0.6, 1.6, true)
			_ship(Vector2(240, 380), 2.6, 0.9, false, Color(0.7, 0.7, 0.75))
			_text(Vector2(800, 90), "ORBIT", 34, accent)
		"alarm":
			_ship(Vector2(200, 330), 1.57, 2.2)
			_warn(Vector2(200, 160), 70)
			var cards := ["LEAK", "POWER", "FIRE", "SENSOR"]
			for i in 4:
				var p := Vector2(430 + i * 140, 300)
				draw_rect(Rect2(p - Vector2(55, 70), Vector2(110, 140)), Color(0.15, 0.1, 0.03))
				draw_rect(Rect2(p - Vector2(55, 70), Vector2(110, 140)), ORANGE, false, 4.0)
				_text(p + Vector2(0, -25), str(i + 1), 40, ORANGE)
				_text(p + Vector2(0, 35), cards[i], 22, Color.WHITE)
				if i < 3:
					_arrow(p + Vector2(60, 0), p + Vector2(82, 0), ORANGE)
			_text(Vector2(640, 470), "COMMANDER FIRES THE NEXT PROBLEM", 26, LINE)
		"dock", "iss":
			if art == "iss":
				_earth_arc(560.0, Color(0.2, 0.45, 0.9))
				var pts := PackedVector2Array()
				for i in 65:
					var a := TAU * i / 64.0
					pts.append(Vector2(500, 330) + Vector2(cos(a) * 430, sin(a) * 120).rotated(-0.35))
				draw_polyline(pts, accent * Color(1, 1, 1, 0.6), 3.0)
				_text(Vector2(850, 170), "51.6°", 30, accent)
				_text(Vector2(500, 560), "REAL ISS POSITION (TLE)", 26, LINE)
			_station(Vector2(330, 280), 1.3)
			_ship(Vector2(720, 280), -1.57, 1.8)
			_route([Vector2(640, 280), Vector2(430, 280)], GREEN)
			draw_arc(Vector2(420, 280), 26, 0, TAU, 32, GREEN, 3.0)
			_text(Vector2(560, 240), "< 0.3 m/s", 28, GREEN)
		"asteroids":
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for i in 16:
				_rock(Vector2(rng.randf_range(420, 960), rng.randf_range(60, 560)), rng.randf_range(14, 60))
			for i in 4:
				_crystal(Vector2(520 + i * 110, 200 + (i % 2) * 180))
			_ship(Vector2(200, 320), -1.2, 1.8)
			_route([Vector2(260, 300), Vector2(500, 230)], YELLOW)
		"eva_window", "eva_antenna", "eva_sample", "eva_rescue", "rescue":
			_ship_side(Vector2(470, 380), 2.2)
			var hatch := Vector2(560, 330)
			match art:
				"eva_window":
					_astro(Vector2(290, 250), 1.3)
					_tether(hatch, Vector2(300, 280))
					draw_arc(Vector2(250, 205), 30, -2.6, -1.2, 12, YELLOW, 4.0)
				"eva_antenna":
					_station(Vector2(820, 160), 1.0)
					_astro(Vector2(700, 210), 1.2)
					draw_line(Vector2(730, 200), Vector2(790, 140), YELLOW, 6.0)
					_tether(hatch, Vector2(700, 240))
				"eva_sample":
					_rock(Vector2(200, 170), 90)
					_astro(Vector2(340, 190), 1.2)
					draw_circle(Vector2(240, 120), 10, RED)
					_tether(hatch, Vector2(350, 220))
				_:
					var tip := Vector2(330, 160)
					draw_polyline(PackedVector2Array([Vector2(600, 300), Vector2(470, 200), tip]), Color(0.9, 0.9, 0.9), 10.0)
					_astro(Vector2(250, 130), 1.2)
					_route([Vector2(140, 90), Vector2(230, 120)], RED)
					_text(Vector2(130, 60), "DRIFTING!", 26, RED)
		"moon", "flag", "eva_moonwalk":
			_moon_ground()
			if art == "moon":
				_route([Vector2(120, 80), Vector2(420, 120), Vector2(640, 300), Vector2(700, 450)], YELLOW)
				_ship(Vector2(560, 220), 2.6, 1.6, true)
				draw_circle(Vector2(700, 470), 10, GREEN)
				draw_arc(Vector2(700, 470), 30, 0, TAU, 32, GREEN, 3.0)
			else:
				_ship(Vector2(300, 400), 0.0, 1.8)
				_astro(Vector2(560, 400), 1.2)
				_flag(Vector2(680, 470))
				for i in 4:
					draw_circle(Vector2(400 + i * 40, 490 + (i % 2) * 8), 6, Color(0.4, 0.4, 0.42))
		"reentry":
			_earth_arc(500.0, Color(0.2, 0.45, 0.9))
			_ship(Vector2(260, 170), 2.0, 1.6)
			for i in 3:
				draw_arc(Vector2(225, 200), 40 + i * 14, 0.3, 2.4, 16, ORANGE * Color(1, 1, 1, 0.8 - i * 0.2), 6.0)
			for i in 4:
				draw_rect(Rect2(Vector2(430 + i * 110, 230 + i * 50), Vector2(60, 40)), GREEN, false, 3.0)
			draw_rect(Rect2(820, 470, 160, 12), Color(0.6, 0.6, 0.6))
		"splash":
			_ship(Vector2(500, 120), 3.14, 1.0)
			for i in 3:
				draw_arc(Vector2(500, 140), 30 + i * 10, 0.4, 2.7, 12, ORANGE, 4.0)
			for i in 3:
				var c := Vector2(380 + i * 120, 300)
				draw_arc(c, 70, PI, TAU, 24, [RED, Color.WHITE, ORANGE][i], 26.0)
				draw_line(c + Vector2(-66, 0), Vector2(500, 420), LINE, 2.0)
				draw_line(c + Vector2(66, 0), Vector2(500, 420), LINE, 2.0)
			draw_colored_polygon(PackedVector2Array([Vector2(470, 420), Vector2(530, 420), Vector2(550, 470), Vector2(450, 470)]), Color(0.8, 0.8, 0.85))
			for i in 4:
				var pts := PackedVector2Array()
				for k in 41:
					pts.append(Vector2(k * 25, 500 + i * 25 + sin(k * 0.8 + i) * 8))
				draw_polyline(pts, Color(0.2, 0.5 + i * 0.1, 1.0), 4.0)
		"city", "night":
			var night := art == "night"
			draw_rect(Rect2(0, 420, 1000, 180), Color(0.06, 0.08, 0.05) if night else Color(0.18, 0.32, 0.16))
			draw_colored_polygon(PackedVector2Array([Vector2(0, 470), Vector2(1000, 430), Vector2(1000, 470), Vector2(0, 510)]), Color(0.1, 0.25, 0.6))
			var rng2 := RandomNumberGenerator.new()
			rng2.seed = 3
			for i in 26:
				var x := 30.0 + i * 37.0
				var bh := rng2.randf_range(30, 110) if absf(x - 520) < 200 else rng2.randf_range(20, 45)
				draw_rect(Rect2(x, 420 - bh, 28, bh), Color(0.1, 0.1, 0.14) if night else Color(0.55, 0.4, 0.35))
				if night:
					for j in int(bh / 18):
						if rng2.randf() < 0.6:
							draw_rect(Rect2(x + 6 + (j % 2) * 10, 420 - bh + 6 + j * 16, 6, 7), YELLOW)
			if night:
				var hm := Vector2(760, 395)
				draw_colored_polygon(PackedVector2Array([hm + Vector2(-26, 0), hm + Vector2(0, -26), hm + Vector2(26, 0)]), RED)
				draw_rect(Rect2(hm + Vector2(-20, 0), Vector2(40, 26)), YELLOW)
				_orbit(hm + Vector2(0, -150), 170, 50, GREEN)
				_ship(Vector2(600, 230), 1.4, 1.2)
				_text(hm + Vector2(0, 60), "HOME", 24, YELLOW)
			else:
				_route([Vector2(80, 80), Vector2(420, 160), Vector2(560, 300)], YELLOW)
				_ship(Vector2(300, 130), 1.9, 1.3)
				_text(Vector2(780, 110), "FREDERICTON", 32, LINE)
		"free":
			_earth_arc(560.0, Color(0.2, 0.45, 0.9))
			_moon_disc(Vector2(850, 130), 60)
			_station(Vector2(250, 180), 0.8)
			for i in 6:
				_rock(Vector2(520 + i * 30, 300 + (i % 3) * 20), 12)
			_route([Vector2(250, 220), Vector2(560, 300), Vector2(820, 180)], YELLOW)
			_ship(Vector2(420, 260), 1.2, 1.2)
			_text(Vector2(500, 70), "JUMP ANYWHERE", 30, accent)
		"signal":
			_ship(Vector2(200, 330), 1.57, 1.8)
			var src := Vector2(820, 220)
			for i in 4:
				draw_arc(src, 50 + i * 60, 2.3, 4.0, 20, GREEN * Color(1, 1, 1, 1.0 - i * 0.2), 5.0)
			draw_circle(src, 34, Color(0.3, 0.9, 0.5))
			draw_circle(src + Vector2(-12, -6), 8, Color.BLACK)
			draw_circle(src + Vector2(12, -6), 8, Color.BLACK)
			draw_line(src + Vector2(-10, -30), src + Vector2(-20, -60), GREEN, 4.0)
			draw_line(src + Vector2(10, -30), src + Vector2(20, -60), GREEN, 4.0)
			_star_shape(Vector2(380, 500), 34, YELLOW)
			draw_circle(Vector2(500, 500), 30, Color(0.7, 0.8, 1))
			draw_circle(Vector2(514, 490), 26, SPACE)
			_heart(Vector2(620, 500), 30, Color(1, 0.4, 0.6))
			_ship(Vector2(740, 500), 0.0, 0.7)
		"ground":
			draw_rect(Rect2(110, 150, 170, 300), Color(0.12, 0.13, 0.16))
			draw_rect(Rect2(110, 150, 170, 300), LINE, false, 4.0)
			for i in 4:
				draw_rect(Rect2(130, 230 + i * 50, 130, 38), [GREEN, accent, accent, RED][i] * Color(1, 1, 1, 0.8))
			_text(Vector2(195, 200), "MISSION\nCONTROL", 18, YELLOW)
			for i in 3:
				draw_arc(Vector2(330, 300), 40 + i * 35, -0.7, 0.7, 12, GREEN, 5.0)
			_route([Vector2(470, 300), Vector2(700, 230)], YELLOW)
			_ship(Vector2(800, 200), 1.2, 1.6)
			_earth_arc(580.0, Color(0.2, 0.45, 0.9))
		"log":
			draw_rect(Rect2(160, 160, 300, 300), Color(0.35, 0.2, 0.1))
			draw_rect(Rect2(180, 180, 260, 260), Color(0.95, 0.9, 0.75))
			for i in 7:
				draw_line(Vector2(210, 220 + i * 30), Vector2(410, 220 + i * 30), Color(0.5, 0.5, 0.6), 3.0)
			draw_rect(Rect2(640, 180, 70, 150), Color(0.7, 0.72, 0.78))
			draw_circle(Vector2(675, 180), 35, Color(0.7, 0.72, 0.78))
			draw_line(Vector2(675, 330), Vector2(675, 430), LINE, 8.0)
			draw_line(Vector2(620, 430), Vector2(730, 430), LINE, 8.0)
			for i in 3:
				draw_arc(Vector2(675, 230), 80 + i * 35, -0.6, 0.6, 12, RED, 5.0)
			draw_circle(Vector2(840, 140), 16, RED)
			_text(Vector2(840, 200), "REC", 26, RED)
		"bedtime":
			_earth_arc(540.0, Color(0.05, 0.1, 0.25))
			var rng3 := RandomNumberGenerator.new()
			rng3.seed = 11
			for i in 30:
				draw_circle(Vector2(rng3.randf_range(80, 920), rng3.randf_range(470, 560)), 2.5, YELLOW)
			draw_circle(Vector2(780, 160), 80, Color(1, 0.95, 0.75))
			draw_circle(Vector2(815, 135), 72, SPACE)
			_ship(Vector2(330, 280), 1.4, 1.4)
			_text(Vector2(520, 200), "z", 40, LINE)
			_text(Vector2(570, 150), "z", 52, LINE)
			_text(Vector2(630, 95), "Z", 66, LINE)
		_:
			_ship(Vector2(500, 300), 0.0, 2.0)


# ======================================================================== primitives
func _stars(r: Rect2, n: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in n:
		draw_circle(r.position + Vector2(rng.randf(), rng.randf()) * r.size, rng.randf_range(0.8, 2.2), Color(1, 1, 1, rng.randf_range(0.3, 0.9)))


func _text(p: Vector2, t: String, fs: int, c: Color) -> void:
	var f := ThemeDB.fallback_font
	var lines := t.split("\n")
	for i in lines.size():
		var tw := f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, p + Vector2(-tw * 0.5, fs * 0.35 + i * fs * 1.1), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)


func _earth_arc(top: float, col: Color) -> void:
	draw_circle(Vector2(500, top + 1400), 1400, col)
	draw_arc(Vector2(500, top + 1400), 1404, PI * 1.3, PI * 1.7, 64, Color(0.5, 0.8, 1.0, 0.7), 8.0)
	for i in 5:
		draw_circle(Vector2(140 + i * 190, top + 40 + (i % 2) * 25), 45 + (i % 3) * 15, col.lerp(Color(0.25, 0.6, 0.3), 0.6))


func _moon_disc(c: Vector2, r: float) -> void:
	draw_circle(c, r, Color(0.72, 0.72, 0.7))
	for k in [Vector3(-0.3, -0.2, 0.25), Vector3(0.35, 0.1, 0.18), Vector3(0.0, 0.45, 0.15)]:
		draw_circle(c + Vector2(k.x, k.y) * r, k.z * r, Color(0.55, 0.55, 0.53))


func _moon_ground() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(0, 480), Vector2(300, 460), Vector2(700, 475), Vector2(1000, 455), Vector2(1000, 600), Vector2(0, 600)]), Color(0.55, 0.55, 0.53))
	for c in [Vector3(150, 530, 40), Vector3(820, 520, 55), Vector3(480, 560, 30)]:
		draw_circle(Vector2(c.x, c.y), c.z, Color(0.45, 0.45, 0.44))
	draw_circle(Vector2(880, 110), 50, Color(0.2, 0.45, 0.9))


func _ship(p: Vector2, ang: float, s: float, flame := false, col := Color(0.92, 0.94, 0.98)) -> void:
	var pts := PackedVector2Array()
	for v in [Vector2(0, -34), Vector2(9, -20), Vector2(11, 22), Vector2(20, 34), Vector2(-20, 34), Vector2(-11, 22), Vector2(-9, -20)]:
		pts.append(p + (v * s).rotated(ang))
	if flame:
		draw_colored_polygon(PackedVector2Array([p + (Vector2(-8, 36) * s).rotated(ang), p + (Vector2(8, 36) * s).rotated(ang), p + (Vector2(0, 70) * s).rotated(ang)]), ORANGE)
	draw_colored_polygon(pts, col)
	draw_circle(p + (Vector2(0, -16) * s).rotated(ang), 4.5 * s, Color(0.2, 0.6, 1.0))


func _ship_side(p: Vector2, s: float) -> void:
	var pts := PackedVector2Array()
	for v in [Vector2(-120, 0), Vector2(-100, -22), Vector2(-60, -34), Vector2(110, -34), Vector2(120, -20), Vector2(120, 20), Vector2(110, 34), Vector2(-60, 34), Vector2(-100, 22)]:
		pts.append(p + v * s)
	draw_colored_polygon(pts, Color(0.88, 0.9, 0.95))
	draw_rect(Rect2(p + Vector2(-95, -18) * s, Vector2(22, 12) * s), Color(0.2, 0.6, 1.0))
	draw_rect(Rect2(p + Vector2(-10, -36) * s, Vector2(90, 6) * s), Color(0.5, 0.5, 0.55))


func _station(p: Vector2, s: float) -> void:
	draw_line(p + Vector2(-110, 0) * s, p + Vector2(110, 0) * s, Color(0.7, 0.7, 0.75), 6.0 * s)
	for x in [-100.0, -60.0, 60.0, 100.0]:
		draw_rect(Rect2(p + Vector2(x - 14, -55) * s, Vector2(28, 110) * s), Color(0.25, 0.35, 0.7))
	draw_rect(Rect2(p + Vector2(-25, -18) * s, Vector2(50, 36) * s), Color(0.9, 0.9, 0.92))
	draw_rect(Rect2(p + Vector2(25, -8) * s, Vector2(40, 16) * s), Color(0.8, 0.8, 0.85))


func _orbit(c: Vector2, rx: float, ry: float, col: Color) -> void:
	for i in 48:
		if i % 2 == 0:
			var a0 := TAU * i / 48.0
			var a1 := TAU * (i + 1) / 48.0
			draw_line(c + Vector2(cos(a0) * rx, sin(a0) * ry), c + Vector2(cos(a1) * rx, sin(a1) * ry), col * Color(1, 1, 1, 0.7), 3.0)


func _route(pts: Array, col: Color) -> void:
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := int(a.distance_to(b) / 22.0)
		for k in n:
			if k % 2 == 0:
				draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), col, 4.0)
	_arrow(pts[pts.size() - 2], pts[pts.size() - 1], col)


func _arrow(a: Vector2, b: Vector2, col: Color) -> void:
	var d := (b - a).normalized()
	draw_colored_polygon(PackedVector2Array([b, b - d * 18 + d.orthogonal() * 10, b - d * 18 - d.orthogonal() * 10]), col)


func _astro(p: Vector2, s: float) -> void:
	draw_rect(Rect2(p + Vector2(-16, 0) * s, Vector2(32, 40) * s), Color(0.95, 0.95, 0.95))
	draw_line(p + Vector2(-16, 8) * s, p + Vector2(-32, 26) * s, Color(0.95, 0.95, 0.95), 9.0 * s)
	draw_line(p + Vector2(16, 8) * s, p + Vector2(34, -8) * s, Color(0.95, 0.95, 0.95), 9.0 * s)
	draw_line(p + Vector2(-8, 40) * s, p + Vector2(-10, 66) * s, Color(0.95, 0.95, 0.95), 10.0 * s)
	draw_line(p + Vector2(8, 40) * s, p + Vector2(12, 66) * s, Color(0.95, 0.95, 0.95), 10.0 * s)
	draw_circle(p + Vector2(0, -14) * s, 17 * s, Color(0.95, 0.95, 0.95))
	draw_circle(p + Vector2(2, -14) * s, 11 * s, YELLOW.darkened(0.3))


func _tether(a: Vector2, b: Vector2) -> void:
	var pts := PackedVector2Array()
	for i in 21:
		var t := i / 20.0
		pts.append(a.lerp(b, t) + Vector2(0, sin(t * PI) * 40))
	draw_polyline(pts, YELLOW * Color(1, 1, 1, 0.8), 2.5)


func _rock(p: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for i in 9:
		var a := TAU * i / 9.0
		pts.append(p + Vector2(cos(a), sin(a)) * r * (0.8 + 0.25 * sin(i * 2.7 + r)))
	draw_colored_polygon(pts, Color(0.45, 0.4, 0.36))


func _crystal(p: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -24), p + Vector2(14, 0), p + Vector2(0, 24), p + Vector2(-14, 0)]), Color(0.4, 1.0, 0.95))


func _flag(p: Vector2) -> void:
	draw_line(p, p + Vector2(0, -150), Color(0.85, 0.85, 0.85), 5.0)
	draw_rect(Rect2(p + Vector2(0, -150), Vector2(110, 66)), Color.WHITE)
	for i in 3:
		draw_rect(Rect2(p + Vector2(0, -150 + i * 22), Vector2(110, 11)), RED)
	draw_rect(Rect2(p + Vector2(0, -150), Vector2(44, 33)), Color(0.2, 0.3, 0.8))


func _warn(c: Vector2, r: float) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, r * 0.75), c + Vector2(-r, r * 0.75)]), RED)
	_text(c + Vector2(0, 5), "!", int(r), Color.WHITE)


func _star_shape(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + PI * i / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, col)


func _heart(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c + Vector2(-r * 0.45, -r * 0.2), r * 0.5, col)
	draw_circle(c + Vector2(r * 0.45, -r * 0.2), r * 0.5, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.93, 0), c + Vector2(r * 0.93, 0), c + Vector2(0, r)]), col)
