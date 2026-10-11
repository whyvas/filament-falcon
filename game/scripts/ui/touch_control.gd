class_name TouchControl
extends Control
## Base for the on-screen hardware stand-ins (virtual panels, sticks, push-to-talk pads):
## real multi-touch, so both kids can hold their controls at once on the one touchscreen.
## Touch points arrive as InputEventScreenTouch/Drag with their finger index; a real mouse is
## pointer -1. Events Godot synthesises from the other kind (emulated mouse from touch, or
## emulated touch from mouse) carry InputEvent.DEVICE_ID_EMULATION and are ignored, so one
## finger is never counted twice.

const MOUSE := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _gui_input(ev: InputEvent) -> void:
	if ev.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if ev is InputEventScreenTouch:
		var t := ev as InputEventScreenTouch
		if t.pressed:
			_pointer_down(t.index, t.position)
		else:
			_pointer_up(t.index)
		accept_event()
	elif ev is InputEventScreenDrag:
		var d := ev as InputEventScreenDrag
		_pointer_move(d.index, d.position)
		accept_event()
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_pointer_down(MOUSE, mb.position)
		else:
			_pointer_up(MOUSE)
		accept_event()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_pointer_move(MOUSE, mm.position)


func _notification(what: int) -> void:
	# a page switch or hot-plug can hide us mid-touch: release everything
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release_all()


func _pointer_down(_idx: int, _pos: Vector2) -> void:
	pass


func _pointer_move(_idx: int, _pos: Vector2) -> void:
	pass


func _pointer_up(_idx: int) -> void:
	pass


func release_all() -> void:
	pass


func font() -> Font:
	return get_theme_default_font()
