class_name CaptainsLog
extends RefCounted
## Captain's Log entries in ~/.local/share/filament-falcon/captains_log/: <stamp>.json
## ({stamp, date, mission, title, score, stars, patch, wav, secs}) + <stamp>.wav (intercom voices).

const DIR := "user://captains_log"


static func entries() -> Array:
	var out := []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".json"):
			var e: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/" + f))
			if typeof(e) == TYPE_DICTIONARY:
				out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("stamp", "")) > str(b.get("stamp", "")))
	return out


static func new_stamp() -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	return Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")


static func wav_path(stamp: String) -> String:
	return ProjectSettings.globalize_path(DIR + "/" + stamp + ".wav")


static func save(e: Dictionary) -> void:
	var f := FileAccess.open(DIR + "/" + str(e["stamp"]) + ".json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(e, "  "))


static var _player: AudioStreamPlayer


static func play(e: Dictionary) -> bool:
	var p := str(e.get("wav", ""))
	if p == "" or not FileAccess.file_exists(p):
		Voice.say("This log has no recording.", 1)
		return false
	var st := AudioStreamWAV.load_from_file(p)
	if st == null:
		return false
	if _player == null or not is_instance_valid(_player):
		_player = AudioStreamPlayer.new()
		Game.add_child(_player)
	_player.stream = st
	_player.play()
	return true


static func stop() -> void:
	if _player and is_instance_valid(_player):
		_player.stop()
