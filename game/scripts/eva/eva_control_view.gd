class_name EvaControlView
extends CamFeedView
## On-screen spacewalk (no headset): the HELMET CAM (first person) or the EVA DRONE (third
## person) with keyboard / mouse / gamepad control. Click the picture to take the keyboard
## (the cockpit's keyboard shortcuts pause meanwhile), Esc or click again to give it back.
## Keys: W/S forward/back · A/D left/right · R/F up/down · Q/E turn · SPACE grab/let go of a
## rail · ENTER (hold) use / pick up / put down · G wave · K knock on the window · P point ·
## L helmet lamps · X stop drifting · C first person / drone. Mouse: look around.

var captured := false
var hint: Label


func _ready() -> void:
	super._ready()
	kind = "HELMET CAM"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	hint = Label.new()
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 6)
	hint.position = Vector2(12, 44)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		set_captured(not captured)
		accept_event()
	elif ev is InputEventMouseMotion and captured:
		Eva.flat.add_mouse_look((ev as InputEventMouseMotion).relative)
		accept_event()


func _unhandled_key_input(ev: InputEvent) -> void:
	if not captured:
		return
	var k := ev as InputEventKey
	if k and k.pressed and not k.echo:
		if k.keycode == KEY_ESCAPE:
			set_captured(false)
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_C:
			kind = "EVA DRONE" if kind == "HELMET CAM" else "HELMET CAM"


func set_captured(on: bool) -> void:
	captured = on and Eva.active and Eva.driver == "flat"
	Eva.keyboard = captured
	InputHub.keyboard_grab = self if captured else null
	if captured:
		grab_focus()


func _process(dt: float) -> void:
	super._process(dt)
	if captured and (not Eva.active or Eva.driver != "flat" or not is_visible_in_tree()):
		set_captured(false)
	if hint:
		var h := ""
		if not Eva.active:
			h = "Nobody outside. Pick a spacewalk and press START EVA."
		elif Eva.driver == "vr":
			h = "Spacewalker in VR (headset). This is their helmet cam."
		elif not captured:
			h = "CLICK HERE to fly the spacewalker (keyboard + mouse, or a gamepad)"
		else:
			h = "WASD move · R/F up/down · SPACE rail · ENTER use · G wave · K knock · X stop · C view · Esc release"
		if Eva.flat.hint != "" and Eva.active:
			h += "\n" + Eva.flat.hint
		hint.text = h


func _exit_tree() -> void:
	if captured:
		set_captured(false)
