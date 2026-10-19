extends Mission
## ALIEN SIGNAL: the scanner hears beeps from deep space. Copy the pattern (big shape buttons on
## the touchscreen + a few real panel switches / buttons) to decode it; it reveals a hidden
## location, and the crew flies there to meet a friendly alien probe.

const SHAPES := {"STAR": ["★", Color(1, 0.85, 0.2), 880.0], "MOON": ["☾", Color(0.7, 0.8, 1), 660.0],
	"HEART": ["♥", Color(1, 0.4, 0.6), 520.0], "ROCKET": ["🚀", Color(0.4, 1, 0.6), 440.0]}
const PANEL := {"horn": "HORN button", "nav_lights": "NAV LIGHTS switch", "strobe": "STROBE switch",
	"beacon": "BEACON switch", "wave_pilot": "Pilot WAVE", "wave_ops": "Ops WAVE"}
var pattern: Array = []
var got := 0
var probe: Dictionary
var _prev := {}
var _replay := -1.0


func setup() -> void:
	id = "signal"
	title = "ALIEN SIGNAL"
	tagline = "Decode the beeps from space"
	briefing = "Beep boop! Our scanner hears a strange signal from space. Copy the pattern with the big buttons and switches, and it will show us where the signal comes from."
	pilot_job = "Flip the switches the card shows, then fly to the SIGNAL SOURCE."
	ops_job = "SCANNER PING to listen, then press the shapes in the same order."
	start_callout = "Listening to deep space..."
	requires_checklist = false
	star_thresholds = [900, 1300]
	objectives = [
		{"text": "SCANNER PING to listen for the signal", "role": "OPS"},
		{"text": "Copy the pattern on the card!", "role": "BOTH"},
		{"text": "Fly to the SIGNAL SOURCE (NAV TARGET)", "role": "PILOT"},
	]
	set_circular_orbit(earth(), 160000.0, deg_to_rad(200.0))
	sim.basis = ship_basis(sim.vel, sim.pos.rel(earth().pos))
	var p: BigVec = sim.pos.copy()
	p.add(sim.vel.normalized() * 2500.0 + sim.basis.y * 300.0)
	probe = game.add_entity("satellite", {"mode": "free", "name": "SIGNAL SOURCE", "radius": 6.0, "revealed": false})
	probe["pos"] = p
	probe["vel"] = sim.vel
	probe["ang_vel"] = Vector3(0.0, 0.3, 0.1)
	game.nav_targets = [{"name": "SIGNAL SOURCE", "entity": probe}, {"name": "EARTH", "body": earth()}]
	_new_pattern()
	set_card("LISTENING...", "Ops: press SCANNER PING to hear the signal!")


func _new_pattern() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var n := {"easy": 3, "hard": 5}.get(game.difficulty(), 4) as int
	var panel_n := {"easy": 0, "hard": 2}.get(game.difficulty(), 1) as int
	pattern.clear()
	for i in n:
		pattern.append(SHAPES.keys()[rng.randi() % SHAPES.size()])
	for i in panel_n:
		pattern[rng.randi_range(1, n - 1)] = PANEL.keys()[rng.randi() % PANEL.size()]
	got = 0


func _tok_text(t: String) -> String:
	return str(SHAPES[t][0]) if SHAPES.has(t) else "[" + str(PANEL[t]) + "]"


func _show() -> void:
	var s := ""
	for i in pattern.size():
		s += ("✓" if i < got else _tok_text(pattern[i])) + "   "
	var b := []
	for k: String in SHAPES:
		b.append([str(SHAPES[k][0]) + " " + k, k, SHAPES[k][1]])
	set_card("COPY THE SIGNAL", s + "\n(▶ HEAR IT AGAIN to listen once more)", b + [["▶ HEAR IT AGAIN", "replay", Color(0.6, 0.7, 0.8)]])


func _play_pattern() -> void:
	for i in pattern.size():
		var t: String = pattern[i]
		Sfx.tone(float(SHAPES[t][2]) if SHAPES.has(t) else 300.0, 0.25, 0.3, "sine", -1.0, i * 0.45)


func _input_tok(t: String) -> void:
	if step != 1:
		return
	if t == pattern[got]:
		got += 1
		Sfx.tone(float(SHAPES[t][2]) if SHAPES.has(t) else 300.0, 0.18, 0.3)
		if got >= pattern.size():
			probe["revealed"] = true
			game.set_nav_target_by_name("SIGNAL SOURCE")
			set_card("DECODED! 👽", "The signal says: HELLO FRIENDS! Fly to the SIGNAL SOURCE.")
			advance("Decoded! It says hello! The signal comes from right ahead. Pilot, fly there!")
		else:
			_show()
	else:
		got = 0
		Sfx.tone(200.0, 0.3, 0.25, "square")
		Voice.say("Beep boop, try again from the start!", 1)
		_show()


func update(_dt: float) -> void:
	for k: String in PANEL:
		var v := InputHub.on(k)
		if _prev.has(k) and v != _prev[k] and (v or k in ["nav_lights", "strobe", "beacon"]):
			_input_tok(k)
		_prev[k] = v
	if step == 2 and rel_to_entity(probe).length() < 300.0:
		set_card("HELLO, ALIEN! 👽", "A friendly little probe! It blinks hello at us.")
		advance("We found the friendly alien probe! Hello!")


func on_scanner_ping() -> void:
	if step == 0:
		_play_pattern()
		_show()
		advance("Signal heard! Copy the pattern!")
	elif step == 1:
		_play_pattern()


func on_card(cid: String) -> void:
	if cid == "replay":
		_play_pattern()
	elif SHAPES.has(cid):
		_input_tok(cid)


func commander_actions() -> Array:
	return [["NEW PATTERN", "new"], ["SAY THE PATTERN", "say"], ["JUMP TO THE PROBE", "jump"]]


func on_commander(cid: String) -> void:
	match cid:
		"new":
			_new_pattern()
			if step == 1:
				_show()
		"say":
			var s := []
			for t: String in pattern:
				s.append(t.to_lower() if SHAPES.has(t) else str(PANEL[t]))
			Voice.say("The pattern is: " + ", ".join(s), 1)
		"jump":
			var p: BigVec = (probe["pos"] as BigVec).copy()
			p.add(-sim.vel.normalized() * 400.0)
			sim.pos.set_from(p)
			sim.vel = probe["vel"]


func cheat_advance() -> void:
	match step:
		0:
			on_scanner_ping()
		1:
			for t: String in pattern.slice(got):
				_input_tok(t)
		_:
			advance()
