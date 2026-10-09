class_name ConsoleUI
extends Control
## Centre touchscreen. Pages: MISSION, NAV, SYSTEMS, CHECKLIST, CAMERAS, CONTROLS, SETUP.
## Everything here is also reachable from the hardware; touch buttons are the fallback when a
## board is missing (and they let a parent run a mission from just the console).

const C_BG := Color(0.02, 0.04, 0.08)
const C_PANEL := Color(0.04, 0.09, 0.15, 0.95)
const C_EDGE := Color(0.2, 0.75, 1.0)
const C_TEXT := Color(0.85, 0.95, 1.0)
const C_GREEN := Color(0.3, 1.0, 0.45)
const C_AMBER := Color(1.0, 0.7, 0.15)
const C_RED := Color(1.0, 0.3, 0.25)
const PAGES := ["MISSION", "NAV", "SYSTEMS", "CHECKLIST", "CAMERAS", "CONTROLS", "SETUP"]

var display: Node
var pages := {}
var tabs := {}
var current := "MISSION"
var live := {}                   # key -> Callable updating a widget
var _acc := 0.0
var _status: Label
var _telem: Label
var _cam_vps: Array[SubViewport] = []
var _cam_cams: Array[Camera3D] = []
var nav_map: NavMap


func _ready() -> void:
	theme = _make_theme()
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_right = -16
	root.offset_top = 12
	root.offset_bottom = -12
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	# Top bar
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	root.add_child(top)
	var logo := Label.new()
	logo.text = "FILAMENT FALCON"
	logo.add_theme_font_size_override("font_size", 34)
	logo.add_theme_color_override("font_color", C_EDGE)
	top.add_child(logo)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.add_theme_font_size_override("font_size", 26)
	top.add_child(_status)
	# Flight telemetry strip (the window HUDs stay minimal; the numbers live here, on every page)
	var strip := PanelContainer.new()
	root.add_child(strip)
	_telem = Label.new()
	_telem.add_theme_font_size_override("font_size", 23)
	_telem.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0))
	_telem.clip_text = true
	strip.add_child(_telem)
	var tabbar := HBoxContainer.new()
	tabbar.add_theme_constant_override("separation", 8)
	root.add_child(tabbar)
	var group := ButtonGroup.new()
	for p in PAGES:
		var b := _button(p, func() -> void: show_page(p), 30)
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 84
		tabbar.add_child(b)
		tabs[p] = b
	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(holder)
	for p in PAGES:
		var page := MarginContainer.new()
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.visible = false
		holder.add_child(page)
		pages[p] = page
	_build_mission(pages["MISSION"])
	_build_nav(pages["NAV"])
	_build_systems(pages["SYSTEMS"])
	_build_checklist(pages["CHECKLIST"])
	_build_cameras(pages["CAMERAS"])
	_build_controls(pages["CONTROLS"])
	_build_setup(pages["SETUP"])
	show_page("MISSION")
	Game.mission_loaded.connect(func() -> void: show_page("MISSION"))
	Game.mission_finished.connect(func(_ok: bool) -> void: show_page("MISSION"))


func show_page(p: String) -> void:
	current = p
	for k in pages:
		(pages[k] as Control).visible = (k == p)
	(tabs[p] as Button).set_pressed_no_signal(true)
	for v in _cam_vps:
		v.render_target_update_mode = SubViewport.UPDATE_ALWAYS if p == "CAMERAS" else SubViewport.UPDATE_DISABLED
	_refresh()


func _process(dt: float) -> void:
	_acc += dt
	if current == "CAMERAS":
		_update_cameras()
	if _acc < 0.1:
		return
	_acc = 0.0
	_refresh()


