class_name Mission
extends RefCounted
## Base class for missions. A mission sets up the ship and world, then walks through a list
## of objectives. Each objective names who does it (PILOT, OPS, BOTH, CMDR) so both kids get
## hero moments. cheat_advance() satisfies the current objective (used by the smoke tests).

var game: Node
var id := ""
var title := ""
var tagline := ""
var briefing := ""
var pilot_job := ""
var ops_job := ""
var commander_tip := "Press START when the crew is strapped in and the checklist is done. Try a failure button mid-mission for extra excitement!"
var start_callout := "Mission start!"
var requires_checklist := true
var laser_enabled := false
var star_thresholds := [900, 1400]
var objectives: Array = []      # [{text, role}]
var step := 0
var guidance := {}              # hints for the HUD (pitch targets, glide boxes, ...)
var _done_timer := -1.0
var eva_inserted := false       # a SPACEWALK objective was woven in (Eva.mission_hook)
var eva_done := false
var eva_obj := {}               # non-empty while that spacewalk is the current objective: the
                                # mission's own update / physics pause, step indices stay put


func setup() -> void:
	pass


func start() -> void:
	_announce_objective()


func update(_dt: float) -> void:
	pass


func physics(_h: float) -> void:
	pass


func current_objective() -> Dictionary:
	if not eva_obj.is_empty():
		return eva_obj
	if step < objectives.size():
		return objectives[step]
	return {"text": "Mission complete!", "role": "ALL"}


func advance(say: String = "") -> void:
	if not eva_obj.is_empty():
		eva_obj = {}            # the woven-in spacewalk is done: resume the mission where it was
	elif step >= objectives.size():
		return
	else:
		step += 1
	if say != "":
		Voice.say(say, 1)
	Sfx.chime()
	game._update_objective_text()
	game.objective_changed.emit()
	if Eva.mission_hook(self):
		_announce_objective()
		return
	if step >= objectives.size():
		game.complete_mission()
	else:
		_announce_objective()


func _announce_objective() -> void:
	var o := current_objective()
	if o.has("say"):
		Voice.say(o["say"])
	else:
		Voice.say(str(o.get("role", "")).capitalize() + ": " + str(o.get("text", "")))


## Satisfy the current objective (tests / commander override).
func cheat_advance() -> void:
	advance()


func final_score() -> void:
	game.add_score("Mission complete", 600)
	var t: float = game.mission_time
	game.add_score("Time %d:%02d" % [int(t) / 60, int(t) % 60], clampi(400 - int(t / 2.0), 0, 400))


func guidance_dir() -> Vector3:
	return Vector3.ZERO


func on_ops_trigger() -> void:
	pass


func on_arm_trigger() -> void:
	pass


func on_scanner_ping() -> void:
	pass


func on_dock_clamp() -> void:
	pass


func can_jump() -> bool:
	Voice.say("No jump destination for this mission.")
	return false


func on_jump_complete() -> void:
	pass


# ------------------------------------------------------------------ helpers
var sim: ShipSim:
	get:
		return game.sim


func earth() -> CelestialBody:
	return game.earth


func moon() -> CelestialBody:
	return game.moon


## Ship basis whose forward (-Z) points along `fwd` and roof (+Y) toward `up`.
static func ship_basis(fwd: Vector3, up: Vector3) -> Basis:
	return Basis.looking_at(fwd.normalized(), up.normalized())


## Put the ship on a circular orbit around `body` at `alt`, at angle `phase` in the equatorial plane.
func set_circular_orbit(body: CelestialBody, alt: float, phase: float) -> void:
	var r := body.radius + alt
	var n := sqrt(body.gm / pow(r, 3.0))
	sim.pos.set_xyz(body.pos.x() + r * cos(phase), body.pos.y(), body.pos.z() - r * sin(phase))
	sim.vel = body.vel + Vector3(-sin(phase), 0.0, -cos(phase)) * (n * r)


func orbit_elements() -> Dictionary:
	var b: CelestialBody = sim.dominant
	return OrbitMath.elements(sim.pos.rel(b.pos), sim.vel - b.vel, b.gm, b.radius)


func rel_to_entity(e: Dictionary) -> Vector3:
	return (e["pos"] as BigVec).rel(sim.pos)


func rel_vel_entity(e: Dictionary) -> Vector3:
	return sim.vel - (e["vel"] as Vector3)


func objective_done_after(seconds: float, dt: float, cond: bool) -> bool:
	if not cond:
		_done_timer = -1.0
		return false
	if _done_timer < 0.0:
		_done_timer = 0.0
	_done_timer += dt
	return _done_timer >= seconds
