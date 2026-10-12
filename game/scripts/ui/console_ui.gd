class_name ConsoleUI
extends FalconPanel
## KIDS' CONSOLE: the TD2220 touchscreen between the two seats. Only the crew's instruments
## and controls live here (grown-up functions are on the Commander screen):
##   FLIGHT     Pilot half: attitude ball, speed + altitude tapes, throttle/fuel, engine, gear,
##              flaps, airbrake, assist. Ops half: RCS/ARM/SCANNER mode, live camera, target,
##              scanner, cargo doors, docking clamp, power switches.
##   NAV        orbit map, STEER TO buttons, NAV TARGET.
##   SYSTEMS    power distribution, ship health bars, faults and how to fix them.
##   CAMERAS    docking, arm and chase cameras.
##   EVA        only during a spacewalk: HELMET CAM, the camera drone, suit telemetry
##              (O2, battery, CO2, suit temperature, heart rate, jet gas, tether) and the task list.
##   CHECKLIST  the overhead start-up switches, in order (the overhead panels are drawn here
##              too while Falcon Command is unplugged).
##   PANELS     only while the Pilot or Ops board is unplugged (or SETUP forces it): that
##              seat's real panels on screen (dash, side console) plus a touch joystick.
## Each kid's task strip has a big TALK pad (intercom push-to-talk; multi-touch).
##   COMMANDER  only when there is no 4th screen: the Commander UI as a tab (also: Escape key).
## Every control here also exists on the hardware; touch buttons are the fallback and mirror
## the real switches when a board is plugged in. Works in landscape (recommended) or portrait.

const PAGES := ["FLIGHT", "NAV", "SYSTEMS", "CAMERAS", "EVA", "CHECKLIST", "PANELS"]

var pages := {}
var tabs := {}
var current := "FLIGHT"
var nav_map: NavMap
var _tabbar: HBoxContainer
var _holder: Control
var _splits: Array[BoxContainer] = []      # flip to vertical in portrait
var _commander_host: Control = null
var _prev_page := "FLIGHT"
var _pending_commander: Control = null
var _virt := {}            # board -> Array[Control] shown while it is missing
var _virt_any := []        # tab button etc.


func _ready() -> void:
	theme = make_theme(26)
	add_background()
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 14
	root.offset_right = -14
	root.offset_top = 10
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	_build_top(root)
	_tabbar = HBoxContainer.new()
	_tabbar.add_theme_constant_override("separation", 8)
	root.add_child(_tabbar)
	_holder = Control.new()
	_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_holder)
	for p in PAGES:
		_add_page(p)
	_build_flight(pages["FLIGHT"])
	_build_nav(pages["NAV"])
	_build_systems(pages["SYSTEMS"])
	_build_cameras(pages["CAMERAS"])
	_build_eva(pages["EVA"])
	_build_checklist(pages["CHECKLIST"])
	_build_panels(pages["PANELS"])
	show_page("FLIGHT")
	InputHub.devices_changed.connect(update_virtual)
	Settings.changed.connect(func(sec: String) -> void:
		if sec == "input":
			update_virtual())
	update_virtual()
	Eva.changed.connect(_update_eva_tab)
	_update_eva_tab()
	resized.connect(_on_resized)
	_on_resized()
	if _pending_commander:
		var pc := _pending_commander
		_pending_commander = null
		embed_commander(pc)


func _add_page(p: String) -> MarginContainer:
	var b := button(p, func() -> void: show_page(p), 30, 76)
	b.toggle_mode = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabbar.add_child(b)
	tabs[p] = b
	var page := MarginContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.visible = false
	_holder.add_child(page)
	pages[p] = page
	return page


func show_page(p: String) -> void:
	if not pages.has(p):
		return
	if p != current:
		_prev_page = current
	current = p
	for k in pages:
		(pages[k] as Control).visible = (k == p)
		(tabs[k] as Button).set_pressed_no_signal(k == p)
	refresh()


