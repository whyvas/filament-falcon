extends Mission
## CAPTAIN'S LOG: after a mission the crew records a short voice log over the intercom (the ICS
## helper mixes the headset mics into a WAV); it is saved with the last mission's patch + score.
## Playback list: Commander > MISSIONS > CAPTAIN'S LOG.

var stamp := ""
var recording := false
var _rec_t := 0.0
var saved := {}


func setup() -> void:
	id = "captains_log"
	title = "CAPTAIN'S LOG"
	tagline = "Record what we did today"
	briefing = "Every captain keeps a log. Press RECORD and tell the log what we did on our mission today. Then we can listen to it again any time!"
	pilot_job = "Press RECORD, hold your TALK button and say what you did!"
	ops_job = "Say your part too, then press STOP."
	start_callout = "Captain's log. Ready to record."
	requires_checklist = false
	star_thresholds = [500, 800]
	objectives = [
		{"text": "Press the big RECORD button", "role": "BOTH"},
		{"text": "Tell the log about our mission, then press STOP", "role": "BOTH"},
	]
	set_circular_orbit(earth(), 350000.0, deg_to_rad(-30.0))
	sim.basis = ship_basis(sim.vel, sim.pos.rel(earth().pos))
	game.nav_targets = [{"name": "EARTH", "body": earth()}]
	_card_record()


func _card_record() -> void:
	var lr: Dictionary = game.last_result
	var txt := "Last mission: %s, %d points, %s" % [lr.get("title", "none yet"), int(lr.get("score", 0)), "★".repeat(int(lr.get("stars", 0)))] if not lr.is_empty() else "Tell the log about today!"
	set_card("CAPTAIN'S LOG", txt, [["⏺ RECORD", "rec", Color(1, 0.3, 0.3)]])


func update(dt: float) -> void:
	if recording:
		_rec_t += dt
		guidance["flash"] = "● REC %d s" % int(_rec_t)
		if _rec_t > 90.0:
			on_card("stop")


func on_card(cid: String) -> void:
	match cid:
		"rec":
			if step != 0:
				return
			stamp = CaptainsLog.new_stamp()
			recording = Ics.record_start(CaptainsLog.wav_path(stamp))
			_rec_t = 0.0
			set_card("● RECORDING", "Talk now! Press STOP when you are done.", [["■ STOP", "stop", Color(0.9, 0.9, 0.9)]])
			advance("Recording. Go ahead, crew!" if recording else "No intercom, so I can only write it down. Tell the Commander!")
		"stop":
			if step != 1:
				return
			if recording:
				Ics.record_stop()
			_save()
			set_card("LOG SAVED ✓", "Saved! Listen to it on the Commander's MISSIONS page.")
			advance("Log saved.")


func _save() -> void:
	var lr: Dictionary = game.last_result
	saved = {"stamp": stamp, "date": Time.get_datetime_string_from_system(false, true), "mission": lr.get("id", ""),
		"title": lr.get("title", "Free log"), "score": int(lr.get("score", 0)), "stars": int(lr.get("stars", 0)),
		"patch": lr.get("id", "captains_log"), "wav": CaptainsLog.wav_path(stamp) if recording else "", "secs": snappedf(_rec_t, 0.1)}
	recording = false
	guidance.erase("flash")
	if not game.test_mode:
		CaptainsLog.save(saved)


func commander_actions() -> Array:
	return [["⏺ RECORD", "rec"], ["■ STOP + SAVE", "stop"], ["▶ PLAY NEWEST LOG", "play"]]


func on_commander(cid: String) -> void:
	if cid == "play":
		var l := CaptainsLog.entries()
		if not l.is_empty():
			CaptainsLog.play(l[0])
	else:
		on_card(cid)


func cheat_advance() -> void:
	on_card("rec" if step == 0 else "stop")


func final_score() -> void:
	game.add_score("Log recorded", 500)
	game.add_score("Talk time %d s" % int(_rec_t), mini(int(_rec_t) * 10, 300))
