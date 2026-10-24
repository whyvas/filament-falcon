class_name AreaMap
extends Control
## World map for the Commander AREAS page (equirectangular, the game's Earth day texture).
## Mouse wheel = zoom at the cursor, right / middle drag = pan, left drag = draw the area box,
## left click = centre the box there. Cached areas are drawn in their state colour.

signal box_drawn(bbox: Array)          # [S, W, N, E]

var center := Vector2(-66.6, 45.9)     # lon, lat
var deg_per_px := 0.25
var sel: Array = []                    # [S, W, N, E]
var areas: Array = []                  # [{bbox, state, name}]
var _drag := -1                        # mouse button being dragged
var _a := Vector2.ZERO
var _b := Vector2.ZERO
var _tex: Texture2D
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func to_screen(lon: float, lat: float) -> Vector2:
	return size * 0.5 + Vector2(lon - center.x, center.y - lat) / deg_per_px


func to_geo(p: Vector2) -> Vector2:
	var d := (p - size * 0.5) * deg_per_px
	return Vector2(center.x + d.x, center.y - d.y)


## Zoom the view onto a box (with a margin).
func frame(bb: Array) -> void:
	center = Vector2((float(bb[1]) + float(bb[3])) * 0.5, (float(bb[0]) + float(bb[2])) * 0.5)
	var span := maxf(float(bb[3]) - float(bb[1]), float(bb[2]) - float(bb[0])) * 4.0
	deg_per_px = clampf(span / maxf(minf(size.x, size.y), 100.0), 0.0005, 0.4)
	queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var g := to_geo(mb.position)
			deg_per_px = clampf(deg_per_px * (0.8 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.25), 0.0005, 0.4)
			center += g - to_geo(mb.position)       # keep the point under the cursor
			accept_event()
		elif mb.pressed and _drag < 0 and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_drag = mb.button_index
			_a = mb.position
			_b = mb.position
			accept_event()
		elif not mb.pressed and mb.button_index == _drag:
			if _drag == MOUSE_BUTTON_LEFT:
				var g0 := to_geo(_a)
				var g1 := to_geo(_b)
				if _a.distance_to(_b) > 6.0:
					sel = [minf(g0.y, g1.y), minf(g0.x, g1.x), maxf(g0.y, g1.y), maxf(g0.x, g1.x)]
				else:          # click: a 10 x 10 km box there
					var dlat := 5.0 / 110.54
					var dlon := 5.0 / (111.32 * maxf(cos(deg_to_rad(g0.y)), 0.05))
					sel = [g0.y - dlat, g0.x - dlon, g0.y + dlat, g0.x + dlon]
				box_drawn.emit(sel)
			_drag = -1
			accept_event()
		queue_redraw()
	elif ev is InputEventMouseMotion and _drag >= 0:
		var mm := ev as InputEventMouseMotion
		if _drag == MOUSE_BUTTON_LEFT:
			_b = mm.position
		else:
			center -= mm.relative * deg_per_px * Vector2(1, -1)
			center.y = clampf(center.y, -85.0, 85.0)
		queue_redraw()
		accept_event()


func _box(bb: Array, c: Color, w: float, fill: float, text: String) -> void:
	var p0 := to_screen(float(bb[1]), float(bb[2]))
	var p1 := to_screen(float(bb[3]), float(bb[0]))
	var r := Rect2(p0, p1 - p0)
	if r.size.x < 4.0:            # tiny at this zoom: a marker instead
		r = Rect2(r.get_center() - Vector2(4, 4), Vector2(8, 8))
	draw_rect(r, Color(c, fill))
	draw_rect(r, c, false, w)
	if text != "":
		draw_string(font, r.position + Vector2(2, -4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.05, 0.1))
	if _tex == null:
		var w := get_tree().get_first_node_in_group("world")
		if w and w.get("earth_mat") is ShaderMaterial:
			var t: Variant = (w.get("earth_mat") as ShaderMaterial).get_shader_parameter("day_tex")
			if t is Texture2D:
				_tex = t
	if _tex:
		var tw := float(_tex.get_width())
		var th := float(_tex.get_height())
		var g0 := to_geo(Vector2.ZERO)
		var g1 := to_geo(size)
		var lat0 := clampf(g0.y, -90.0, 90.0)
		var lat1 := clampf(g1.y, -90.0, 90.0)
		var lon0 := clampf(g0.x, -180.0, 180.0)
		var lon1 := clampf(g1.x, -180.0, 180.0)
		if lon1 > lon0 and lat0 > lat1:
			var src := Rect2((lon0 + 180.0) / 360.0 * tw, (90.0 - lat0) / 180.0 * th,
				(lon1 - lon0) / 360.0 * tw, (lat0 - lat1) / 180.0 * th)
			var a := to_screen(lon0, lat0)
			var b := to_screen(lon1, lat1)
			draw_texture_rect_region(_tex, Rect2(a, b - a), src)
	# graticule (labels in degrees)
	var step := 10.0
	for s: float in [10.0, 5.0, 1.0, 0.5, 0.1, 0.05, 0.01]:
		if s / deg_per_px > 60.0:
			step = s
	var g0b := to_geo(Vector2.ZERO)
	var g1b := to_geo(size)
	var lo := floorf(g0b.x / step) * step
	while lo < g1b.x:
		var x := to_screen(lo, 0.0).x
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.5, 0.8, 1.0, 0.18))
		draw_string(font, Vector2(x + 2, size.y - 4), "%.2f" % lo, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.85, 1.0, 0.6))
		lo += step
	var la := floorf(g1b.y / step) * step
	while la < g0b.y:
		var y := to_screen(0.0, la).y
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.5, 0.8, 1.0, 0.18))
		draw_string(font, Vector2(2, y - 2), "%.2f" % la, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.85, 1.0, 0.6))
		la += step
	for a: Dictionary in areas:
		var st := str(a.get("state", ""))
		var c := FalconPanel.C_GREEN if st == "done" else (FalconPanel.C_AMBER if st in ["running", "queued"] else (FalconPanel.C_RED if st == "error" else FalconPanel.C_DIM))
		_box(a["bbox"], c, 1.5, 0.12, str(a.get("name", "")))
	if not sel.is_empty():
		_box(sel, FalconPanel.C_EDGE, 2.5, 0.08, "")
	if _drag == MOUSE_BUTTON_LEFT:
		draw_rect(Rect2(_a, _b - _a).abs(), FalconPanel.C_EDGE, false, 2.0)
	draw_string(font, Vector2(8, 18), "wheel zoom · right-drag pan · left-drag draw a box · click = 10 km box",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.9, 1.0, 0.8))