func _refresh() -> void:
	var sim: ShipSim = Game.sim
	if sim and _telem:
		var orb := Hud.orbit_strings(sim)
		var thr := "%d%%%s" % [int(sim.throttle * 100.0), "+B" if sim.boost else ""]
		var fuel := ("BOOSTER %d%%" % int(sim.booster_fuel / sim.booster_fuel_max * 100.0)) if sim.booster_attached else ("FUEL %d kg" % int(sim.fuel))
		_telem.text = "ALT %s   SPD %d m/s   V/S %+.0f   %.1f g   THR %s   %s   %s  AP %s  PE %s   %s  GEAR %s  FLAPS %s%s" % [
			Hud._fmt_dist(sim.altitude), int(sim.surface_vel.length()), sim.vspeed, sim.g_load, thr, fuel,
			orb[0], orb[1], orb[2], ShipSim.FA_NAMES[sim.fa_mode], "DN" if sim.gear_down else "UP",
			["UP", "HALF", "DN"][int(sim.flaps * 2.0)], "  ENGINE ON" if sim.engine_on else ("  ARMED" if InputHub.on("engine_arm") else "")]
	var m: Mission = Game.mission
	var tm := int(Game.mission_time)
	_status.text = "%s   %s   T+%d:%02d   %s" % [m.title if m else "", Game.STATE_NAMES[Game.state], tm / 60, tm % 60,
		("WARP x%d" % int(Game.warp)) if Game.warp > 1.0 else ""]
	for k in live:
		var cb: Callable = live[k]
		if cb.is_valid():
			cb.call()


