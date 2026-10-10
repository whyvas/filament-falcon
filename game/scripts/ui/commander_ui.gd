class_name CommanderUI
extends FalconPanel
## COMMANDER screen (the grown-up's monitor; mouse and keyboard, no touch needed).
##   MISSION CONTROL  mission select, START/PAUSE/RESTART, harness check, orbit map, live
##                    telemetry, crew status with both kids' current tasks, ship health,
##                    faults, MASTER CAUTION RESET, failure injection, live score.
##   BRIEFING         the full briefing, crew jobs, objectives, Commander tips.
##   TRAINING         difficulty, checklist shortcuts, failure injection, time warp, voice.
##   CONTROLS         live test of every switch, axis and button, devices, LEDs.
##   SETUP            which screen is which (4 roles), layout mode, quality, FPS cap, vsync.
## On a 3-screen rig this whole UI is a tab on the kids' console (Escape toggles it).

const PAGES := ["MISSION CONTROL", "BRIEFING", "TRAINING", "CONTROLS", "SETUP"]

var pages := {}
var tabs := {}
var current := "MISSION CONTROL"
var nav_map: NavMap


func _ready() -> void:
	theme = make_theme(24)
	add_background()
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 14
	root.offset_right = -14
	root.offset_top = 10
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var top := hbox(root, 12)
	top.add_child(label("FILAMENT FALCON  ·  COMMANDER", 30, C_AMBER, false))
	var status := label("", 26, C_TEXT, false)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(status)
	live["status"] = func() -> void:
		var m: Mission = Game.mission
		var tm := int(Game.mission_time)
		status.text = "%s   %s   T+%d:%02d   %s%s" % [m.title if m else "", Game.STATE_NAMES[Game.state], tm / 60, tm % 60,
			("WARP x%d   " % int(Game.warp)) if Game.warp > 1.0 else "", Game.difficulty().to_upper()]
	var tabbar := hbox(root, 8)
	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(holder)
	for p in PAGES:
		var b := button(p, func() -> void: show_page(p), 24, 60)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabbar.add_child(b)
		tabs[p] = b
		var page := MarginContainer.new()
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.visible = false
		holder.add_child(page)
		pages[p] = page
	_build_control(pages["MISSION CONTROL"])
	_build_briefing(pages["BRIEFING"])
	_build_training(pages["TRAINING"])
	_build_controls(pages["CONTROLS"])
	_build_setup(pages["SETUP"])
	show_page("MISSION CONTROL")


func show_page(p: String) -> void:
	if not pages.has(p):
		return
	current = p
	for k in pages:
		(pages[k] as Control).visible = (k == p)
		(tabs[k] as Button).set_pressed_no_signal(k == p)
	refresh()


