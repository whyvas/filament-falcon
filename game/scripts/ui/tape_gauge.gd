class_name TapeGauge
extends Control
## Vertical tape instrument (speed or altitude). The scale adapts to the value (1-2-5 steps),
## so one tape works from the launch pad to the Moon. `getter` returns [value, text, color].

var title := ""
var unit := ""
var getter: Callable
var min_major := 10.0
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	clip_contents = true
	custom_minimum_size = Vector2(150, 300)


func _process(_dt: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


static func nice_step(x: float) -> float:
	var e := pow(10.0, floorf(log(maxf(x, 1e-6)) / log(10.0)))
	var f := x / e
	return e * (1.0 if f < 1.5 else (2.0 if f < 3.5 else (5.0 if f < 7.5 else 10.0)))


func _draw() -> void:
	if not getter.is_valid():
		return
	var r: Array = getter.call()
	var v := float(r[0])
	var col: Color = r[2]
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.05, 0.1))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.75, 1.0, 0.6), false, 2.0)
	var top := 40.0
	var h := size.y - top - 8.0
	var mid := top + h * 0.5
	var major := nice_step(maxf(absf(v) * 0.25, min_major))
	var px := h / (major * 5.0)
	var first := floorf((v - major * 3.0) / major) * major
	var x := first
	while x <= v + major * 3.0:
		var y := mid - (x - v) * px
		if y > top and y < size.y - 4.0:
			draw_line(Vector2(size.x - 26, y), Vector2(size.x - 4, y), Color.WHITE, 2.0)
			draw_string(font, Vector2(8, y + 8), Hud._fmt_dist(x) if unit == "m" else "%d" % int(x), HORIZONTAL_ALIGNMENT_LEFT, size.x - 40, 20, Color(0.8, 0.9, 1.0))
			var ym := y - major * 0.5 * px
			if ym > top:
				draw_line(Vector2(size.x - 14, ym), Vector2(size.x - 4, ym), Color(1, 1, 1, 0.6), 2.0)
		x += major
	# value box
	var bh := 46.0
	draw_rect(Rect2(2, mid - bh * 0.5, size.x - 4, bh), Color(0, 0, 0, 0.92))
	draw_rect(Rect2(2, mid - bh * 0.5, size.x - 4, bh), col, false, 3.0)
	draw_string(font, Vector2(4, mid + 11), str(r[1]), HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 30, col)
	draw_rect(Rect2(0, 0, size.x, top - 4), Color(0.04, 0.09, 0.15))
	draw_string(font, Vector2(0, 28), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(0.2, 0.75, 1.0))