## Three-screen setups: the Commander UI becomes a tab here (and the Escape key toggles it).
func embed_commander(c: Control) -> void:
	if not is_node_ready():
		_pending_commander = c      # the layout is built before the console enters the tree
		return
	if _commander_host == null:
		_commander_host = _add_page("COMMANDER")
		(tabs["COMMANDER"] as Button).text = "⚙ COMMANDER"
		(tabs["COMMANDER"] as Button).size_flags_stretch_ratio = 0.8
	if c.get_parent():
		c.get_parent().remove_child(c)
	_commander_host.add_child(c)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	if not _commander_host.resized.is_connected(_fit_commander):
		_commander_host.resized.connect(_fit_commander)
	_fit_commander()


## The Commander normally renders at a fixed 1920x1080 and is stretched to its window. The tab is
## smaller and not 16:9, so lay it out 1080 high at the tab's aspect ratio: uniform scale, nothing cut off.
func _fit_commander() -> void:
	if _commander_host == null:
		return
	var hs := _commander_host.size
	if hs.x < 1.0 or hs.y < 1.0:
		return
	var h := maxf(1080.0, hs.y)
	for ch in _commander_host.get_children():
		_set_commander_override(ch, Vector2i(roundi(hs.x * h / hs.y), roundi(h)))


static func _set_commander_override(c: Node, sz: Vector2i) -> void:
	for ch in c.get_children():
		if ch is SubViewport:
			(ch as SubViewport).size_2d_override = sz


func release_commander() -> void:
	_pending_commander = null
	if _commander_host == null:
		return
	if current == "COMMANDER":
		show_page("FLIGHT")
	for ch in _commander_host.get_children():
		_set_commander_override(ch, Vector2i(1920, 1080))
		_commander_host.remove_child(ch)
	pages.erase("COMMANDER")
	(tabs["COMMANDER"] as Button).queue_free()
	tabs.erase("COMMANDER")
	_commander_host.queue_free()
	_commander_host = null


func has_commander_tab() -> bool:
	return _commander_host != null


func toggle_commander() -> void:
	if _commander_host == null:
		return
	show_page(_prev_page if current == "COMMANDER" else "COMMANDER")


func is_portrait() -> bool:
	return size.y > size.x * 1.05


func _on_resized() -> void:
	var portrait := is_portrait()
	for s in _splits:
		s.vertical = portrait


func _split(parent: Control) -> BoxContainer:
	var b := BoxContainer.new()
	b.add_theme_constant_override("separation", 12)
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	_splits.append(b)
	return b


# ======================================================================== top bar + crew tasks
func _build_top(root: VBoxContainer) -> void:
	var top := hbox(root, 12)
	var logo := label("FILAMENT FALCON", 32, C_EDGE, false)
	top.add_child(logo)
	var title := label("", 30, C_TEXT, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)
	var caution := label("", 30, C_RED, false)
	top.add_child(caution)
	var clock := label("", 30, C_GREEN, false)
	top.add_child(clock)
	var tasks := hbox(root, 12)
	var pp := panel(tasks, "", true, false)
	var ph := hbox(pp, 10)
	var pl := label("", 28, C_PILOT)
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(pl)
	ph.add_child(_talk_pad("pilot", C_PILOT))
	var op := panel(tasks, "", true, false)
	var oh := hbox(op, 10)
	oh.add_child(_talk_pad("ops", C_OPS))
	var ol := label("", 28, C_OPS)
	ol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oh.add_child(ol)
	for l: Label in [pl, ol]:
		l.custom_minimum_size.y = 66
		l.max_lines_visible = 2
	live["top"] = func() -> void:
		var m: Mission = Game.mission
		if m == null:
			return
		var tm := int(Game.mission_time)
		title.text = m.title
		clock.text = "%s  T+%d:%02d" % [Game.STATE_NAMES[Game.state], tm / 60, tm % 60]
		var blink := fmod(Time.get_ticks_msec() / 400.0, 2.0) < 1.0
		caution.text = "⚠ MASTER CAUTION" if Game.caution_active and blink else ""
		var o := m.current_objective()
		var role := str(o.get("role", ""))
		var txt := str(o.get("text", ""))
		match Game.state:
			Game.State.BRIEFING:
				pl.text = "PILOT ▸ Get ready! " + m.pilot_job
				ol.text = "OPS ▸ Get ready! " + m.ops_job
			Game.State.PAUSED:
				pl.text = "PILOT ▸ Paused. Wait for the Commander."
				ol.text = "OPS ▸ Paused. Wait for the Commander."
			Game.State.COMPLETE:
				pl.text = "PILOT ▸ Mission complete! Great flying!"
				ol.text = "OPS ▸ Mission complete! Great work!"
			Game.State.FAILED:
				pl.text = "PILOT ▸ " + Game.result_text
				ol.text = "OPS ▸ Ask the Commander to fly again."
			_:
				pl.text = "PILOT ▸ " + (txt if role in ["PILOT", "BOTH", "ALL"] else "Hold steady while Ops works.")
				ol.text = "OPS ▸ " + (txt if role in ["OPS", "BOTH", "ALL"] else "Watch the screens and help the Pilot.")
		pl.modulate = Color.WHITE if role in ["PILOT", "BOTH", "ALL"] or Game.state != Game.State.ACTIVE else Color(1, 1, 1, 0.55)
		ol.modulate = Color.WHITE if role in ["OPS", "BOTH", "ALL"] or Game.state != Game.State.ACTIVE else Color(1, 1, 1, 0.55)


