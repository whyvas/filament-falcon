class_name VirtualStick
extends TouchControl
## On-screen joystick for a seat whose board (and so its stick) is unplugged: drag in the
## big circle for the two main axes (springs back to centre on release), drag the bar
## underneath for the twist axis, hold TRIGGER. The Pilot also gets the throttle on the
## virtual side panel; keyboard keys keep working alongside.
##   Pilot: circle = roll (x) + pitch (y, pull down = nose up), bar = yaw
##   Ops:   circle = RCS left/right + down/up, bar = forward/back

var seat := "pilot"
var color := Color(0.35, 0.85, 1.0)
var _ptr := {}            # index -> "pad" | "twist" | "trig"
var _pad := Vector2.ZERO
var _twist := 0.0
var _trig := false


func _init() -> void:
	super()
	custom_minimum_size = Vector2(300, 260)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func axes() -> Array:
	return ["roll", "pitch", "yaw", "pilot_trigger"] if seat == "pilot" else ["tx", "ty", "tz", "ops_trigger"]


func _geom() -> Dictionary:
	var tw := minf(size.x * 0.26, 170.0)
	var area := Rect2(Vector2.ZERO, Vector2(size.x - tw - 12.0, size.y - 74.0))
	var r := minf(area.size.x, area.size.y) * 0.5 - 6.0
	var c := area.get_center()
	var twist := Rect2(Vector2(c.x - r, size.y - 64.0), Vector2(r * 2.0, 58.0))
	var trig := Rect2(Vector2(size.x - tw, size.y * 0.2), Vector2(tw, size.y * 0.6))
	return {"c": c, "r": r, "twist": twist, "trig": trig}


func _pointer_down(idx: int, pos: Vector2) -> void:
	var g := _geom()
	if (g["trig"] as Rect2).grow(10).has_point(pos):
		_ptr[idx] = "trig"
		_trig = true
		InputHub.set_switch(axes()[3], true)
	elif (g["twist"] as Rect2).grow(14).has_point(pos):
		_ptr[idx] = "twist"
		_pointer_move(idx, pos)
	elif pos.distance_to(g["c"]) <= float(g["r"]) * 1.15:
		_ptr[idx] = "pad"
		_pointer_move(idx, pos)


func _pointer_move(idx: int, pos: Vector2) -> void:
	var g := _geom()
	match str(_ptr.get(idx, "")):
		"pad":
			var v := (pos - (g["c"] as Vector2)) / (float(g["r"]) * 0.8)
			_pad = v.limit_length(1.0)
		"twist":
			var tr: Rect2 = g["twist"]
			_twist = clampf((pos.x - tr.get_center().x) / (tr.size.x * 0.45), -1.0, 1.0)
	_apply()


func _pointer_up(idx: int) -> void:
	match str(_ptr.get(idx, "")):
		"pad":
			_pad = Vector2.ZERO
		"twist":
			_twist = 0.0
		"trig":
			_trig = false
			InputHub.set_switch(axes()[3], false)
	_ptr.erase(idx)
	_apply()


func release_all() -> void:
	_ptr.clear()
	_pad = Vector2.ZERO
	_twist = 0.0
	_trig = false
	if InputHub.actions.has(axes()[3]):
		InputHub.set_switch(axes()[3], false)
	_apply()


func _apply() -> void:
	var a := axes()
	if seat == "pilot":
		InputHub.set_axis_override(a[0], _pad.x)
		InputHub.set_axis_override(a[1], _pad.y)      # pull towards you (down) = nose up
	else:
		InputHub.set_axis_override(a[0], _pad.x)
		InputHub.set_axis_override(a[1], -_pad.y)     # up the screen = RCS up
	InputHub.set_axis_override(a[2], _twist)
	queue_redraw()


func _process(_dt: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var g := _geom()
	var c: Vector2 = g["c"]
	var r: float = g["r"]
	var f := font()
	draw_circle(c, r, Color(0.03, 0.06, 0.1))
	draw_arc(c, r, 0, TAU, 64, color * Color(1, 1, 1, 0.7), 3.0)
	draw_arc(c, r * 0.5, 0, TAU, 48, color * Color(1, 1, 1, 0.25), 1.5)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), color * Color(1, 1, 1, 0.2), 1.5)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), color * Color(1, 1, 1, 0.2), 1.5)
	var a := axes()
	# show the actual axis values (keyboard or hardware moves the knob too)
	var v := Vector2(InputHub.axis(a[0]), InputHub.axis(a[1]) * (1.0 if seat == "pilot" else -1.0))
	var kp := c + v * r * 0.8
	draw_circle(kp, r * 0.22, color * Color(1, 1, 1, 0.9) if _ptr.values().has("pad") else color * Color(1, 1, 1, 0.55))
	draw_circle(kp, r * 0.12, Color(0.05, 0.08, 0.12))
	var fs := 18
	if seat == "pilot":
		draw_string(f, c + Vector2(-r, -r + 8), "PUSH = NOSE DOWN", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(0.7, 0.8, 0.9))
		draw_string(f, c + Vector2(-r, r + 2), "PULL = NOSE UP", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(0.7, 0.8, 0.9))
	else:
		draw_string(f, c + Vector2(-r, -r + 8), "RCS UP", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(0.7, 0.8, 0.9))
		draw_string(f, c + Vector2(-r, r + 2), "RCS DOWN", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(0.7, 0.8, 0.9))
	var tr: Rect2 = g["twist"]
	draw_style_box(FalconPanel.sb(Color(0.03, 0.06, 0.1), color * Color(1, 1, 1, 0.6), 2, 12), tr)
	var tx := tr.get_center().x + InputHub.axis(a[2]) * tr.size.x * 0.45
	draw_rect(Rect2(Vector2(tx - 16, tr.position.y + 6), Vector2(32, tr.size.y - 12)), color * Color(1, 1, 1, 0.85))
	draw_string(f, Vector2(tr.position.x, tr.position.y + tr.size.y * 0.5 + 7), "  ◀ " + ("YAW" if seat == "pilot" else "BACK"), HORIZONTAL_ALIGNMENT_LEFT, tr.size.x, fs, Color(0.75, 0.85, 0.95))
	draw_string(f, Vector2(tr.position.x, tr.position.y + tr.size.y * 0.5 + 7), ("YAW" if seat == "pilot" else "FWD") + " ▶  ", HORIZONTAL_ALIGNMENT_RIGHT, tr.size.x, fs, Color(0.75, 0.85, 0.95))
	var tg: Rect2 = g["trig"]
	var on := InputHub.on(a[3])
	draw_style_box(FalconPanel.sb(Color(0.75, 0.12, 0.1) if on else Color(0.18, 0.05, 0.05), Color(1, 0.4, 0.3), 3 if on else 2, 18), tg)
	draw_string(f, Vector2(tg.position.x, tg.get_center().y + 9), "TRIGGER", HORIZONTAL_ALIGNMENT_CENTER, tg.size.x, 24, Color.WHITE)
