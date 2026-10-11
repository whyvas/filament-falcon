class_name LevelMeter
extends Control
## Live microphone level for one intercom seat: -60..0 dBFS bar, the VOX threshold as a
## white tick, green while the mic is on air. getter: Callable -> [level_db, open, threshold_db].

var getter: Callable
var _lvl := -90.0
var _open := false
var _thr := -38.0


func _init() -> void:
	custom_minimum_size = Vector2(160, 26)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_dt: float) -> void:
	if getter.is_valid():
		var r: Array = getter.call()
		_lvl = float(r[0])
		_open = bool(r[1])
		_thr = float(r[2])
	queue_redraw()


static func frac(db: float) -> float:
	return clampf((db + 60.0) / 60.0, 0.0, 1.0)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.02, 0.04, 0.07))
	var w := size.x * frac(_lvl)
	var c := FalconPanel.C_GREEN if _open else Color(0.25, 0.55, 0.75)
	draw_rect(Rect2(0, 2, w, size.y - 4), c)
	for db in [-48, -36, -24, -12]:
		var x := size.x * frac(float(db))
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.12))
	if _thr > -60.0:
		var tx := size.x * frac(_thr)
		draw_line(Vector2(tx, -3), Vector2(tx, size.y + 3), Color.WHITE, 3.0)
	draw_rect(r, FalconPanel.C_EDGE * Color(1, 1, 1, 0.5), false, 2.0)