## Intercom push-to-talk for one kid (works in VOX mode too: holding it forces the mic open).
func _talk_pad(seat: String, col: Color) -> HoldPad:
	var hp := ptt_pad(seat, "TALK", "", col)
	hp.custom_minimum_size = Vector2(170, 76)
	hp.font_size = 28
	live["talk_" + seat] = func() -> void:
		var vox := str(Settings.get_v("ics", seat + "_mode")) == "vox"
		hp.sub = ("ON AIR" if Ics.keyed(seat) else ("voice on" if vox else "hold")) if Ics.ok() else "no intercom"
		hp.modulate = Color.WHITE if Ics.ok() or not Ics.enabled else Color(1, 1, 1, 0.6)
	return hp


# ======================================================================== PANELS (virtual hardware)
func _build_panels(page: Control) -> void:
	var sp := _split(page)
	for seat: Array in [[InputHub.DEV_PILOT, "PILOT", C_PILOT, ["PILOT_DASH_A", "PILOT_DASH_B"], "PILOT_SIDE", "pilot"],
			[InputHub.DEV_OPS, "OPS", C_OPS, ["OPS_DASH_A", "OPS_DASH_B"], "OPS_SIDE", "ops"]]:
		var col := panel(sp, "%s PANELS  (board not plugged in: touch these)" % seat[1], true, true, seat[2])
		var dash := hbox(col, 8)
		dash.size_flags_vertical = Control.SIZE_EXPAND_FILL
		for id: String in seat[3]:
			var vp := VirtualPanel.make(id)
			dash.add_child(vp)
		var low := hbox(col, 8)
		low.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var side := VirtualPanel.make(str(seat[4]))
		low.add_child(side)
		var st := VirtualStick.new()
		st.seat = str(seat[5])
		st.color = seat[2]
		low.add_child(st)
		_virt[seat[0]] = [col.get_parent()]


## Show / hide the on-screen panels for unplugged boards (hot-plug, or SETUP forcing them).
func update_virtual() -> void:
	if not is_node_ready():
		return
	var any := false
	for dev: String in _virt:
		var need := InputHub.virtual_needed(dev)
		for c: Control in _virt[dev]:
			c.visible = need
		any = any or (dev != InputHub.DEV_CMD and need)
	var tb: Button = tabs["PANELS"]
	tb.visible = any
	tb.text = "PANELS ●" if any and not bool(Settings.get_v("input", "force_virtual_panels")) else "PANELS"
	tb.modulate = C_AMBER if any and not bool(Settings.get_v("input", "force_virtual_panels")) else Color.WHITE
	if not any and current == "PANELS":
		show_page("FLIGHT")


