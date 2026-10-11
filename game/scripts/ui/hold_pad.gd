class_name HoldPad
extends TouchControl
## A big touch button that stays "down" while a finger (or the mouse) holds it, e.g. a kid's
## PUSH-TO-TALK pad or the Commander's ALL-CALL. Other fingers keep working (multi-touch).
## lit: optional Callable -> bool (e.g. the intercom says this mic is on air).

signal held(down: bool)

var text := "PTT"
var sub := ""
var color := Color(0.35, 0.85, 1.0)
var lit: Callable
var down := false
var _ptrs := {}
var font_size := 30


func _init() -> void:
	super()
	custom_minimum_size = Vector2(150, 84)


func _pointer_down(idx: int, _pos: Vector2) -> void:
	_ptrs[idx] = true
	_set_down(true)


func _pointer_up(idx: int) -> void:
	_ptrs.erase(idx)
	if _ptrs.is_empty():
		_set_down(false)


func release_all() -> void:
	_ptrs.clear()
	_set_down(false)


func _set_down(d: bool) -> void:
	if d == down:
		return
	down = d
	held.emit(d)
	queue_redraw()


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var on_air := down or (lit.is_valid() and bool(lit.call()))
	var r := Rect2(Vector2.ZERO, size)
	var bg := color * Color(1, 1, 1, 0.9) if on_air else Color(0.05, 0.1, 0.16)
	var sbx := FalconPanel.sb(bg, color if on_air else color * Color(0.7, 0.7, 0.7), 4 if down else 2, 16)
	draw_style_box(sbx, r)
	var f := font()
	var tc := Color(0.02, 0.04, 0.08) if on_air else color
	var fs := font_size
	var y := size.y * 0.5 + fs * 0.35 - (fs * 0.4 if sub != "" else 0.0)
	draw_string(f, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, tc)
	if sub != "":
		draw_string(f, Vector2(0, y + fs * 0.95), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x, int(fs * 0.6), tc)
