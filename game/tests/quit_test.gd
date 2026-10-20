extends Node
## Headless: the game quits cleanly from Alt+F4 (key event), a root close request or an extra
## window's close request. godot --headless --path game -- --quit-test=key|close|window
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GroundLink.get_link()          # a helper that must be shut down
	for i in 5:
		await get_tree().process_frame
	var how := str(Settings.cli.get("quit-test", "key"))
	print("QUIT TEST: ", how)
	match how:
		"close":
			get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
		"window":
			var w := Window.new()
			Game.hook_window(w)
			add_child(w)
			await get_tree().process_frame
			w.close_requested.emit()
		_:
			var k := InputEventKey.new()
			k.keycode = KEY_F4
			k.physical_keycode = KEY_F4
			k.alt_pressed = true
			k.pressed = true
			Input.parse_input_event(k)
	for i in 30:
		await get_tree().process_frame
	print("QUIT TEST: FAIL (still running)")
	get_tree().quit(3)