# ======================================================================== FLIGHT
func _build_flight(page: Control) -> void:
	var sp := _split(page)
	# ---- PILOT half
	var p := panel(sp, "PILOT", true, true, C_PILOT)
	p.get_parent().size_flags_stretch_ratio = 1.1
	var inst := hbox(p, 8)
	inst.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var spd := TapeGauge.new()
	spd.title = "SPEED m/s"
	spd.unit = "m/s"
	spd.getter = func() -> Array:
		var s: ShipSim = Game.sim
		var v := s.surface_vel.length() if s.altitude < 70000.0 else (s.vel - (s.dominant.vel if s.dominant else Vector3.ZERO)).length()
		return [v, "%d" % int(v), C_GREEN]
	spd.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inst.add_child(spd)
	var adi := AdiGauge.new()
	adi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	adi.size_flags_vertical = Control.SIZE_EXPAND_FILL
	adi.custom_minimum_size = Vector2(320, 280)
	inst.add_child(adi)
	var alt := TapeGauge.new()
	alt.title = "ALTITUDE"
	alt.unit = "m"
	alt.getter = func() -> Array:
		var s: ShipSim = Game.sim
		return [s.altitude, Hud._fmt_dist(s.altitude), C_GREEN if s.agl > 300.0 or s.vspeed > -5.0 else C_AMBER]
	alt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inst.add_child(alt)
	var rd := label("", 26, C_TEXT, false)
	rd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(rd)
	bar(p, "THROTTLE", "f_thr", func() -> Array:
		var s: ShipSim = Game.sim
		return [s.throttle, "%d%%%s" % [int(s.throttle * 100.0), " BOOST" if s.boost else ""], C_AMBER if s.engine_on else C_DIM], 170)
	bar(p, "FUEL", "f_fuel", func() -> Array:
		var s: ShipSim = Game.sim
		if s.booster_attached:
			return [s.booster_fuel / s.booster_fuel_max, "BOOSTER %d%%" % int(s.booster_fuel / s.booster_fuel_max * 100.0), C_AMBER]
		return [s.fuel / s.fuel_max, "%d kg" % int(s.fuel), C_GREEN if s.fuel > 1500.0 else C_RED], 170)
	var r1 := hbox(p, 8)
	for b: Button in [switch_button("engine_arm", "ENGINE ARM", 26, 84), pulse_button("ignition", "IGNITION", 26, 84), switch_button("gear", "GEAR DOWN", 26, 84), switch_button("airbrake", "AIRBRAKE", 26, 84)]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r1.add_child(b)
	var r2 := hbox(p, 8)
	r2.add_child(label("FLAPS", 22, C_DIM, false))
	for fl: Array in [["UP", true, false], ["HALF", false, false], ["DOWN", false, true]]:
		var fu: bool = fl[1]
		var fd: bool = fl[2]
		var fb := button(str(fl[0]), func() -> void:
			if not InputHub.has_hardware_for("flaps_up"):
				InputHub.set_switch("flaps_up", fu)
				InputHub.set_switch("flaps_down", fd)
				Sfx.click(), 24, 76)
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r2.add_child(fb)
		live["flap_" + str(fl[0])] = func() -> void:
			var on := InputHub.on("flaps_up") == fu and InputHub.on("flaps_down") == fd
			fb.modulate = C_GREEN if on else Color.WHITE
			fb.disabled = InputHub.has_hardware_for("flaps_up")
	var r3 := hbox(p, 8)
	r3.add_child(label("ASSIST", 22, C_DIM, false))
	group_buttons(r3, "fa", ShipSim.FA_NAMES, 22, 76)
	live["f_read"] = func() -> void:
		var s: ShipSim = Game.sim
		var eng := "ENGINE ON" if s.engine_on else ("ARMED" if InputHub.on("engine_arm") else "ENGINE OFF")
		rd.text = "CLIMB %+d m/s    G %.1f    %s    GEAR %s" % [int(s.vspeed), s.g_load, eng, "DOWN" if s.gear_down else "UP"]
	# ---- OPS half
	var o := panel(sp, "OPS", true, true, C_OPS)
	var mr := hbox(o, 8)
	mr.add_child(label("MODE", 22, C_DIM, false))
	group_buttons(mr, "ops", Game.OPS_MODES, 26, 80)
	var cam := CamFeedView.new()
	cam.kind = "AUTO"
	cam.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cam.custom_minimum_size = Vector2(400, 200)
	o.add_child(cam)
	var tg := hbox(o, 8)
	var tl := label("", 24, C_TEXT)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tg.add_child(tl)
	var nt := pulse_button("nav_target", "NAV TARGET ▶", 26, 76)
	nt.custom_minimum_size.x = 260
	tg.add_child(nt)
	var oa := hbox(o, 8)
	for b: Button in [pulse_button("scanner_ping", "SCANNER PING", 24, 84), pulse_button("ops_trigger", "TRIGGER", 24, 84), switch_button("cargo_doors", "CARGO DOORS", 24, 84), switch_button("dock_clamp", "DOCK CLAMP", 24, 84)]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		oa.add_child(b)
	var pw := hbox(o, 8)
	for pair: Array in [["pwr_reactor", "REACTOR"], ["pwr_life", "LIFE SUP"], ["pwr_shields", "SHIELDS"], ["pwr_comms", "COMMS"], ["pwr_sensors", "SENSORS"]]:
		var b := switch_button(pair[0], pair[1], 22, 76)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pw.add_child(b)
	live["o_tgt"] = func() -> void:
		tl.text = _target_text()