# ======================================================================== theme / widgets
func _sb(c: Color, edge: Color, w: int = 2, r: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.border_color = edge
	s.set_border_width_all(w)
	s.set_corner_radius_all(r)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 26
	t.set_stylebox("normal", "Button", _sb(Color(0.06, 0.14, 0.24), C_EDGE * 0.8))
	t.set_stylebox("hover", "Button", _sb(Color(0.09, 0.2, 0.33), C_EDGE))
	t.set_stylebox("pressed", "Button", _sb(Color(0.1, 0.45, 0.6), Color(0.6, 1, 1), 3))
	t.set_stylebox("hover_pressed", "Button", _sb(Color(0.1, 0.45, 0.6), Color(0.6, 1, 1), 3))
	t.set_stylebox("disabled", "Button", _sb(Color(0.04, 0.06, 0.09), Color(0.2, 0.3, 0.4)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_color", "Label", C_TEXT)
	t.set_stylebox("panel", "PanelContainer", _sb(C_PANEL, C_EDGE * 0.6, 2, 16))
	t.set_stylebox("normal", "LineEdit", _sb(Color(0.03, 0.06, 0.1), C_EDGE * 0.6))
	t.set_stylebox("background", "ProgressBar", _sb(Color(0.02, 0.04, 0.07), C_EDGE * 0.5, 2, 6))
	t.set_stylebox("fill", "ProgressBar", _sb(C_GREEN, C_GREEN, 0, 6))
	t.set_stylebox("normal", "OptionButton", _sb(Color(0.06, 0.14, 0.24), C_EDGE * 0.8))
	return t


func _button(text: String, cb: Callable, fs: int = 28) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 80)
	b.add_theme_font_size_override("font_size", fs)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _label(text: String, fs: int = 26, c: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _panel(parent: Control, title: String = "", expand_h := true, expand_v := false) -> VBoxContainer:
	var pc := PanelContainer.new()
	if expand_h:
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand_v:
		pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pc.add_child(v)
	if title != "":
		v.add_child(_label(title, 24, C_EDGE))
	return v


func _bar(parent: Control, title: String, key: String, getter: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := _label(title, 24)
	l.custom_minimum_size.x = 220
	row.add_child(l)
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(300, 34)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.show_percentage = false
	row.add_child(pb)
	var val := _label("", 24)
	val.custom_minimum_size.x = 190
	row.add_child(val)
	live[key] = func() -> void:
		var r: Array = getter.call()     # [fraction, text, color]
		pb.value = clampf(float(r[0]), 0.0, 1.0) * 100.0
		val.text = str(r[1])
		var sb: StyleBoxFlat = (pb.get_theme_stylebox("fill") as StyleBoxFlat).duplicate()
		sb.bg_color = r[2]
		pb.add_theme_stylebox_override("fill", sb)


## A touch toggle for a maintained switch. Disabled (mirror only) when the real board is present.
func _switch_button(id: String, text: String) -> Button:
	var b := _button(text, func() -> void: pass, 24)
	b.toggle_mode = true
	b.toggled.connect(func(on: bool) -> void:
		if not InputHub.has_hardware_for(id):
			InputHub.set_switch(id, on))
	live["sw_" + id] = func() -> void:
		var on := InputHub.on(id)
		b.set_pressed_no_signal(on)
		b.disabled = InputHub.has_hardware_for(id)
		b.modulate = Color(0.6, 1.0, 0.7) if on else Color.WHITE
	return b


# ======================================================================== MISSION
func _build_mission(page: Control) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	page.add_child(h)
	var left := _panel(h, "", true, true)
	left.size_flags_stretch_ratio = 1.5
	var title := _label("", 54, C_EDGE)
	left.add_child(title)
	var tag := _label("", 30, C_AMBER)
	left.add_child(tag)
	var brief := _label("", 26)
	left.add_child(brief)
	var jobs := HBoxContainer.new()
	jobs.add_theme_constant_override("separation", 12)
	left.add_child(jobs)
	var pj := _panel(jobs, "PILOT (left seat)")
	var pjl := _label("", 24, C_GREEN)
	pj.add_child(pjl)
	var oj := _panel(jobs, "OPS (right seat)")
	var ojl := _label("", 24, C_GREEN)
	oj.add_child(ojl)
	var cmd := _label("", 22, Color(0.7, 0.8, 0.9))
	left.add_child(cmd)
	var objs := _label("", 26)
	left.add_child(objs)
	var right := _panel(h, "COMMANDER", true, true)
	var sel := HBoxContainer.new()
	right.add_child(sel)
	sel.add_child(_button("◀", func() -> void: Game.select_mission(-1), 40))
	var mlist := _label("", 30, C_TEXT)
	mlist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mlist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel.add_child(mlist)
	sel.add_child(_button("▶", func() -> void: Game.select_mission(1), 40))
	var start := _button("START", func() -> void: Game.start_pause(), 44)
	start.custom_minimum_size.y = 120
	right.add_child(start)
	var harness := _button("HARNESSES FASTENED ✓", func() -> void:
		Game.harness_confirmed = not Game.harness_confirmed
		Sfx.click(), 24)
	right.add_child(harness)
	var end_btn := _button("END FREE FLIGHT", func() -> void:
		if Game.mission and Game.mission.has_method("end_flight"):
			Game.mission.call("end_flight"), 26)
	right.add_child(end_btn)
	right.add_child(_label("FAILURE INJECTION", 22, C_RED))
	var fg := GridContainer.new()
	fg.columns = 2
	right.add_child(fg)
	for k: String in ["fire", "leak", "power", "sensor"]:
		var fb := _button(k.to_upper(), func() -> void: Game.inject_failure(k), 26)
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fg.add_child(fb)
	right.add_child(_button("CAUTION RESET", func() -> void: Game.reset_caution(), 26))
	var result := _label("", 26, C_GREEN)
	right.add_child(result)
	live["mission"] = func() -> void:
		var m: Mission = Game.mission
		if m == null:
			return
		title.text = m.title
		tag.text = m.tagline
		brief.text = m.briefing
		pjl.text = m.pilot_job
		ojl.text = m.ops_job
		cmd.text = "Commander: " + m.commander_tip
		var s := "OBJECTIVES\n"
		for i in m.objectives.size():
			var o: Dictionary = m.objectives[i]
			var mark := "✔" if i < m.step else ("▶" if i == m.step else "○")
			s += "%s  [%s] %s\n" % [mark, str(o.get("role", "")), str(o.get("text", ""))]
		objs.text = s
		var idx := Game.MISSION_ORDER.find(Game.mission_id)
		mlist.text = "%d/%d  %s" % [idx + 1, Game.MISSION_ORDER.size(), m.title]
		match Game.state:
			Game.State.BRIEFING:
				start.text = "START MISSION"
			Game.State.ACTIVE:
				start.text = "PAUSE"
			Game.State.PAUSED:
				start.text = "RESUME"
			_:
				start.text = "FLY AGAIN"
		harness.modulate = C_GREEN if Game.harness_confirmed else Color.WHITE
		end_btn.visible = m.has_method("end_flight") and Game.state == Game.State.ACTIVE
		if Game.state == Game.State.COMPLETE or Game.state == Game.State.FAILED:
			var r := Game.result_text + "\n"
			for it in Game.score_items:
				r += "%s  +%d\n" % [str(it[0]), int(it[1])]
			r += "TOTAL %d   " % Game.score_total
			for i in 3:
				r += "★" if i < Game.stars else "☆"
			result.text = r
			result.add_theme_color_override("font_color", C_GREEN if Game.state == Game.State.COMPLETE else C_RED)
		else:
			result.text = ""


# ======================================================================== NAV
func _build_nav(page: Control) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	page.add_child(h)
	var mp := _panel(h, "ORBIT MAP", true, true)
	mp.size_flags_stretch_ratio = 1.4
	nav_map = NavMap.new()
	nav_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_map.custom_minimum_size = Vector2(600, 500)
	mp.add_child(nav_map)
	var zr := HBoxContainer.new()
	mp.add_child(zr)
	zr.add_child(_button("ZOOM -", func() -> void: nav_map.zoom = maxf(nav_map.zoom / 1.6, 0.2)))
	zr.add_child(_button("ZOOM +", func() -> void: nav_map.zoom = minf(nav_map.zoom * 1.6, 40.0)))
	zr.add_child(_button("RESET", func() -> void: nav_map.zoom = 1.0))
	var r := _panel(h, "NAVIGATION", true, true)
	var info := _label("", 26)
	r.add_child(info)
	r.add_child(_label("STEER TO (assist PROGRADE mode):", 22, C_EDGE))
	var vg := GridContainer.new()
	vg.columns = 3
	r.add_child(vg)
	var vbtn := {}
	for nv in Game.NAV_VECTORS:
		var b := _button(nv, func() -> void:
			Game.nav_vector = nv
			Voice.say("Steering to " + nv.to_lower())
			Sfx.click(), 22)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vg.add_child(b)
		vbtn[nv] = b
	var tr := HBoxContainer.new()
	r.add_child(tr)
	tr.add_child(_button("NEXT TARGET", func() -> void: Game.cycle_nav_target(), 26))
	tr.add_child(_button("VIEW", func() -> void: Game.view_mode = 1 - Game.view_mode, 26))
	r.add_child(_label("TIME WARP (coasting; max x4 in the air):", 22, C_EDGE))
	var wr := HBoxContainer.new()
	r.add_child(wr)
	for w: int in [1, 4, 10, 100, 1000]:
		var b := _button("x%d" % w, func() -> void: Game.set_warp(float(w)), 26)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wr.add_child(b)
	live["nav"] = func() -> void:
		var sim: ShipSim = Game.sim
		var dom: CelestialBody = sim.dominant
		if dom == null:
			return
		var el := OrbitMath.elements(sim.pos.rel(dom.pos), sim.vel - dom.vel, dom.gm, dom.radius)
		var orb := Hud.orbit_strings(sim)
		var s := "Near: %s   (%s)\nAltitude: %s\nSpeed: %d m/s\n" % [dom.display_name, orb[0], Hud._fmt_dist(sim.altitude), int((sim.vel - dom.vel).length())]
		if orb[0] == "ON THE GROUND":
			s += "Apoapsis: ---   Periapsis: ---\n(no orbit yet: we need about 2,400 m/s sideways)\n"
		else:
			s += "Apoapsis: %s%s\n" % [orb[1], ("  (in %ds)" % int(float(el["time_to_ap"]))) if orb[1] != "ESCAPE" else ""]
			s += "Periapsis: %s\n" % orb[2]
			if orb[0] == "IN ORBIT":
				s += "Orbit time: %d min\n" % int(float(el["period"]) / 60.0)
		var tgt: Dictionary = Game.current_target()
		if not tgt.is_empty():
			var ts: Array = Game.target_state()
			var rel: Vector3 = (ts[0] as BigVec).rel(sim.pos)
			s += "Target: %s  %s  rel %.1f m/s" % [str(tgt["name"]), Hud._fmt_dist(rel.length()), (sim.vel - (ts[1] as Vector3)).length()]
		else:
			s += "Target: none"
		info.text = s
		for k in vbtn:
			(vbtn[k] as Button).modulate = C_GREEN if k == Game.nav_vector else Color.WHITE


# ======================================================================== SYSTEMS
func _build_systems(page: Control) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	page.add_child(h)
	var a := _panel(h, "SHIP STATUS", true, true)
	_bar(a, "POWER USE", "b_pwr", func() -> Array:
		return [Game.power_draw / maxf(Game.power_avail, 1.0), "%d/%d kW" % [int(Game.power_draw), int(Game.power_avail)], C_GREEN if Game.power_ok else C_RED])
	_bar(a, "REACTOR", "b_rea", func() -> Array:
		return [Game.reactor_out / 100.0, "%d%%" % int(Game.reactor_out), C_GREEN if Game.reactor_out > 90.0 else C_AMBER])
	_bar(a, "FUEL", "b_fuel", func() -> Array:
		var s: ShipSim = Game.sim
		return [s.fuel / s.fuel_max, "%d kg" % int(s.fuel), C_GREEN if s.fuel > 1500.0 else C_RED])
	_bar(a, "BOOSTER", "b_boost", func() -> Array:
		var s: ShipSim = Game.sim
		return [s.booster_fuel / s.booster_fuel_max if s.booster_attached else 0.0, "%d kg" % int(s.booster_fuel) if s.booster_attached else "none", C_AMBER])
	_bar(a, "RCS FUEL", "b_mono", func() -> Array:
		var s: ShipSim = Game.sim
		return [s.mono / s.mono_max, "%d kg" % int(s.mono), C_EDGE])
	_bar(a, "OXYGEN", "b_o2", func() -> Array:
		return [Game.o2 / 100.0, "%d%%" % int(Game.o2), C_GREEN if Game.o2 > 60.0 else C_RED])
	_bar(a, "CABIN", "b_cab", func() -> Array:
		return [Game.cabin_kpa / 101.0, "%d kPa" % int(Game.cabin_kpa), C_GREEN if Game.cabin_kpa > 80.0 else C_RED])
	_bar(a, "HULL", "b_hull", func() -> Array:
		return [Game.hull / 100.0, "%d%%" % int(Game.hull), C_GREEN if Game.hull > 50.0 else C_RED])
	_bar(a, "HULL TEMP", "b_temp", func() -> Array:
		var s: ShipSim = Game.sim
		return [(s.hull_temp - 250.0) / 1400.0, "%d K" % int(s.hull_temp), C_GREEN if s.hull_temp < 900.0 else (C_AMBER if s.hull_temp < 1400.0 else C_RED)])
	_bar(a, "JUMP DRIVE", "b_jump", func() -> Array:
		return [Game.jump_charge / 100.0, "%d%%" % int(Game.jump_charge), Color(0.75, 0.5, 1.0)])
	var b := _panel(h, "OPS POWER PANEL & FAULTS", true, true)
	var g := GridContainer.new()
	g.columns = 3
	b.add_child(g)
	for pair in [["pwr_reactor", "REACTOR"], ["pwr_life", "LIFE SUPPORT"], ["pwr_shields", "SHIELDS"], ["pwr_comms", "COMMS"], ["pwr_sensors", "SENSORS"], ["cargo_doors", "CARGO DOORS"], ["jump_arm", "JUMP ARM"], ["dock_clamp", "DOCK CLAMP"]]:
		var sb := _switch_button(pair[0], pair[1])
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(sb)
	var pg := HBoxContainer.new()
	b.add_child(pg)
	pg.add_child(_button("FIRE SUPPRESS", func() -> void: InputHub.pulse("fire_suppress"), 24))
	pg.add_child(_button("SCAN PING", func() -> void: InputHub.pulse("scanner_ping"), 24))
	pg.add_child(_button("OPS TRIGGER", func() -> void: InputHub.pulse("ops_trigger"), 24))
	var seal := _button("SEAL LEAK", func() -> void:
		Game.leak_sealed = true
		Sfx.clunk(), 34)
	seal.custom_minimum_size.y = 110
	b.add_child(seal)
	var faults := _label("", 28, C_AMBER)
	b.add_child(faults)
	live["sys"] = func() -> void:
		seal.visible = Game.failures["leak"]
		seal.modulate = C_RED if fmod(Time.get_ticks_msec() / 400.0, 2.0) < 1.0 else Color.WHITE
		var s := ""
		var help := {"fire": "ENGINE FIRE: Pilot ENGINE ARM off, Ops FIRE SUPPRESS", "leak": "CABIN LEAK: press SEAL LEAK", "power": "POWER FAULT: REACTOR off, wait, on", "sensor": "SENSOR GLITCH: SENSORS off, then on"}
		for k in Game.failures:
			if Game.failures[k]:
				s += "⚠ " + str(help[k]) + "\n"
		for k in Game.warnings:
			if not Game.failures.has(k):
				s += "• " + str(Game.warnings[k]) + "\n"
		faults.text = s if s != "" else "All systems nominal ✓"
		faults.add_theme_color_override("font_color", C_AMBER if s != "" else C_GREEN)


# ======================================================================== CHECKLIST
func _build_checklist(page: Control) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	page.add_child(h)
	var a := _panel(h, "OVERHEAD START-UP CHECKLIST  (flip in order, left to right)", true, true)
	a.size_flags_stretch_ratio = 1.5
	var rows: Array = []
	for i in Game.CHECKLIST.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		a.add_child(row)
		var num := _label("%d" % (i + 1), 44, C_EDGE)
		num.custom_minimum_size.x = 60
		row.add_child(num)
		var sb := _switch_button(Game.CHECKLIST[i], Game.CHECKLIST_NAMES[i])
		sb.custom_minimum_size = Vector2(380, 92)
		sb.add_theme_font_size_override("font_size", 32)
		row.add_child(sb)
		var st := _label("", 30)
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(st)
		rows.append(st)
	var b := _panel(h, "CREW", true, true)
	var hint := _label("", 30, C_AMBER)
	b.add_child(hint)
	b.add_child(_button("ALL ON (grown-up shortcut)", func() -> void: Game.auto_checklist(), 24))
	b.add_child(_button("ALL OFF", func() -> void:
		for id in Game.CHECKLIST:
			InputHub.set_switch(id, false), 24))
	var seat := _label("", 26)
	b.add_child(seat)
	live["check"] = func() -> void:
		for i in rows.size():
			var st: Label = rows[i]
			var on := InputHub.on(Game.CHECKLIST[i])
			if Game.seq_ok[i]:
				st.text = "✔ DONE"
				st.add_theme_color_override("font_color", C_GREEN)
			elif on:
				st.text = "✖ OUT OF ORDER - flip it off"
				st.add_theme_color_override("font_color", C_RED)
			elif i == Game.checklist_progress:
				st.text = "◀ NEXT"
				st.add_theme_color_override("font_color", C_AMBER)
			else:
				st.text = ""
		if Game.checklist_progress >= Game.CHECKLIST.size():
			hint.text = "Checklist complete!\nReady for START."
			hint.add_theme_color_override("font_color", C_GREEN)
		else:
			hint.text = "Next switch:\n" + Game.CHECKLIST_NAMES[Game.checklist_progress]
			hint.add_theme_color_override("font_color", C_AMBER)
		seat.text = "Seat sensor: %s\nHarnesses: %s" % ["OCCUPIED" if InputHub.on("seat_up") else "empty / not fitted", "CONFIRMED" if Game.harness_confirmed else "tap on MISSION page"]


# ======================================================================== CAMERAS
func _build_cameras(page: Control) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	page.add_child(h)
	for t: String in ["DOCKING CAMERA", "ARM CAMERA", "CHASE CAMERA"]:
		var p := _panel(h, t, true, true)
		var svc := SubViewportContainer.new()
		svc.stretch = true
		svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		svc.custom_minimum_size = Vector2(400, 400)
		p.add_child(svc)
		var v := SubViewport.new()
		v.render_target_update_mode = SubViewport.UPDATE_DISABLED
		v.msaa_3d = Viewport.MSAA_2X
		v.audio_listener_enable_3d = false
		svc.add_child(v)
		var c := Camera3D.new()
		c.fov = 55.0 if t != "CHASE CAMERA" else 60.0
		c.near = 0.3
		c.far = 2.5e5
		v.add_child(c)
		c.current = true
		_cam_vps.append(v)
		_cam_cams.append(c)
		var ov := CameraOverlay.new()
		ov.kind = t
		ov.set_anchors_preset(Control.PRESET_FULL_RECT)
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(ov)


func _update_cameras() -> void:
	var w: WorldView = get_tree().get_first_node_in_group("world")
	if w == null:
		return
	_cam_cams[0].global_transform = w.docking_cam_xform()
	_cam_cams[1].global_transform = w.arm_cam_xform()
	var sim: ShipSim = Game.sim
	var back := sim.basis * Vector3(0, 6, 34)
	_cam_cams[2].global_transform = Transform3D(Basis.IDENTITY, back).looking_at(Vector3.ZERO, sim.basis.y)


# ======================================================================== CONTROLS TEST
func _build_controls(page: Control) -> void:
	var v := VBoxContainer.new()
	page.add_child(v)
	var dev := _label("", 24)
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
		var l := _label("", 20)
		l.custom_minimum_size = Vector2(590, 34)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.clip_text = true
		g.add_child(l)
		cells[id] = [l, str(a["role"]), str(a["label"]), str(a["type"])]
	var tools := HBoxContainer.new()
	v.add_child(tools)
	tools.add_child(_button("WRITE TEMPLATE input_map.json", func() -> void:
		var p := "user://input_map_template.json"
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f:
			f.store_string(InputHub.export_template())
			Voice.say("Template written to " + ProjectSettings.globalize_path(p)), 22))
	tools.add_child(_button("LED TEST", func() -> void: LedLink.set_all_signals(Color(0, 0.6, 1.0), "PULSE"), 22))
	live["controls"] = func() -> void:
		if current != "CONTROLS":
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
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	page.add_child(h)
	var a := _panel(h, "DISPLAYS", true, true)
	var mode_row := HBoxContainer.new()
	a.add_child(mode_row)
	for m: String in ["auto", "cockpit", "dev"]:
		var mb := _button(m.to_upper(), func() -> void: Settings.set_v("display", "mode", m), 24)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mode_row.add_child(mb)
		live["mode_" + m] = func() -> void: mb.modulate = C_GREEN if Settings.get_v("display", "mode") == m else Color.WHITE
	var screens := _label("", 22)
	a.add_child(screens)
	var roles: Array[String] = []
	if display:
		roles.append_array(display.out_views)
	else:
		roles.append_array(["left", "right"])
	roles.append("console")
	for role: String in roles:
		var row := HBoxContainer.new()
		a.add_child(row)
		var l := _label(role.to_upper() + " screen", 24)
		l.custom_minimum_size.x = 240
		row.add_child(l)
		row.add_child(_button("-", func() -> void: _bump_screen(role, -1), 30))
		var val := _label("", 30, C_GREEN)
		val.custom_minimum_size.x = 80
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(val)
		row.add_child(_button("+", func() -> void: _bump_screen(role, 1), 30))
		row.add_child(_button("IDENTIFY", func() -> void: _identify(role), 22))
		live["scr_" + role] = func() -> void: val.text = str(Settings.get_v("display", role + "_screen"))
	var geo := [["monitor_width_m", "Monitor width m", 0.01], ["monitor_height_m", "Monitor height m", 0.01], ["monitor_gap_m", "Gap between m", 0.01],
		["eye_distance_m", "Eye distance m", 0.02], ["eye_height_m", "Eye height m", 0.02], ["toe_in_deg", "Toe-in deg", 1.0], ["view_scale", "View scale", 0.05]]
	for gdef in geo:
		var row := HBoxContainer.new()
		a.add_child(row)
		var l := _label(str(gdef[1]), 22)
		l.custom_minimum_size.x = 260
		row.add_child(l)
		var key: String = gdef[0]
		var step: float = gdef[2]
		var mb := _button("-", func() -> void: Settings.set_v("display", key, snappedf(float(Settings.get_v("display", key)) - step, 0.001)), 26)
		mb.custom_minimum_size = Vector2(84, 64)
		row.add_child(mb)
		var val := _label("", 24, C_GREEN)
		val.custom_minimum_size.x = 110
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(val)
		var pb := _button("+", func() -> void: Settings.set_v("display", key, snappedf(float(Settings.get_v("display", key)) + step, 0.001)), 26)
		pb.custom_minimum_size = Vector2(84, 64)
		row.add_child(pb)
		live["geo_" + key] = func() -> void: val.text = "%.3f" % float(Settings.get_v("display", key))
	var apply := _button("APPLY WINDOW LAYOUT", func() -> void:
		if display:
			display.apply_layout(), 28)
	a.add_child(apply)
	var b := _panel(h, "GRAPHICS / SOUND / LIGHTS", true, true)
	var qrow := HBoxContainer.new()
	b.add_child(qrow)
	for q in Settings.QUALITY_LEVELS:
		var qb := _button(q.to_upper(), func() -> void: Settings.set_v("graphics", "quality", q), 24)
		qb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qrow.add_child(qb)
		live["q_" + q] = func() -> void: qb.modulate = C_GREEN if Settings.quality() == q else Color.WHITE
	var frow := HBoxContainer.new()
	b.add_child(frow)
	for fps: int in [60, 75, 120, 144]:
		var fb := _button("%d FPS" % fps, func() -> void: Settings.set_v("display", "max_fps", fps), 22)
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frow.add_child(fb)
		live["fps_%d" % fps] = func() -> void: fb.modulate = C_GREEN if int(Settings.get_v("display", "max_fps")) == fps else Color.WHITE
	var vrow := HBoxContainer.new()
	b.add_child(vrow)
	for vm: String in ["mailbox", "fifo", "off"]:
		var vmb := _button("VSYNC " + vm.to_upper(), func() -> void:
			Settings.set_v("display", "vsync", vm)
			if display:
				display.apply_vsync_all(), 20)
		vmb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vrow.add_child(vmb)
		live["vs_" + vm] = func() -> void: vmb.modulate = C_GREEN if str(Settings.get_v("display", "vsync")) == vm else Color.WHITE
	var vb := _button("VOICE CALLOUTS", func() -> void: Settings.set_v("audio", "voice", not bool(Settings.get_v("audio", "voice"))), 24)
	b.add_child(vb)
	var lb := _button("LED PANEL LINK (restart)", func() -> void: Settings.set_v("led", "enabled", not bool(Settings.get_v("led", "enabled"))), 24)
	b.add_child(lb)
	var fsb := _button("FULLSCREEN WINDOWS", func() -> void: Settings.set_v("display", "fullscreen", not bool(Settings.get_v("display", "fullscreen"))), 24)
	b.add_child(fsb)
	var info := _label("", 22)
	b.add_child(info)
	b.add_child(_button("QUIT GAME", func() -> void: get_tree().quit(), 24))
	live["setup"] = func() -> void:
		vb.modulate = C_GREEN if Settings.get_v("audio", "voice") else Color.WHITE
		lb.modulate = C_GREEN if Settings.get_v("led", "enabled") else Color.WHITE
		fsb.modulate = C_GREEN if Settings.get_v("display", "fullscreen") else Color.WHITE
		var s := "Screens detected: %d\n" % DisplayServer.get_screen_count()
		for i in DisplayServer.get_screen_count():
			s += "  #%d  %s @ %.0f Hz at %s\n" % [i, str(DisplayServer.screen_get_size(i)), DisplayServer.screen_get_refresh_rate(i), str(DisplayServer.screen_get_position(i))]
		screens.text = s
		info.text = "FPS: %d (cap %d)\nRunning mode: %s\nVoice: %s\nLED link: %s\nRenderer: %s\nSettings file: %s" % [int(Engine.get_frames_per_second()), Engine.max_fps, display.mode if display else "?", Voice.engine, LedLink.status,
			RenderingServer.get_video_adapter_name(), ProjectSettings.globalize_path(Settings.PATH)]


func _bump_screen(role: String, d: int) -> void:
	var n := maxi(DisplayServer.get_screen_count(), 1)
	Settings.set_v("display", role + "_screen", posmod(int(Settings.get_v("display", role + "_screen")) + d, n))


func _identify(role: String) -> void:
	var scr := int(Settings.get_v("display", role + "_screen"))
	var w := Window.new()
	w.borderless = true
	w.always_on_top = true
	w.size = Vector2i(800, 300)
	w.position = DisplayServer.screen_get_position(scr) + (DisplayServer.screen_get_size(scr) - w.size) / 2
	var l := Label.new()
	l.text = "%s = SCREEN %d" % [role.to_upper(), scr]
	l.add_theme_font_size_override("font_size", 64)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	w.add_child(l)
	get_tree().root.add_child(w)
	get_tree().create_timer(2.5).timeout.connect(w.queue_free)
