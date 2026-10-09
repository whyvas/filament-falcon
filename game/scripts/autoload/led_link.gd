extends Node
## Sends backlight state to the Falcon Command board. Godot has no serial port API, so the
## game talks to tools/falcon_led_bridge.py over localhost UDP; the bridge owns the USB CDC
## serial port. The bridge is started automatically if python3 is available and quietly
## ignored if anything is missing. Protocol (shared/led_protocol.md):
##   SEG <LABEL_ID> <r> <g> <b> [SOLID|BLINK|FAST|PULSE|OFF]   ALL ...   CLEAR   BRIGHT <n>
## Label ids come from shared/led_segments.json; config/led_labels.json maps game signals to them.

var enabled := false
var port := 47800
var udp := PacketPeerUDP.new()
var bridge_pid := -1
var status := "disabled"
var label_map := {}          # game signal -> panel label id
var unknown_labels: Array[String] = []
var _sent := {}              # label -> "r g b MODE"
var _desired := {}
var _timer := 0.0
var _full_timer := 0.0
var _brightness := -1
var lines_sent := 0


func _ready() -> void:
	_load_label_map()
	enabled = bool(Settings.get_v("led", "enabled"))
	port = int(Settings.get_v("led", "udp_port"))
	if not enabled:
		return
	udp.set_dest_address("127.0.0.1", port)
	_start_bridge()


func _load_label_map() -> void:
	var path := "res://config/led_labels.json"
	if FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(d) == TYPE_DICTIONARY:
			label_map = d.get("labels", {})
	# Cross-check against the firmware segment map if it exists.
	var shared := Settings.shared_file("led_segments.json")
	if FileAccess.file_exists(shared):
		var seg: Variant = JSON.parse_string(FileAccess.get_file_as_string(shared))
		if typeof(seg) == TYPE_DICTIONARY and typeof(seg.get("segments")) == TYPE_DICTIONARY:
			var known: Dictionary = seg["segments"]
			for sig in label_map:
				for lab in _labels_for(sig):
					if not known.has(lab):
						unknown_labels.append(lab)


func _labels_for(sig: String) -> Array:
	var v: Variant = label_map.get(sig, sig)
	if typeof(v) == TYPE_ARRAY:
		return v
	return [str(v)]


func _start_bridge() -> void:
	var script := ProjectSettings.globalize_path("res://tools/falcon_led_bridge.py")
	if not FileAccess.file_exists(script):
		status = "bridge script missing"
		return
	var py := ""
	for cand in ["python3", "python"]:
		if OS.execute("sh", ["-c", "command -v " + cand]) == 0:
			py = cand
			break
	if py == "":
		status = "python3 not found (LEDs off)"
		return
	var serial_port: String = str(Settings.get_v("led", "serial_port"))
	bridge_pid = OS.create_process(py, [script, "--udp-port", str(port), "--serial", serial_port, "--parent-pid", str(OS.get_process_id())])
	status = "bridge started (pid %d)" % bridge_pid if bridge_pid > 0 else "bridge failed to start"


func _exit_tree() -> void:
	if bridge_pid > 0:
		_send_raw("IDLE")
		OS.kill(bridge_pid)


func _send_raw(line: String) -> void:
	if not enabled:
		return
	udp.put_packet((line + "\n").to_utf8_buffer())
	lines_sent += 1


## Set a game signal's light. mode: SOLID | BLINK | PULSE. Color.BLACK = off.
func set_signal(sig: String, c: Color, mode: String = "SOLID") -> void:
	if not label_map.has(sig):
		return
	c = c.clamp()
	var v := "%d %d %d %s" % [c.r8, c.g8, c.b8, mode]
	for label in _labels_for(sig):
		_desired[label] = v


func set_all_signals(c: Color, mode: String = "SOLID") -> void:
	for sig in label_map:
		set_signal(sig, c, mode)


func clear_all() -> void:
	_desired.clear()


func _process(dt: float) -> void:
	if not enabled:
		return
	_timer += dt
	_full_timer += dt
	if _timer < 0.1:
		return
	_timer = 0.0
	var b := int(Settings.get_v("led", "brightness") * clampf(InputHub.axis("dimmer") * 1.4, 0.05, 1.0))
	if b != _brightness or _full_timer > 5.0:
		_brightness = b
		_send_raw("BRIGHT %d" % clampi(b, 0, 255))
	var full := _full_timer > 5.0
	if full:
		_full_timer = 0.0
	var batch := 0
	for label in _desired:
		var v: String = _desired[label]
		if full or _sent.get(label, "") != v:
			_send_raw("SEG %s %s" % [label, v])
			_sent[label] = v
			batch += 1
			if batch > 40 and not full:
				break
	_send_raw("#HEARTBEAT")