func _target_text() -> String:
	var tgt: Dictionary = Game.current_target()
	if tgt.is_empty():
		return "TARGET: none"
	var sim: ShipSim = Game.sim
	var ts: Array = Game.target_state()
	var rel: Vector3 = (ts[0] as BigVec).rel(sim.pos)
	var s := "TARGET: %s\n%s away, %.1f m/s" % [str(tgt["name"]), Hud._fmt_dist(rel.length()), (sim.vel - (ts[1] as Vector3)).length()]
	var gd: Dictionary = Game.mission.guidance if Game.mission else {}
	if gd.has("docking") and str(tgt["name"]).contains("PORT"):
		var info: Dictionary = gd["docking"]
		s = "PORT: %.1f m   SIDEWAYS %.1f m   CLOSING %.2f m/s" % [float(info["range"]), (info["lat"] as Vector2).length(), float(info["closing"])]
	return s


# ======================================================================== NAV
func _build_nav(page: Control) -> void:
	var sp := _split(page)
	var mp := panel(sp, "WHERE ARE WE?", true, true)
	mp.get_parent().size_flags_stretch_ratio = 1.3
	nav_map = NavMap.new()
	nav_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_map.custom_minimum_size = Vector2(500, 420)
	mp.add_child(nav_map)
	var zr := hbox(mp, 8)
	for zz: Array in [["ZOOM -", 1.0 / 1.6], ["ZOOM +", 1.6], ["RESET", 0.0]]:
		var f: float = zz[1]
		var zb := button(str(zz[0]), func() -> void:
			nav_map.zoom = 1.0 if f == 0.0 else clampf(nav_map.zoom * f, 0.2, 40.0), 26, 84)
		zb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		zr.add_child(zb)
	var r := panel(sp, "NAVIGATION", true, true)
	var info := label("", 28)
	r.add_child(info)
	r.add_child(label("PILOT: STEER TO (assist PROGRADE)", 22, C_PILOT))
	var vg := grid(r, 2, 8)
	var vbtn := {}
	for nv: String in Game.NAV_VECTORS:
		var b := button(nv, func() -> void:
			Game.nav_vector = nv
			Voice.say("Steering to " + nv.to_lower())
			Sfx.click(), 26, 90)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vg.add_child(b)
		vbtn[nv] = b
	r.add_child(label("OPS: TARGET", 22, C_OPS))
	var tr := hbox(r, 8)
	var nb := pulse_button("nav_target", "NAV TARGET ▶", 28, 96)
	nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.add_child(nb)
	var tl := label("", 24)
	r.add_child(tl)
	live["nav"] = func() -> void:
		var sim: ShipSim = Game.sim
		var dom: CelestialBody = sim.dominant
		if dom == null:
			return
		var orb := Hud.orbit_strings(sim)
		var s := "Near: %s   %s\nHeight: %s   Speed: %d m/s\n" % [dom.display_name, orb[0], Hud._fmt_dist(sim.altitude), int((sim.vel - dom.vel).length())]
		if orb[0] == "ON THE GROUND":
			s += "Highest / lowest point: ---\n(no orbit yet: we need about 2,400 m/s sideways)"
		else:
			s += "Highest point (Ap): %s\nLowest point (Pe): %s" % [orb[1], orb[2]]
		info.text = s
		tl.text = _target_text()
		for k in vbtn:
			(vbtn[k] as Button).modulate = C_GREEN if k == Game.nav_vector else Color.WHITE