# ======================================================================== MISSION CONTROL
func _build_control(page: Control) -> void:
	var h := hbox(page, 12)
	# ---- left: mission + flow + score
	var left := panel(h, "MISSION", true, true, C_AMBER)
	left.get_parent().size_flags_stretch_ratio = 0.9
	var mg := grid(left, 2, 6)
	var mbtn := {}
	for id: String in Game.MISSION_ORDER:
		var b := button("%d  %s" % [Game.MISSION_ORDER.find(id) + 1, Game.MISSION_TITLES[id]], func() -> void:
			if Game.state == Game.State.ACTIVE:
				Voice.say("Pause the mission before changing it.")
				return
			Game.load_mission(id)
			Sfx.beep(), 22, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mg.add_child(b)
		mbtn[id] = b
	var tag := label("", 22, C_DIM)
	left.add_child(tag)
	var start := button("START", func() -> void: Game.start_pause(), 38, 100)
	left.add_child(start)
	var r2 := hbox(left, 8)
	var restart := button("RESTART", func() -> void: Game.restart_mission(), 24, 64)
	restart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(restart)
	var skip := button("SKIP STEP ▶", func() -> void: Game.skip_step(), 24, 64)
	skip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(skip)
	var harness := button("HARNESSES FASTENED ✓", func() -> void:
		Game.harness_confirmed = not Game.harness_confirmed
		Sfx.click(), 22, 60)
	left.add_child(harness)
	var end_btn := button("END FREE FLIGHT", func() -> void:
		if Game.mission and Game.mission.has_method("end_flight"):
			Game.mission.call("end_flight"), 22, 60)
	left.add_child(end_btn)
	left.add_child(label("INJECT A FAILURE (while running)", 20, C_RED))
	var fg := grid(left, 2, 6)
	for k: String in ["fire", "leak", "power", "sensor"]:
		var fb := button(k.to_upper(), func() -> void: Game.inject_failure(k), 22, 52)
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fg.add_child(fb)
		live["mc_fail_" + k] = func() -> void:
			fb.disabled = Game.state != Game.State.ACTIVE
			fb.modulate = C_RED if Game.failures.get(k, false) else Color.WHITE
	left.add_child(label("SCORE", 22, C_EDGE))
	var score := label("", 22, C_GREEN)
	score.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(score)
	live["mc_left"] = func() -> void:
		var m: Mission = Game.mission
		if m == null:
			return
		for id in mbtn:
			(mbtn[id] as Button).modulate = C_GREEN if id == Game.mission_id else Color.WHITE
			(mbtn[id] as Button).disabled = Game.state == Game.State.ACTIVE and id != Game.mission_id
		tag.text = m.tagline
		match Game.state:
			Game.State.BRIEFING:
				start.text = "START MISSION"
				start.modulate = C_GREEN
			Game.State.ACTIVE:
				start.text = "PAUSE"
				start.modulate = C_AMBER
			Game.State.PAUSED:
				start.text = "RESUME"
				start.modulate = C_GREEN
			_:
				start.text = "FLY AGAIN"
				start.modulate = C_GREEN
		skip.disabled = Game.state != Game.State.ACTIVE
		harness.modulate = C_GREEN if Game.harness_confirmed else C_AMBER
		harness.text = "HARNESSES FASTENED ✓" if Game.harness_confirmed else "CHECK HARNESSES (click when done)"
		end_btn.visible = m.has_method("end_flight") and Game.state == Game.State.ACTIVE
		var r := ""
		if Game.state == Game.State.COMPLETE or Game.state == Game.State.FAILED:
			r = Game.result_text + "\n"
		for it in Game.score_items:
			r += "%s  +%d\n" % [str(it[0]), int(it[1])]
		r += "TOTAL %d   " % Game.score_total
		if Game.state == Game.State.COMPLETE:
			for i in 3:
				r += "★" if i < Game.stars else "☆"
		score.text = r
		score.add_theme_color_override("font_color", C_RED if Game.state == Game.State.FAILED else C_GREEN)
	# ---- centre: orbit map + telemetry
	var mid := panel(h, "ORBIT MAP", true, true)
	mid.get_parent().size_flags_stretch_ratio = 1.25
	nav_map = NavMap.new()
	nav_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_map.custom_minimum_size = Vector2(400, 300)
	mid.add_child(nav_map)
	var zr := hbox(mid, 6)
	for zz: Array in [["ZOOM -", 1.0 / 1.6], ["ZOOM +", 1.6], ["RESET", 0.0]]:
		var f: float = zz[1]
		var zb := button(str(zz[0]), func() -> void:
			nav_map.zoom = 1.0 if f == 0.0 else clampf(nav_map.zoom * f, 0.2, 40.0), 20, 50)
		zb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		zr.add_child(zb)
	var vb := button("VIEW: COCKPIT", func() -> void: Game.view_mode = 1 - Game.view_mode, 20, 50)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zr.add_child(vb)
	var telem := label("", 22, Color(0.75, 0.95, 1.0))
	mid.add_child(telem)
	var wr := hbox(mid, 6)
	wr.add_child(label("WARP", 20, C_DIM, false))
	for w: int in [1, 4, 10, 100, 1000]:
		var b := button("x%d" % w, func() -> void: Game.set_warp(float(w)), 20, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wr.add_child(b)
		live["warp_%d" % w] = func() -> void: b.modulate = C_GREEN if int(Game.warp) == w else Color.WHITE
	live["mc_mid"] = func() -> void:
		vb.text = "VIEW: " + ("CHASE" if Game.view_mode == 1 else "COCKPIT")
		var sim: ShipSim = Game.sim
		var orb := Hud.orbit_strings(sim)
		var dom := sim.dominant.display_name if sim.dominant else "?"
		telem.text = "%s near %s   ALT %s   SPD %d m/s   V/S %+d   %.1f g\nAp %s   Pe %s   THR %d%%   FUEL %d kg   RCS %d kg   ASSIST %s   GEAR %s   %s" % [
			orb[0], dom, Hud._fmt_dist(sim.altitude), int(sim.surface_vel.length()), int(sim.vspeed), sim.g_load,
			orb[1], orb[2], int(sim.throttle * 100.0), int(sim.fuel), int(sim.mono), ShipSim.FA_NAMES[sim.fa_mode],
			"DN" if sim.gear_down else "UP", "ENGINE ON" if sim.engine_on else ("ARMED" if InputHub.on("engine_arm") else "ENGINE OFF")]
	# ---- right: crew + ship + faults
	var right := panel(h, "CREW STATUS", true, true)
	var pl := label("", 24, C_PILOT)
	right.add_child(pl)
	var ol := label("", 24, C_OPS)
	right.add_child(ol)
	var objs := label("", 20, C_DIM)
	right.add_child(objs)
	bar(right, "HULL", "mc_hull", func() -> Array:
		return [Game.hull / 100.0, "%d%%" % int(Game.hull), C_GREEN if Game.hull > 50.0 else C_RED], 130, 20)
	bar(right, "OXYGEN", "mc_o2", func() -> Array:
		return [Game.o2 / 100.0, "%d%%" % int(Game.o2), C_GREEN if Game.o2 > 60.0 else C_RED], 130, 20)
	bar(right, "POWER", "mc_pwr", func() -> Array:
		return [Game.power_draw / maxf(Game.power_avail, 1.0), "%d/%d kW" % [int(Game.power_draw), int(Game.power_avail)], C_GREEN if Game.power_ok else C_RED], 130, 20)
	bar(right, "FUEL", "mc_fuel", func() -> Array:
		var s: ShipSim = Game.sim
		return [s.fuel / s.fuel_max, "%d kg" % int(s.fuel), C_GREEN if s.fuel > 1500.0 else C_RED], 130, 20)
	var faults := label("", 22, C_AMBER)
	faults.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(faults)
	var cr := button("MASTER CAUTION RESET", func() -> void: Game.reset_caution(), 24, 64)
	right.add_child(cr)
	live["mc_right"] = func() -> void:
		var m: Mission = Game.mission
		if m == null:
			return
		var o := m.current_objective()
		var role := str(o.get("role", ""))
		var txt := str(o.get("text", ""))
		var act := Game.state == Game.State.ACTIVE
		pl.text = "PILOT  %s\n%s" % ["◀ ACTING NOW" if act and role in ["PILOT", "BOTH", "ALL"] else "", txt if act and role in ["PILOT", "BOTH", "ALL"] else "(standing by)  assist " + ShipSim.FA_NAMES[Game.sim.fa_mode]]
		ol.text = "OPS  %s\n%s" % ["◀ ACTING NOW" if act and role in ["OPS", "BOTH", "ALL"] else "", txt if act and role in ["OPS", "BOTH", "ALL"] else "(standing by)  mode " + Game.OPS_MODES[Game.ops_mode]]
		var s := "Step %d of %d" % [mini(m.step + 1, m.objectives.size()), m.objectives.size()]
		if m.step + 1 < m.objectives.size():
			var nx: Dictionary = m.objectives[m.step + 1]
			s += "   next: [%s] %s" % [str(nx.get("role", "")), str(nx.get("text", ""))]
		objs.text = s
		var f := ""
		for k in Game.failures:
			if Game.failures[k]:
				f += "⚠ " + ConsoleUI.fault_help(k) + "\n"
		for k in Game.warnings:
			if not Game.failures.has(k):
				f += "• " + str(Game.warnings[k]) + "\n"
		if Game.caution_active:
			f = "MASTER CAUTION ON\n" + f
		faults.text = f if f != "" else "All systems nominal ✓"
		faults.add_theme_color_override("font_color", C_AMBER if f != "" else C_GREEN)
		cr.modulate = C_RED if Game.caution_active else Color.WHITE


# ======================================================================== BRIEFING
func _build_briefing(page: Control) -> void:
	var h := hbox(page, 12)
	var left := panel(h, "", true, true)
	left.get_parent().size_flags_stretch_ratio = 1.5
	var title := label("", 50, C_EDGE)
	left.add_child(title)
	var tag := label("", 28, C_AMBER)
	left.add_child(tag)
	var brief := label("", 26)
	left.add_child(brief)
	var jobs := hbox(left, 12)
	var pj := panel(jobs, "PILOT (left seat)", true, false, C_PILOT)
	var pjl := label("", 24, C_GREEN)
	pj.add_child(pjl)
	var oj := panel(jobs, "OPS (right seat)", true, false, C_OPS)
	var ojl := label("", 24, C_GREEN)
	oj.add_child(ojl)
	var right := panel(h, "OBJECTIVES", true, true)
	var objs := label("", 26)
	right.add_child(objs)
	right.add_child(label("COMMANDER TIP", 22, C_AMBER))
	var cmd := label("", 24, C_DIM)
	right.add_child(cmd)
	var say := button("READ BRIEFING ALOUD", func() -> void:
		if Game.mission:
			Voice.say(Game.mission.title + ". " + Game.mission.briefing, 1), 24, 64)
	right.add_child(say)
	live["brief"] = func() -> void:
		var m: Mission = Game.mission
		if m == null:
			return
		title.text = m.title
		tag.text = m.tagline
		brief.text = m.briefing
		pjl.text = m.pilot_job
		ojl.text = m.ops_job
		cmd.text = m.commander_tip
		var s := ""
		for i in m.objectives.size():
			var o: Dictionary = m.objectives[i]
			s += "%s  [%s] %s\n" % ["✔" if i < m.step else ("▶" if i == m.step else "○"), str(o.get("role", "")), str(o.get("text", ""))]
		objs.text = s


# ======================================================================== TRAINING
func _build_training(page: Control) -> void:
	var h := hbox(page, 12)
	var a := panel(h, "DIFFICULTY & ASSISTS", true, true)
	var dr := hbox(a, 8)
	for d: String in Game.DIFFICULTIES:
		var db := button(d.to_upper(), func() -> void: Settings.set_v("game", "difficulty", d), 26, 70)
		db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dr.add_child(db)
		live["diff_" + d] = func() -> void: db.modulate = C_GREEN if Game.difficulty() == d else Color.WHITE
	a.add_child(label("EASY: +30% fuel and RCS, half damage.  HARD: -15% fuel, 1.5x damage.\nApplies when a mission is (re)loaded.", 20, C_DIM))
	var sk := button("", func() -> void: Settings.set_v("game", "skip_checklist", not bool(Settings.get_v("game", "skip_checklist"))), 22, 64)
	a.add_child(sk)
	live["skipcl"] = func() -> void:
		var on := bool(Settings.get_v("game", "skip_checklist"))
		sk.text = "SKIP OVERHEAD CHECKLIST (little crews): " + ("ON" if on else "OFF")
		sk.modulate = C_GREEN if on else Color.WHITE
	var cr := hbox(a, 8)
	var all_on := button("CHECKLIST ALL ON", func() -> void: Game.auto_checklist(), 22, 64)
	all_on.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cr.add_child(all_on)
	var all_off := button("CHECKLIST ALL OFF", func() -> void:
		for id in Game.CHECKLIST:
			InputHub.set_switch(id, false), 22, 64)
	all_off.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cr.add_child(all_off)
	a.add_child(label("PILOT ASSIST (overrides the knob until it is turned)", 20, C_EDGE))
	var ar := hbox(a, 8)
	group_buttons(ar, "fa", ShipSim.FA_NAMES, 20, 60)
	var vc := button("", func() -> void: Settings.set_v("audio", "voice", not bool(Settings.get_v("audio", "voice"))), 22, 64)
	a.add_child(vc)
	live["voice"] = func() -> void:
		vc.text = "VOICE CALLOUTS: " + ("ON" if Settings.get_v("audio", "voice") else "OFF")
		vc.modulate = C_GREEN if Settings.get_v("audio", "voice") else Color.WHITE
	var b := panel(h, "FAILURES", true, true, C_RED)
	b.add_child(label("Inject a failure while the mission runs. The crew sees what to do on the console SYSTEMS page.", 22, C_DIM))
	for k: String in ["fire", "leak", "power", "sensor"]:
		var fb := button("FAIL: " + ConsoleUI.fault_help(k), func() -> void: Game.inject_failure(k), 22, 70)
		b.add_child(fb)
		live["tr_fail_" + k] = func() -> void:
			fb.disabled = Game.state != Game.State.ACTIVE
			fb.modulate = C_RED if Game.failures.get(k, false) else Color.WHITE
	b.add_child(button("MASTER CAUTION RESET", func() -> void: Game.reset_caution(), 24, 70))


# ======================================================================== CONTROLS TEST
func _build_controls(page: Control) -> void:
	var v := VBoxContainer.new()
	page.add_child(v)
	var dev := label("", 22)
	v.add_child(dev)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var g := GridContainer.new()
	g.columns = 3
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 12)
	sc.add_child(g)
	var cells := {}
	for a in InputHub.ACTIONS:
		var id: String = a["id"]
		var l := label("", 20, C_TEXT, false)
		l.custom_minimum_size = Vector2(590, 32)
		l.clip_text = true
		g.add_child(l)
		cells[id] = [l, str(a["role"]), str(a["label"]), str(a["type"])]
	var tools := hbox(v, 8)
	tools.add_child(button("WRITE TEMPLATE input_map.json", func() -> void:
		var p := "user://input_map_template.json"
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f:
			f.store_string(InputHub.export_template())
			Voice.say("Template written to " + ProjectSettings.globalize_path(p)), 20, 56))
	tools.add_child(button("LED TEST", func() -> void: LedLink.set_all_signals(Color(0, 0.6, 1.0), "PULSE"), 20, 56))
	live["controls"] = func() -> void:
		if current != "CONTROLS" or not is_visible_in_tree():
			return
		var pads := InputHub.connected_joypads()
		var ds := "Devices: "
		for dn in [InputHub.DEV_PILOT, InputHub.DEV_OPS, InputHub.DEV_CMD]:
			ds += "%s %s   " % [dn, "✔" if InputHub.device_connected(dn) else "✖ (keyboard)"]
		ds += "\nJoypads seen: %s\nMap: %s %s\nLEDs: %s (%d lines)   Voice: %s" % [str(pads), InputHub.map_source, ("ERRORS: " + "; ".join(InputHub.map_errors)) if not InputHub.map_errors.is_empty() else "", LedLink.status, LedLink.lines_sent, Voice.engine]
		dev.text = ds
		for id in cells:
			var cell: Array = cells[id]
			var l: Label = cell[0]
			var val := InputHub.axis(id)
			var vs := ""
			match cell[3]:
				"axis":
					vs = "%+.2f" % val
				"throttle":
					vs = "%3d%%" % int(val * 100.0)
				"pos":
					vs = "●" if InputHub.on(id) else "○"
				_:
					vs = "ON" if InputHub.on(id) else "--"
			l.text = "%s %-6s %s  [%s]" % [vs, cell[1], cell[2], InputHub.binding_text(id)]
			var active := absf(val) > 0.05 or InputHub.on(id)
			l.add_theme_color_override("font_color", C_GREEN if active else Color(0.7, 0.8, 0.9))


# ======================================================================== SETUP
func _build_setup(page: Control) -> void:
	var h := hbox(page, 12)
	var a := panel(h, "SCREENS", true, true)
	a.get_parent().size_flags_stretch_ratio = 1.4
	var mode_row := hbox(a, 8)
	mode_row.add_child(label("LAYOUT", 20, C_DIM, false))
	for m: String in ["auto", "cockpit", "dev"]:
		var mb := button(m.to_upper(), func() -> void: Settings.set_v("display", "mode", m), 22, 56)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mode_row.add_child(mb)
		live["mode_" + m] = func() -> void: mb.modulate = C_GREEN if Settings.get_v("display", "mode") == m else Color.WHITE
	var screens := label("", 20, C_DIM)
	a.add_child(screens)
	for role: String in DisplayManager.ROLES:
		var row := hbox(a, 8)
		var l := label(DisplayManager.ROLE_NAMES[role], 22, C_TEXT, false)
		l.custom_minimum_size.x = 230
		row.add_child(l)
		row.add_child(button("◀", func() -> void: _cycle_screen(role, -1), 24, 52))
		var val := label("", 18, C_GREEN, false)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # long "AUTO → #2 22\" … DisplayPort-0" texts wrap
		val.custom_minimum_size.x = 120
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(val)
		row.add_child(button("▶", func() -> void: _cycle_screen(role, 1), 24, 52))
		row.add_child(button("IDENTIFY", func() -> void: _identify(role), 20, 52))
		live["scr_" + role] = func() -> void:
			val.text = display.describe_role(role) if display else "?"
	var ar := hbox(a, 8)
	var apply := button("APPLY WINDOW LAYOUT", func() -> void:
		if display:
			display.apply_layout(), 24, 64)
	apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ar.add_child(apply)
	var idall := button("IDENTIFY ALL", func() -> void:
		for r: String in DisplayManager.ROLES:
			_identify(r), 22, 64)
	ar.add_child(idall)
	a.add_child(label("◀ ▶ cycles AUTO → screen 0, 1, 2 … Changes are saved; press APPLY to move the windows. Touch: run game/tools/setup_displays.sh (run.sh does it) to map the touchscreen to the KIDS' CONSOLE output.", 18, C_DIM))
	var geo := [["monitor_width_m", "Window width m", 0.01], ["monitor_gap_m", "Gap between m", 0.01],
		["eye_distance_m", "Eye distance m", 0.02], ["eye_height_m", "Eye height m", 0.02], ["toe_in_deg", "Toe-in deg", 1.0], ["view_scale", "View scale", 0.05]]
	var gg := grid(a, 2, 6)
	for gdef in geo:
		var row := HBoxContainer.new()
		gg.add_child(row)
		var gl := label(str(gdef[1]), 20, C_TEXT, false)
		gl.custom_minimum_size.x = 170
		row.add_child(gl)
		var key: String = gdef[0]
		var step: float = gdef[2]
		row.add_child(button("-", func() -> void: Settings.set_v("display", key, snappedf(float(Settings.get_v("display", key)) - step, 0.001)), 22, 46))
		var gv := label("", 20, C_GREEN, false)
		gv.custom_minimum_size.x = 80
		gv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(gv)
		row.add_child(button("+", func() -> void: Settings.set_v("display", key, snappedf(float(Settings.get_v("display", key)) + step, 0.001)), 22, 46))
		live["geo_" + key] = func() -> void: gv.text = "%.3f" % float(Settings.get_v("display", key))
	var b := panel(h, "GRAPHICS / SOUND / LIGHTS", true, true)
	var qrow := hbox(b, 6)
	for q: String in Settings.QUALITY_LEVELS:
		var qb := button(q.to_upper(), func() -> void: Settings.set_v("graphics", "quality", q), 22, 56)
		qb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qrow.add_child(qb)
		live["q_" + q] = func() -> void: qb.modulate = C_GREEN if Settings.quality() == q else Color.WHITE
	var frow := hbox(b, 6)
	for fps: int in [60, 75, 120, 144]:
		var fb := button("%d FPS" % fps, func() -> void: Settings.set_v("display", "max_fps", fps), 20, 56)
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frow.add_child(fb)
		live["fps_%d" % fps] = func() -> void: fb.modulate = C_GREEN if int(Settings.get_v("display", "max_fps")) == fps else Color.WHITE
	var vrow := hbox(b, 6)
	for vm: String in ["mailbox", "fifo", "off"]:
		var vmb := button("VSYNC " + vm.to_upper(), func() -> void:
			Settings.set_v("display", "vsync", vm)
			if display:
				display.apply_vsync_all(), 18, 56)
		vmb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vrow.add_child(vmb)
		live["vs_" + vm] = func() -> void: vmb.modulate = C_GREEN if str(Settings.get_v("display", "vsync")) == vm else Color.WHITE
	var lb := button("LED PANEL LINK (restart)", func() -> void: Settings.set_v("led", "enabled", not bool(Settings.get_v("led", "enabled"))), 22, 56)
	b.add_child(lb)
	var fsb := button("FULLSCREEN WINDOWS", func() -> void: Settings.set_v("display", "fullscreen", not bool(Settings.get_v("display", "fullscreen"))), 22, 56)
	b.add_child(fsb)
	var info := label("", 20)
	b.add_child(info)
	b.add_child(button("QUIT GAME", func() -> void: get_tree().quit(), 22, 56))
	live["setup"] = func() -> void:
		if current != "SETUP":
			return
		lb.modulate = C_GREEN if Settings.get_v("led", "enabled") else Color.WHITE
		fsb.modulate = C_GREEN if Settings.get_v("display", "fullscreen") else Color.WHITE
		screens.text = display.describe_monitors() if display else ""
		info.text = "FPS: %d (cap %d)\nRunning layout: %s\nVoice: %s\nLED link: %s\nRenderer: %s\nSettings file: %s" % [int(Engine.get_frames_per_second()), Engine.max_fps,
			display.layout_summary() if display else "?", Voice.engine, LedLink.status, RenderingServer.get_video_adapter_name(), ProjectSettings.globalize_path(Settings.PATH)]


func _cycle_screen(role: String, d: int) -> void:
	if display:
		display.cycle_role_screen(role, d)


func _identify(role: String) -> void:
	if display == null:
		return
	var scr: int = display.screen_of(role)
	if scr < 0:
		return
	var w := Window.new()
	w.borderless = true
	w.always_on_top = true
	w.size = Vector2i(900, 300)
	w.position = DisplayServer.screen_get_position(scr) + (DisplayServer.screen_get_size(scr) - w.size) / 2
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.1, 0.2)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	w.add_child(bg)
	var l := Label.new()
	l.text = "%s\nscreen %d  %s" % [DisplayManager.ROLE_NAMES[role], scr, display.monitor_name(scr)]
	l.add_theme_font_size_override("font_size", 56)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	w.add_child(l)
	get_tree().root.add_child(w)
	get_tree().create_timer(3.0).timeout.connect(w.queue_free)
