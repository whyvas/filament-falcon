extends Node
## Voice callouts. Uses piper (if installed and a model is configured) or espeak-ng for
## real speech; always shows the text on screen and plays a short attention tone.

signal callout(text: String, priority: int)

var engine := "none"
var _queue: Array[String] = []
var _busy_until := 0.0
var _pid := -1
var history: Array[String] = []


func _ready() -> void:
	if not bool(Settings.get_v("audio", "voice")) or Settings.is_headless():
		engine = "none"
		return
	var pref: String = str(Settings.get_v("audio", "voice_engine"))
	var model: String = str(Settings.get_v("audio", "piper_model"))
	if (pref == "auto" or pref == "piper") and model != "" and _has_cmd("piper") and _has_cmd("aplay"):
		engine = "piper"
	elif (pref == "auto" or pref == "espeak") and _has_cmd("espeak-ng"):
		engine = "espeak-ng"
	elif (pref == "auto" or pref == "espeak") and _has_cmd("espeak"):
		engine = "espeak"
	print("[Voice] engine: ", engine)


func _has_cmd(cmd: String) -> bool:
	var out := []
	var code := OS.execute("sh", ["-c", "command -v " + cmd], out)
	return code == 0


## priority: 0 info, 1 important, 2 warning
func say(text: String, priority: int = 0) -> void:
	callout.emit(text, priority)
	history.append(text)
	if history.size() > 40:
		history.pop_front()
	if priority >= 2:
		Sfx.caution_chime()
	else:
		Sfx.tone(1046.0, 0.08, 0.12)
	if engine == "none":
		return
	if priority >= 2:
		_queue.clear()
		_queue.push_front(text)
	elif _queue.size() < 4:
		_queue.append(text)


func _process(_dt: float) -> void:
	if engine == "none" or _queue.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _busy_until:
		return
	var text: String = _queue.pop_front()
	_busy_until = now + 0.6 + text.length() * 0.065
	# With the intercom running, callouts go to its MISSION CONTROL channel (falcon_mc sink):
	# radio effect, heard in all three headsets (and the room speakers if enabled).
	var sink := Ics.mc_sink()
	var env := ("PULSE_SINK=%s " % sink) if sink != "" else ""
	match engine:
		"piper":
			var model: String = str(Settings.get_v("audio", "piper_model"))
			_pid = OS.create_process("sh", ["-c", "echo \"$1\" | piper --model \"$2\" --output-raw 2>/dev/null | %saplay -q -r 22050 -f S16_LE -t raw - 2>/dev/null" % env, "falcon", text, model])
		"espeak-ng", "espeak":
			_pid = OS.create_process("sh", ["-c", "%sexec \"$1\" -v en-us+f3 -s 158 -p 45 \"$2\"" % env, "falcon", engine, text])