# ======================================================================== SYSTEMS
func _build_systems(page: Control) -> void:
	var sp := _split(page)
	var a := panel(sp, "POWER DISTRIBUTION (Ops)", true, true, C_OPS)
	bar(a, "POWER USE", "b_pwr", func() -> Array:
		return [Game.power_draw / maxf(Game.power_avail, 1.0), "%d/%d kW" % [int(Game.power_draw), int(Game.power_avail)], C_GREEN if Game.power_ok else C_RED])
	bar(a, "REACTOR", "b_rea", func() -> Array:
		return [Game.reactor_out / 100.0, "%d%%" % int(Game.reactor_out), C_GREEN if Game.reactor_out > 90.0 else C_AMBER])
	var g := grid(a, 3, 10)
	for pair: Array in [["pwr_reactor", "REACTOR"], ["pwr_life", "LIFE SUPPORT"], ["pwr_shields", "SHIELDS"], ["pwr_comms", "COMMS"], ["pwr_sensors", "SENSORS"], ["cargo_doors", "CARGO DOORS"], ["jump_arm", "JUMP ARM"], ["dock_clamp", "DOCK CLAMP"]]:
		var b := switch_button(pair[0], pair[1], 24, 100)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(b)
	var jb := pulse_button("jump_engage", "JUMP ENGAGE", 24, 100)
	jb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(jb)
	var fr := hbox(a, 10)
	for b: Button in [pulse_button("fire_suppress", "FIRE SUPPRESS", 26, 100)]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fr.add_child(b)
	var seal := button("SEAL LEAK", func() -> void:
		Game.leak_sealed = true
		Sfx.clunk(), 32, 100)
	seal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fr.add_child(seal)
	var b2 := panel(sp, "SHIP HEALTH", true, true)
	bar(b2, "FUEL", "b_fuel", func() -> Array:
		var s: ShipSim = Game.sim
		return [s.fuel / s.fuel_max, "%d kg" % int(s.fuel), C_GREEN if s.fuel > 1500.0 else C_RED])
	bar(b2, "RCS FUEL", "b_mono", func() -> Array:
		var s: ShipSim = Game.sim
		return [s.mono / s.mono_max, "%d kg" % int(s.mono), C_EDGE])
	bar(b2, "OXYGEN", "b_o2", func() -> Array:
		return [Game.o2 / 100.0, "%d%%" % int(Game.o2), C_GREEN if Game.o2 > 60.0 else C_RED])
	bar(b2, "CABIN AIR", "b_cab", func() -> Array:
		return [Game.cabin_kpa / 101.0, "%d kPa" % int(Game.cabin_kpa), C_GREEN if Game.cabin_kpa > 80.0 else C_RED])
	bar(b2, "HULL", "b_hull", func() -> Array:
		return [Game.hull / 100.0, "%d%%" % int(Game.hull), C_GREEN if Game.hull > 50.0 else C_RED])
	bar(b2, "HULL HEAT", "b_temp", func() -> Array:
		var s: ShipSim = Game.sim
		return [(s.hull_temp - 250.0) / 1400.0, "%d K" % int(s.hull_temp), C_GREEN if s.hull_temp < 900.0 else (C_AMBER if s.hull_temp < 1400.0 else C_RED)])
	bar(b2, "JUMP DRIVE", "b_jump", func() -> Array:
		return [Game.jump_charge / 100.0, "%d%%" % int(Game.jump_charge), Color(0.75, 0.5, 1.0)])
	var faults := label("", 28, C_AMBER)
	b2.add_child(faults)
	live["sys"] = func() -> void:
		seal.visible = Game.failures["leak"]
		seal.modulate = C_RED if fmod(Time.get_ticks_msec() / 400.0, 2.0) < 1.0 else Color.WHITE
		var s := ""
		for k in Game.failures:
			if Game.failures[k]:
				s += "⚠ " + fault_help(k) + "\n"
		for k in Game.warnings:
			if not Game.failures.has(k):
				s += "• " + str(Game.warnings[k]) + "\n"
		faults.text = s if s != "" else "All systems OK ✓"
		faults.add_theme_color_override("font_color", C_AMBER if s != "" else C_GREEN)


