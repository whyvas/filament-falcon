extends Mission
## BEDTIME CRUISE: calm drift over the night side of Earth, a lullaby, dimmed cabin, no
## failures, no score pressure. Three gentle taps on the card, then a slow fade to "sweet dreams".

const TWINKLE := [[261.6, 1], [261.6, 1], [392.0, 1], [392.0, 1], [440.0, 1], [440.0, 1], [392.0, 2],
	[349.2, 1], [349.2, 1], [329.6, 1], [329.6, 1], [293.7, 1], [293.7, 1], [261.6, 2]]
const BEAT := 0.62
var music := true
var _song_t := 0.0
var drift_s := 120.0


func setup() -> void:
	id = "bedtime"
	title = "BEDTIME CRUISE"
	tagline = "Calm drift and a lullaby"
	briefing = "Time for a quiet trip before bed. We float slowly around the Earth, watch the city lights and the Moon, and say good night to everybody."
	pilot_job = "Nothing to fly tonight. Just look out of the window."
	ops_job = "Tap the moon when you see it, then wave good night."
	start_callout = "Bedtime cruise. Nice and quiet now."
	requires_checklist = false
	calm = true
	star_thresholds = [0, 0]
	drift_s = {"easy": 60.0, "hard": 180.0}.get(game.difficulty(), 120.0) as float
	objectives = [
		{"text": "Look out of the window: can you see the Moon?", "role": "ALL", "say": "Look out of the window. Can you see the Moon?"},
		{"text": "Wave good night to the Earth", "role": "ALL", "say": "Let's wave good night to the Earth."},
		{"text": "Close your eyes and drift...", "role": "ALL", "say": "Now close your eyes, and float."},
	]
	set_circular_orbit(earth(), 170000.0, deg_to_rad(150.0))
	var up := sim.pos.rel(earth().pos).normalized()
	game.sun_dir = (-up * 0.95 + sim.vel.normalized() * 0.3).normalized()    # night side, sunrise far ahead
	var to_moon := moon().pos.rel(sim.pos).normalized()
	sim.basis = ship_basis(to_moon.slide(up).normalized() if absf(to_moon.dot(up)) < 0.95 else sim.vel, up)
	game.nav_targets = [{"name": "MOON", "body": moon()}, {"name": "EARTH", "body": earth()}]
	game.cabin_dim = 0.75
	set_card("GOOD EVENING", "Look for the Moon!", [["🌙 I SEE THE MOON", "moon", Color(0.7, 0.8, 1.0)]])


func start() -> void:
	super.start()
	game.cabin_dim = 0.75
	_song_t = 3.0


func update(dt: float) -> void:
	if game.warp > 1.0:
		game.set_warp(1.0)
	if music:
		_song_t -= dt
		if _song_t <= 0.0:
			var d := 0.0
			for n: Array in TWINKLE:
				Sfx.tone(float(n[0]), float(n[1]) * BEAT * 0.9, 0.07, "sine", -1.0, d)
				d += float(n[1]) * BEAT
			_song_t = d + 6.0
	if step == 2:
		game.cabin_dim = minf(1.0, game.cabin_dim + dt / drift_s * 0.25)
		if objective_done_after(drift_s, dt, true):
			set_card("SWEET DREAMS 💤", "Good night, crew.")
			advance("Sweet dreams, crew.")


func on_card(cid: String) -> void:
	match cid:
		"moon":
			if step == 0:
				set_card("GOOD NIGHT, EARTH", "Wave to everybody down there!", [["👋 GOOD NIGHT!", "wave", Color(1.0, 0.85, 0.5)]])
				advance("There it is, the Moon. Good night, Moon.")
		"wave":
			if step == 1:
				game.wave(0)
				game.wave(1)
				set_card("SHHH...", "Close your eyes and float...")
				advance("Good night, Earth. Good night, everybody.")


func commander_actions() -> Array:
	return [["MUSIC ON / OFF", "music"], ["DIMMER", "dim"], ["BRIGHTER", "bright"], ["END: SWEET DREAMS", "end"]]


func on_commander(cid: String) -> void:
	match cid:
		"music":
			music = not music
			_song_t = 0.5
		"dim":
			game.cabin_dim = minf(1.0, game.cabin_dim + 0.2)
		"bright":
			game.cabin_dim = maxf(0.0, game.cabin_dim - 0.2)
		"end":
			while step < objectives.size():
				advance()


func final_score() -> void:
	game.add_score("Sweet dreams", 300)