static func fault_help(k: String) -> String:
	return str({"fire": "ENGINE FIRE: Pilot ENGINE ARM off, Ops FIRE SUPPRESS", "leak": "CABIN LEAK: Ops press SEAL LEAK",
		"power": "POWER FAULT: Ops REACTOR off, wait, on", "sensor": "SENSOR GLITCH: Ops SENSORS off, then on"}.get(k, k.to_upper()))


# ======================================================================== CAMERAS
func _build_cameras(page: Control) -> void:
	var sp := _split(page)
	for t: String in ["DOCKING CAMERA", "ARM CAMERA", "CHASE CAMERA"]:
		var p := panel(sp, t, true, true)
		var f := CamFeedView.new()
		f.kind = t
		f.size_flags_vertical = Control.SIZE_EXPAND_FILL
		f.custom_minimum_size = Vector2(300, 260)
		p.add_child(f)


# ======================================================================== EVA
func _build_eva(page: Control) -> void:
	var sp := _split(page)
	var a := panel(sp, "HELMET CAM", true, true, Color(1.0, 0.85, 0.4))
	var hf := CamFeedView.new()
	hf.kind = "HELMET CAM"
	hf.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hf.custom_minimum_size = Vector2(300, 300)
	a.add_child(hf)
	var df := CamFeedView.new()
	df.kind = "EVA DRONE"
	df.size_flags_vertical = Control.SIZE_EXPAND_FILL
	df.custom_minimum_size = Vector2(300, 220)
	a.add_child(df)
	var b := panel(sp, "SUIT TELEMETRY", true, true, Color(1.0, 0.85, 0.4))
	var tl := func(k: String) -> float:
		return float(Eva.telemetry().get(k, 0.0))
	bar(b, "OXYGEN", "e_o2", func() -> Array:
		var v: float = tl.call("o2")
		return [v / 100.0, "%d%%" % int(v), C_GREEN if v > 40.0 else (C_AMBER if v > 20.0 else C_RED)])
	bar(b, "BATTERY", "e_bat", func() -> Array:
		var v: float = tl.call("batt")
		return [v / 100.0, "%d%%" % int(v), C_GREEN if v > 30.0 else C_AMBER])
	bar(b, "CO2", "e_co2", func() -> Array:
		var v: float = tl.call("co2")
		return [v / 8.0, "%.1f mmHg" % v, C_GREEN if v < 4.0 else (C_AMBER if v < 6.0 else C_RED)])
	bar(b, "SUIT TEMP", "e_tmp", func() -> Array:
		var v: float = tl.call("temp")
		return [(v - 10.0) / 25.0, "%.1f °C" % v, C_GREEN if absf(v - 21.0) < 5.0 else C_AMBER])
	bar(b, "HEART RATE", "e_hr", func() -> Array:
		var v: float = tl.call("hr")
		return [(v - 50.0) / 110.0, "%d bpm %s" % [int(v), "♥" if fmod(Time.get_ticks_msec() / 1000.0 * v / 60.0, 1.0) < 0.3 else ""], C_GREEN if v < 130.0 else C_AMBER])
	bar(b, "JET GAS", "e_gas", func() -> Array:
		var v: float = tl.call("gas")
		return [v / 100.0, "%d%%" % int(v), C_EDGE])
	bar(b, "TETHER", "e_teth", func() -> Array:
		var t := Eva.telemetry()
		var used := float(t.get("tether", 0.0))
		var ln := maxf(float(t.get("tether_len", 20.0)), 1.0)
		if not bool(t.get("tether_on", true)):
			return [0.0, "none (Moon)", C_EDGE]
		return [used / ln, "%.1f / %d m" % [used, int(ln)], C_GREEN if used < ln * 0.85 else C_AMBER])
	var tasks := label("", 26, C_TEXT)
	tasks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tasks.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_child(tasks)
	live["eva"] = func() -> void:
		tasks.text = eva_task_text()


static func eva_task_text() -> String:
	if Eva.sim == null:
		return "Nobody outside."
	var sim: EvaSim = Eva.sim
	var s := "%s  ·  %s\n" % [str(Eva.scen.get("title", "")), "VR HEADSET" if Eva.driver == "vr" else "ON SCREEN"]
	for i in sim.steps.size():
		var mark := "✓" if i < sim.step else ("▶" if i == sim.step else "·")
		s += "%s %s\n" % [mark, str((sim.steps[i] as Dictionary).get("text", ""))]
	if not Eva.active and Eva.result_text != "":
		s += "\n" + Eva.result_text
	return s


func _update_eva_tab() -> void:
	if not tabs.has("EVA"):
		return
	var tb: Button = tabs["EVA"]
	tb.visible = Eva.active or current == "EVA"
	tb.text = "EVA ●" if Eva.active else "EVA"
	tb.modulate = Color(1.0, 0.85, 0.4) if Eva.active else Color.WHITE


# ======================================================================== CHECKLIST
func _build_checklist(page: Control) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	page.add_child(v)
	# the overhead consoles, on screen while Falcon Command (which reads them) is unplugged
	var ovh := hbox(v, 8)
	ovh.custom_minimum_size.y = 250
	for id: String in ["OVERHEAD_A", "OVERHEAD_B", "OVERHEAD_C"]:
		ovh.add_child(VirtualPanel.make(id))
	_virt[InputHub.DEV_CMD] = [ovh]
	var sp := _split(v)
	var a := panel(sp, "OVERHEAD START-UP CHECKLIST  (flip the switches in order)", true, true)
	a.get_parent().size_flags_stretch_ratio = 1.6
	var rows: Array = []
	var btns: Array[Button] = []
	for i in Game.CHECKLIST.size():
		var row := hbox(a, 12)
		var num := label("%d" % (i + 1), 44, C_EDGE, false)
		num.custom_minimum_size.x = 56
		row.add_child(num)
		var b := switch_button(Game.CHECKLIST[i], Game.CHECKLIST_NAMES[i], 32, 92)
		b.custom_minimum_size.x = 380
		row.add_child(b)
		btns.append(b)
		var st := label("", 30, C_TEXT, false)
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(st)
		rows.append(st)
	var b2 := panel(sp, "CREW", true, true)
	var hint := label("", 34, C_AMBER)
	b2.add_child(hint)
	var seat := label("", 26)
	b2.add_child(seat)
	live["check"] = func() -> void:
		var compact := ovh.visible
		for b: Button in btns:
			b.custom_minimum_size.y = 58 if compact else 92
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
			hint.text = "Checklist complete!\nTell the Commander you're ready."
			hint.add_theme_color_override("font_color", C_GREEN)
		else:
			hint.text = "Next switch:\n" + Game.CHECKLIST_NAMES[Game.checklist_progress]
			hint.add_theme_color_override("font_color", C_AMBER)
		seat.text = "Master power: %s\nHarnesses: %s" % ["ON" if Game.master_power else "OFF (Commander's key)", "CHECKED ✓" if Game.harness_confirmed else "Commander will check"]
