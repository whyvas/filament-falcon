class_name CommanderUI
extends FalconPanel
## COMMANDER screen (the grown-up's monitor; mouse and keyboard, no touch needed).
##   MISSIONS         every mission, spacewalk and destination by category: patch, illustrated
##                    diagram, objective, crew roles, difficulty, duration, Commander injects,
##                    START (+ Captain's Log playback).
##   MISSION CONTROL  current mission, START/PAUSE/RESTART, harness check, orbit map, live
##                    telemetry, crew status with both kids' current tasks, ship health,
##                    faults, MASTER CAUTION RESET, failure injection, live score.
##   BRIEFING         the full briefing, crew jobs, objectives, Commander tips.
##   TRAINING         difficulty, checklist shortcuts, failure injection, time warp, voice.
##   CONTROLS         live test of every switch, axis and button, devices, LEDs.
##   PANEL            the Falcon Command panels on screen (virtual while the board is
##                    unplugged, a live mirror when it is), ALL-CALL, sense test switches.
##   ICS              intercom: headsets per seat, VOX/PTT, levels, volumes, radio effect.
##   EVA              spacewalks: pick one, START / ABORT, VR client (Quest 3 via WiVRn) or the
##                    on-screen spacewalk (keyboard / mouse / gamepad), comfort settings,
##                    suit telemetry and the task list.
##   SETUP            which screen is which (4 roles), headsets, virtual panels, layout
##                    mode, quality, FPS cap, vsync.
## Top bar: board status (PILOT / OPS / CMD: plugged in or VIRTUAL), crew position (pod and
## seats, from the read-only senses) and intercom state.
## On a 3-screen rig this whole UI is a tab on the kids' console (Escape toggles it).

const PAGES := ["MISSIONS", "MISSION CONTROL", "BRIEFING", "TRAINING", "CONTROLS", "PANEL", "ICS", "EVA", "SETUP"]
const SEAT_COL := {"pilot": FalconPanel.C_PILOT, "ops": FalconPanel.C_OPS, "commander": FalconPanel.C_AMBER, "eva": Color(1.0, 0.85, 0.4)}
const C_EVA := Color(1.0, 0.85, 0.4)

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
	status.clip_text = true
	status.custom_minimum_size.x = 200
	top.add_child(status)
	var quit := button("QUIT GAME", func() -> void: pass, 18, 40)
	quit.pressed.connect(func() -> void:
		if _now() - _quit_armed < 4.0:
			Game.quit_game()
		else:
			_quit_armed = _now()
			refresh())
	top.add_child(quit)
	live["quit"] = func() -> void:
		var armed := _now() - _quit_armed < 4.0
		quit.text = "CONFIRM QUIT?" if armed else "QUIT GAME"
		quit.modulate = C_RED if armed else Color(1, 1, 1, 0.8)
	live["status"] = func() -> void:
		var m: Mission = Game.mission
		var tm := int(Game.mission_time)
		status.text = "%s   %s   T+%d:%02d   %s%s" % [m.title if m else "", Game.STATE_NAMES[Game.state], tm / 60, tm % 60,
			("WARP x%d   " % int(Game.warp)) if Game.warp > 1.0 else "", Game.difficulty().to_upper()]
	var ind := hbox(root, 8)
	_build_indicators(ind)
	var tabbar := hbox(root, 8)
	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(holder)
	for p in PAGES:
		var b := button(p, func() -> void: show_page(p), 22, 60)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # 9 tabs: long names wrap on 1280 px screens
		b.custom_minimum_size.x = 90
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabbar.add_child(b)
		tabs[p] = b
		# every page scrolls when its content is taller than the screen (nothing ends up off-screen)
		var sc := ScrollContainer.new()
		sc.set_anchors_preset(Control.PRESET_FULL_RECT)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO   # too-wide pages scroll sideways instead of pushing off-screen
		sc.visible = false
		holder.add_child(sc)
		var page := MarginContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.add_child(page)
		pages[p] = page
	_build_missions(pages["MISSIONS"])
	_build_control(pages["MISSION CONTROL"])
	_build_briefing(pages["BRIEFING"])
	_build_training(pages["TRAINING"])
	_build_controls(pages["CONTROLS"])
	_build_panel(pages["PANEL"])
	_build_ics(pages["ICS"])
	_build_eva(pages["EVA"])
	_build_setup(pages["SETUP"])
	show_page("MISSIONS")


func show_page(p: String) -> void:
	if not pages.has(p):
		return
	current = p
	for k in pages:
		(pages[k] as Control).get_parent().visible = (k == p)
		(tabs[k] as Button).set_pressed_no_signal(k == p)
	refresh()


# ======================================================================== top-bar status
func _chip(parent: Control) -> Label:
	var l := label("", 20, C_TEXT, false)
	l.add_theme_stylebox_override("normal", sb(Color(0.03, 0.06, 0.1), C_EDGE * 0.5, 2, 8))
	parent.add_child(l)
	return l


func _build_indicators(top: HBoxContainer) -> void:
	top.add_child(label("STATUS", 18, C_DIM, false))
	var chips := {}
	for dev: String in InputHub.BOARDS:
		chips[dev] = _chip(top)
	var pod := _chip(top)
	var ics := _chip(top)
	var evab := button("", func() -> void: show_page("EVA"), 18, 36)
	top.add_child(evab)
	live["eva_chip"] = func() -> void:
		if Eva.active:
			evab.text = "EVA: OUTSIDE (%s) %d%% O2" % ["VR" if Eva.driver == "vr" else "SCREEN", int(Eva.telemetry().get("o2", 0))]
			evab.modulate = C_EVA
		else:
			evab.text = "SPACEWALK%s ▶" % (" · VR ✔" if Eva.client_has_xr() else "")
			evab.modulate = Color.WHITE if not Eva.available().is_empty() else C_DIM
	live["indicators"] = func() -> void:
		for dev: String in chips:
			var l: Label = chips[dev]
			var short := dev.replace("Falcon ", "").to_upper().replace("COMMAND", "CMD")
			if InputHub.device_connected(dev):
				l.text = "%s ✔" % short
				l.add_theme_color_override("font_color", C_GREEN)
			else:
				l.text = "%s: VIRTUAL" % short
				l.add_theme_color_override("font_color", C_AMBER)
		pod.text = "POD %s · SEATS %s" % [Game.pod.pod_text(), Game.pod.seats_text()]
		var moving := Game.pod.pod == PodMonitor.Pod.MOVING or Game.pod.seats == PodMonitor.Seats.MOVING
		pod.add_theme_color_override("font_color", C_AMBER if moving else (C_GREEN if Game.pod.pod == PodMonitor.Pod.DOWN_LOCKED else C_TEXT))
		ics.text = "ICS " + _ics_short()
		ics.add_theme_color_override("font_color", C_GREEN if Ics.ok() else (C_AMBER if Ics.enabled else C_DIM))


func _ics_short() -> String:
	if not Ics.connected():
		return "OFF" if not Ics.enabled else "…"
	if not Ics.ok():
		return "ERROR"
	var on := []
	for s: String in Ics.SEATS:
		if Ics.keyed(s):
			on.append(Ics.SEAT_NAMES[s])
	if Ics.status.get("allcall", false):
		return "ALL-CALL"
	return ("ON AIR: " + ",".join(on)) if not on.is_empty() else "OK"


## Crew position + intercom box (MISSION CONTROL right column; meters and settings on ICS).
func _build_crew_ics(parent: Control) -> void:
	var ip := panel(parent, "", true, false, C_AMBER)
	var cpl := label("", 20, C_TEXT, false)
	ip.add_child(cpl)
	live["mc_pod"] = func() -> void:
		var p: PodMonitor = Game.pod
		cpl.text = "CREW POSITION   POD %s · SEATS %s" % [p.pod_text(), p.seats_text()]
		cpl.add_theme_color_override("font_color", C_AMBER if p.pod == PodMonitor.Pod.MOVING or p.seats == PodMonitor.Seats.MOVING else C_TEXT)
	var r := hbox(ip, 8)
	var talk := ptt_pad("commander", "TALK", "hold ( ` )", C_AMBER)
	talk.custom_minimum_size = Vector2(110, 64)
	talk.font_size = 24
	talk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(talk)
	var ac := HoldPad.new()
	ac.text = "ALL-CALL"
	ac.sub = "hold ( ' )"
	ac.color = C_RED
	ac.font_size = 24
	ac.custom_minimum_size = Vector2(110, 64)
	ac.lit = func() -> bool: return bool(Ics.status.get("allcall", false))
	ac.held.connect(func(d: bool) -> void: Ics.touch_allcall = d)
	ac.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(ac)
	for s: String in ["pilot", "ops", "eva"]:
		var mb := button("", func() -> void: Ics.toggle_mute(s), 16, 64)
		mb.custom_minimum_size.x = 88
		r.add_child(mb)
		var nm: String = "EVA" if s == "eva" else Ics.SEAT_NAMES[s]
		live["mute_" + s] = func() -> void:
			mb.visible = s != "eva" or Eva.active or Ics.seat("eva").get("connected", false)
			mb.text = ("MUTE\n%s" % nm) if not Ics.mute[s] else ("%s\nMUTED" % nm)
			mb.modulate = C_RED if Ics.mute[s] else Color.WHITE
	var st := label("", 16, C_DIM, false)
	st.clip_text = true
	ip.add_child(st)
	live["mc_ics"] = func() -> void:
		st.text = ("INTERCOM: " + Ics.state_text) if not Ics.ok() else "INTERCOM " + _ics_short() + "  ·  levels + settings on the ICS page"


# ======================================================================== PANEL (Falcon Command)
func _build_panel(page: Control) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	page.add_child(v)
	var head := label("", 22, C_AMBER)
	v.add_child(head)
	var h := hbox(v, 12)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for id: String in ["CMD_A", "CMD_B"]:
		var pp := panel(h, str(VirtualPanel.load_all().get(id, {}).get("title", id)).to_upper(), true, true)
		pp.get_parent().size_flags_stretch_ratio = 1.3
		var vp := VirtualPanel.make(id)
		vp.show_title = false
		pp.add_child(vp)
	var side := panel(h, "INTERCOM + SENSES", true, true, C_AMBER)
	var ac := HoldPad.new()
	ac.text = "ALL-CALL / PA"
	ac.sub = "hold: talk to both kids"
	ac.color = C_RED
	ac.custom_minimum_size.y = 110
	ac.lit = func() -> bool: return bool(Ics.status.get("allcall", false))
	ac.held.connect(func(d: bool) -> void: Ics.touch_allcall = d)
	side.add_child(ac)
	side.add_child(label("SENSE TEST (no board: pretend the contacts close)", 18, C_DIM))
	for sid: Array in [["cradle_reclined", "CRADLE RECLINED"], ["pod_down_locked", "POD DOWN + LOCKED"], ["pod_up_locked", "POD UP + LOCKED (optional)"]]:
		side.add_child(switch_button(str(sid[0]), str(sid[1]), 20, 60))
	var pos := label("", 22)
	pos.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(pos)
	live["panel_head"] = func() -> void:
		if current != "PANEL":
			return
		var conn := InputHub.device_connected(InputHub.DEV_CMD)
		head.text = ("Falcon Command is plugged in: these panels mirror the real switches (buttons still work)." if conn
			else "Falcon Command is NOT plugged in: use these on-screen panels (mouse). MOTION key, CREW POS and STOP are hardwired to the actuators and only exist on the real panel.")
		head.add_theme_color_override("font_color", C_GREEN if conn else C_AMBER)
		pos.text = "POD: %s\nSEATS: %s\nTravel time %.0f s · UP sense: %s" % [Game.pod.pod_text(), Game.pod.seats_text(), Game.pod.travel_s, "fitted" if Game.pod.has_up_sense() else "not seen"]


# ======================================================================== ICS (intercom)
func _build_ics(page: Control) -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	page.add_child(root)
	# one framed card per station, 2 x 2
	var cards := grid(root, 2, 14)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s: String in Ics.SEATS:
		_station_card(cards, s)
	# system strip: status + rescan + radio/mix
	var h := hbox(root, 12)
	var a := panel(h, "INTERCOM SYSTEM", true, false, C_AMBER)
	var tr := hbox(a, 8)
	var rs := button("RESCAN USB", func() -> void: Ics.rescan(), 20, 52)
	rs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.add_child(rs)
	tr.add_child(setting_toggle("ics", "enabled", "INTERCOM", 20, 52))
	var stl := label("", 17, C_DIM)
	a.add_child(stl)
	live["ics_status"] = func() -> void:
		if current != "ICS":
			return
		var t := "State: %s\n" % Ics.state_text
		if Ics.ok():
			t += "Sound server: %s · latency ≈ %d ms · dropouts %d\n" % [str(Ics.status.get("server", "")), int(Ics.status.get("latency_ms", 0)), int(Ics.status.get("xruns", 0))]
		t += "Log: ~/.local/share/filament-falcon/ics.log"
		stl.text = t
	var g := panel(h, "RADIO / MIX", true, false)
	var gt := hbox(g, 8)
	for t: Array in [["radio_fx", "RADIO FX"], ["static", "STATIC"], ["squelch_tail", "SQUELCH"], ["beeps", "CLICK+ROGER"], ["speakers", "ROOM SPEAKERS"]]:
		gt.add_child(setting_toggle("ics", str(t[0]), str(t[1]), 15, 44))
	var gs := hbox(g, 24)
	setting_stepper(gs, "ics", "mc_vol", "Callouts", 0.1, 0.0, 2.0, "%.1f", 90, 18)
	setting_stepper(gs, "ics", "allcall_duck", "ALL-CALL duck", 0.05, 0.0, 1.0, "%.2f", 130, 18)
	root.add_child(label("VOX: the mic opens above the white tick on the meter and stays open for the hang time; set PTT if a seat chatters. MIC IN / AUDIO OUT: 'Headset' follows the seat's headset; a device used by another station is not offered.", 16, C_DIM))


## One station = one framed card: header in the station colour, then every control for it.
func _station_card(parent: Control, s: String) -> void:
	var col: Color = SEAT_COL[s]
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r * 0.08, col.g * 0.08, col.b * 0.08, 0.92)
	sb.border_color = col
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 6)
	pc.add_child(c)
	var head := hbox(c, 10)
	var nm := label(("SPACEWALKER (EVA)" if s == "eva" else str(Ics.SEAT_NAMES[s]).to_upper()), 26, col, false)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	var air := label("", 18, C_DIM, false)
	head.add_child(air)
	live["icsair_" + s] = func() -> void:
		var st := Ics.seat(s)
		var on := bool(st.get("open", false))
		air.text = ("● ON AIR" if on else "○ quiet") + ("  MUTED" if Ics.mute.get(s, false) else "") + "  %d dB" % int(float(st.get("level", -90.0)))
		air.add_theme_color_override("font_color", C_GREEN if on else C_DIM)
	# headset
	var hr := hbox(c, 6)
	var hl := label("HEADSET", 16, C_DIM, false)
	hl.custom_minimum_size.x = 110
	hr.add_child(hl)
	var lb := button("◀", func() -> void: Ics.cycle_headset(s, -1), 18, 40)
	lb.custom_minimum_size.x = 44
	hr.add_child(lb)
	var hv := label("", 17, C_GREEN, false)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.custom_minimum_size.x = 160
	hv.clip_text = true
	hr.add_child(hv)
	var rb := button("▶", func() -> void: Ics.cycle_headset(s, 1), 18, 40)
	rb.custom_minimum_size.x = 44
	hr.add_child(rb)
	hr.add_child(button("IDENTIFY", func() -> void: Ics.identify(str(Settings.get_v("ics", s + "_headset"))), 15, 40))
	live["hs_card_" + s] = func() -> void:
		var id := str(Settings.get_v("ics", s + "_headset"))
		hv.text = Ics.device_label(id)
		hv.add_theme_color_override("font_color", C_GREEN if bool(Ics.seat(s).get("connected", false)) else (C_AMBER if id != "" else C_DIM))
	# MIC IN / AUDIO OUT dropdowns (free devices only)
	for kind: String in ["in", "out"]:
		var r := hbox(c, 6)
		var l := label("MIC IN" if kind == "in" else "AUDIO OUT", 16, C_DIM, false)
		l.custom_minimum_size.x = 110
		r.add_child(l)
		r.add_child(_io_picker(s, kind))
	var lm := level_meter(s)
	lm.custom_minimum_size = Vector2(200, 26)
	c.add_child(lm)
	# mode + mute
	var mr := hbox(c, 6)
	for m: String in ["vox", "ptt"]:
		var mb := button(m.to_upper(), func() -> void: Settings.set_v("ics", s + "_mode", m), 18, 44)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mr.add_child(mb)
		live["icsmode_%s_%s" % [s, m]] = func() -> void: mb.modulate = C_GREEN if str(Settings.get_v("ics", s + "_mode")) == m else Color.WHITE
	if s == "commander":
		var tp := ptt_pad("commander", "TALK", "hold", C_AMBER)
		tp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mr.add_child(tp)
	else:
		var mb2 := button("", func() -> void: Ics.toggle_mute(s), 18, 44)
		mb2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mr.add_child(mb2)
		live["icsmute_" + s] = func() -> void:
			mb2.text = "MIC MUTED" if Ics.mute[s] else "MUTE MIC"
			mb2.modulate = C_RED if Ics.mute[s] else Color.WHITE
	# levels in two columns
	var gg := grid(c, 2, 6)
	gg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setting_stepper(gg, "ics", s + "_vox_db", "VOX level", 2.0, -70.0, -10.0, "%.0f dB", 100, 16)
	setting_stepper(gg, "ics", s + "_mic_gain", "Mic gain", 0.25, 0.25, 4.0, "x%.2f", 100, 16)
	setting_stepper(gg, "ics", s + "_attack_ms", "Attack", 5.0, 0.0, 200.0, "%.0f ms", 100, 16)
	setting_stepper(gg, "ics", s + "_hang_ms", "Hang", 100.0, 100.0, 3000.0, "%.0f ms", 100, 16)
	setting_stepper(gg, "ics", s + "_ics_vol", "Intercom", 0.1, 0.0, 2.0, "%.1f", 100, 16)
	setting_stepper(gg, "ics", s + "_game_vol", "Game vol", 0.1, 0.0, 2.0, "%.1f", 100, 16)
	setting_stepper(gg, "ics", s + "_sidetone", "Sidetone", 0.05, 0.0, 0.5, "%.2f|OFF", 100, 16)


## Dropdown of: Headset / None / System default / every device no other station uses.
## Rebuilt whenever the helper's device list or any station's pick changes.
func _io_picker(s: String, kind: String) -> OptionButton:
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.custom_minimum_size = Vector2(260, 40)
	ob.clip_text = true
	ob.add_theme_font_size_override("font_size", 17)
	var key := "%s_%s" % [s, kind]
	var sig := [""]
	var rebuild := func() -> void:
		var opts := Ics.io_options(s, kind)   # [[value, text], ...]
		var cur := str(Settings.get_v("ics", key))
		var sg := JSON.stringify([opts, cur])
		if sg == sig[0] or ob.get_popup().visible:
			return
		sig[0] = sg
		ob.clear()
		var sel := 0
		for i in opts.size():
			ob.add_item(str(opts[i][1]), i)
			ob.set_item_metadata(i, str(opts[i][0]))
			if str(opts[i][0]) == cur:
				sel = i
		ob.select(sel)
		ob.tooltip_text = str(opts[sel][1])
	ob.item_selected.connect(func(i: int) -> void:
		Ics.set_cfg(key, str(ob.get_item_metadata(i)))   # saved + applied live
		Sfx.click())
	live["io_" + key] = rebuild
	rebuild.call()
	return ob


## Seat -> headset rows (used on ICS and SETUP).
func _headset_rows(parent: Control, meters: bool) -> void:
	for s: String in Ics.SEATS:
		var row := hbox(parent, 6)
		var l := label(Ics.SEAT_NAMES[s], 20, SEAT_COL[s], false)
		l.custom_minimum_size.x = 120
		row.add_child(l)
		var lb := button("◀", func() -> void: Ics.cycle_headset(s, -1), 22, 50)
		lb.custom_minimum_size.x = 56
		row.add_child(lb)
		var val := label("", 18, C_GREEN)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.custom_minimum_size.x = 140
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(val)
		var rb := button("▶", func() -> void: Ics.cycle_headset(s, 1), 22, 50)
		rb.custom_minimum_size.x = 56
		row.add_child(rb)
		row.add_child(button("IDENTIFY", func() -> void:
			Ics.identify(str(Settings.get_v("ics", s + "_headset"))), 18, 50))
		if meters:
			var m := level_meter(s)
			m.custom_minimum_size = Vector2(120, 18)
			parent.add_child(m)
		# per-station INPUT / OUTPUT pickers live on the ICS page station cards
		for kind: String in []:
			var r2 := hbox(parent, 6)
			var k2 := kind
			var l2 := label("   MIC IN" if kind == "in" else "   AUDIO OUT", 16, C_DIM, false)
			l2.custom_minimum_size.x = 120
			r2.add_child(l2)
			var b1 := button("◀", func() -> void: Ics.cycle_io(s, k2, -1), 18, 40)
			b1.custom_minimum_size.x = 48
			r2.add_child(b1)
			var v2 := label("", 16, C_GREEN)
			v2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v2.clip_text = true
			r2.add_child(v2)
			var b2 := button("▶", func() -> void: Ics.cycle_io(s, k2, 1), 18, 40)
			b2.custom_minimum_size.x = 48
			r2.add_child(b2)
			if kind == "in":
				var m2 := level_meter(s)   # live mic level: watch it move when you talk
				m2.custom_minimum_size = Vector2(140, 16)
				r2.add_child(m2)
			live["io_%s_%s_%d" % [s, kind, r2.get_instance_id()]] = func() -> void:
				v2.text = Ics.io_label(s, k2)
		live["hs_%s_%d" % [s, row.get_instance_id()]] = func() -> void:
			var id := str(Settings.get_v("ics", s + "_headset"))
			var st := Ics.seat(s)
			val.text = Ics.device_label(id)
			var conn := bool(st.get("connected", false))
			val.add_theme_color_override("font_color", C_GREEN if conn else (C_AMBER if id != "" else C_DIM))


# ======================================================================== MISSION CONTROL
# ======================================================================== MISSIONS
var sel_key := "launch"
var _ms := {}            # widgets of the MISSIONS page
var _switch_armed := -100.0
var _quit_armed := -100.0


func _build_missions(page: Control) -> void:
	var h := hbox(page, 12)
	var left := panel(h, "ALL MISSIONS", true, true, C_AMBER)
	var btns := {}
	for cat: String in MissionCatalog.CATS:
		left.add_child(label(cat, 20, MissionCatalog.CAT_COL[cat], false))
		var g := grid(left, 3, 6)
		for e: Dictionary in MissionCatalog.ALL:
			if e["cat"] != cat:
				continue
			var key: String = e["key"]
			var b := button(MissionCatalog.title_of(e), func() -> void: select_entry(key), 17, 50)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.custom_minimum_size.x = 140
			g.add_child(b)
			btns[key] = b
	var right := panel(h, "", true, true, C_EDGE)
	right.get_parent().size_flags_stretch_ratio = 1.25
	var top := hbox(right, 14)
	var patch := MissionArt.new()
	patch.patch = true
	patch.custom_minimum_size = Vector2(130, 130)
	top.add_child(patch)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	var title := label("", 34, C_AMBER)
	var chips := label("", 18, C_DIM)
	tv.add_child(title)
	tv.add_child(chips)
	var art := MissionArt.new()
	art.custom_minimum_size = Vector2(280, 220)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(art)
	var info := label("", 18, C_TEXT)
	right.add_child(info)
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 8)
	acts.add_theme_constant_override("v_separation", 6)
	right.add_child(acts)
	var logs := VBoxContainer.new()
	right.add_child(logs)
	var start := button("START", _on_start_pressed, 40, 100)
	right.add_child(start)
	_ms = {"btns": btns, "patch": patch, "title": title, "chips": chips, "art": art, "info": info, "acts": acts, "logs": logs, "start": start, "acts_for": "", "logs_n": -1}
	select_entry(Game.mission_id if not MissionCatalog.by_key(Game.mission_id).is_empty() else "launch")
	live["missions"] = func() -> void:
		var e := MissionCatalog.by_key(sel_key)
		for k: String in btns:
			var be: Dictionary = MissionCatalog.by_key(k)
			var loaded: bool = be["id"] == Game.mission_id and (be["kind"] != "eva" or Game.force_eva == be.get("eva", ""))
			(btns[k] as Button).modulate = C_GREEN if k == sel_key else (C_AMBER if loaded else Color.WHITE)
		var is_loaded: bool = e["id"] == Game.mission_id and Game.mission != null
		var running := Game.state == Game.State.ACTIVE
		if running and is_loaded:
			start.text = "RUNNING · MISSION CONTROL ▶"
			start.modulate = C_AMBER
		elif running:
			start.text = "SWITCH TO THIS MISSION? PRESS AGAIN" if _now() - _switch_armed < 4.0 else "START (ends the current mission)"
			start.modulate = C_RED if _now() - _switch_armed < 4.0 else C_GREEN
		else:
			start.text = "START  " + MissionCatalog.title_of(e)
			start.modulate = C_GREEN
		var key := "%s|%d|%s" % [sel_key, Game.mission.get_instance_id() if Game.mission else 0, Eva.available()]
		if _ms["acts_for"] != key:
			_ms["acts_for"] = key
			_rebuild_actions(e, is_loaded)
		if e.get("log", false):
			var n := CaptainsLog.entries().size()
			if n != int(_ms["logs_n"]):
				_ms["logs_n"] = n
				_rebuild_logs()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func select_entry(key: String) -> void:
	var e := MissionCatalog.by_key(key)
	if e.is_empty():
		return
	sel_key = key
	var col: Color = MissionCatalog.CAT_COL[e["cat"]]
	var p: MissionArt = _ms["patch"]
	p.accent = col
	p.caption = str(e["cat"]).get_slice(" ", 0)
	p.art = e["art"]
	(_ms["art"] as MissionArt).accent = col
	(_ms["art"] as MissionArt).art = e["art"]
	(_ms["title"] as Label).text = MissionCatalog.title_of(e)
	var host := ""
	if e["kind"] == "eva":
		host = "  ·  flown inside %s" % Game.MISSION_TITLES.get(e["id"], "")
	(_ms["chips"] as Label).text = "%s  ·  difficulty %s  ·  ~%s min%s" % [e["cat"], e["diff"], e["mins"], host]
	(_ms["info"] as Label).text = "OBJECTIVE  %s\nCREW  %s\nCOMMANDER CAN INJECT  %s" % [e["obj"], e["crew"], e["inject"]]
	_ms["acts_for"] = ""
	_ms["logs_n"] = -1
	if not e.get("log", false):
		for c in (_ms["logs"] as Control).get_children():
			c.queue_free()
	refresh()


func _on_start_pressed() -> void:
	var e := MissionCatalog.by_key(sel_key)
	if Game.state == Game.State.ACTIVE:
		if e["id"] == Game.mission_id:
			show_page("MISSION CONTROL")
			return
		if _now() - _switch_armed > 4.0:
			_switch_armed = _now()
			refresh()
			return
	_switch_armed = -100.0
	Sfx.beep()
	MissionCatalog.launch(e)
	show_page("MISSION CONTROL")


func _rebuild_actions(e: Dictionary, is_loaded: bool) -> void:
	var acts: HFlowContainer = _ms["acts"]
	for c in acts.get_children():
		c.queue_free()
	if e["kind"] == "eva" and str(e["eva"]) in Eva.available() and not Eva.active:
		var ev: String = e["eva"]
		acts.add_child(button("SPACEWALK NOW (from here)", func() -> void:
			Eva.start(ev)
			show_page("EVA"), 18, 46))
	if e["id"] == "ground_crew":
		var gl := GroundLink.get_link(false)
		acts.add_child(button("PHONE LINK: " + (" · ".join(gl.urls()) if gl else "OFF (tap to open)"), func() -> void:
			GroundLink.get_link(true)
			_ms["acts_for"] = "", 18, 46))
	if not is_loaded or Game.mission == null:
		return
	for a: Array in Game.mission.commander_actions():
		var aid := str(a[1])
		acts.add_child(button(str(a[0]), func() -> void:
			if Game.mission:
				Game.mission.on_commander(aid)
				Sfx.click(), 18, 46))


func _rebuild_logs() -> void:
	var logs: VBoxContainer = _ms["logs"]
	for c in logs.get_children():
		c.queue_free()
	var l := CaptainsLog.entries()
	logs.add_child(label("CAPTAIN'S LOG  ·  %d saved" % l.size(), 18, C_AMBER, false))
	for e: Dictionary in l.slice(0, 6):
		var row := hbox(logs, 8)
		var pa := MissionArt.new()
		pa.patch = true
		var me := MissionCatalog.by_key(str(e.get("patch", "")))
		pa.art = str(me.get("art", "log"))
		pa.accent = MissionCatalog.CAT_COL.get(me.get("cat", ""), C_EDGE)
		pa.custom_minimum_size = Vector2(48, 48)
		row.add_child(pa)
		var t := label("%s  ·  %s  ·  %d pts %s  ·  %.0f s" % [str(e.get("date", "")).left(16), e.get("title", ""), int(e.get("score", 0)), "★".repeat(int(e.get("stars", 0))), float(e.get("secs", 0.0))], 16, C_TEXT)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		var ent := e
		row.add_child(button("▶ PLAY", func() -> void: CaptainsLog.play(ent), 16, 40))
	if l.size() > 0:
		logs.add_child(button("■ STOP PLAYBACK", func() -> void: CaptainsLog.stop(), 16, 40))


func _build_control(page: Control) -> void:
	var h := hbox(page, 12)
	# ---- left: mission + flow + score
	var left := panel(h, "MISSION", true, true, C_AMBER)
	left.get_parent().size_flags_stretch_ratio = 0.9
	var mrow := hbox(left, 8)
	var cur := label("", 26, C_GREEN, false)
	cur.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cur.clip_text = true
	cur.custom_minimum_size.x = 120
	mrow.add_child(cur)
	mrow.add_child(button("ALL MISSIONS ▶", func() -> void: show_page("MISSIONS"), 22, 56))
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
		cur.text = m.title + ((" + " + str(EvaScenarios.TITLES.get(Game.force_eva, "")).to_upper()) if Game.force_eva != "" else "")
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
	var faults := label("", 20, C_AMBER)
	faults.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(faults)
	var cr := button("MASTER CAUTION RESET", func() -> void: Game.reset_caution(), 22, 56)
	right.add_child(cr)
	_build_crew_ics(right)
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


# ======================================================================== EVA
var _eva_pick := ""
var _eva_view: EvaControlView


func _build_eva(page: Control) -> void:
	var h := hbox(page, 12)
	var a := panel(h, "SPACEWALK", true, true, C_EVA)
	var st := label("", 18, C_DIM)
	a.add_child(st)
	var sc := grid(a, 3, 6)
	var sbtn := {}
	for id: String in EvaScenarios.TITLES:
		var b := button(str(EvaScenarios.TITLES[id]).to_upper(), func() -> void: _eva_pick = id, 18, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(b)
		sbtn[id] = b
	var brief := label("", 18, C_TEXT)
	a.add_child(brief)
	var r := hbox(a, 8)
	var go := button("START EVA", func() -> void:
		var av := Eva.available()
		var id := _eva_pick if _eva_pick in av else (av[0] if not av.is_empty() else "")
		if id != "":
			Eva.start(id)
			show_page("EVA"), 26, 70)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(go)
	var ab := button("ABORT EVA", func() -> void: Eva.abort(), 22, 70)
	ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(ab)
	var mr := hbox(a, 6)
	mr.add_child(label("DRIVER", 18, C_DIM, false))
	for m: String in ["auto", "vr", "flat"]:
		var mb := button({"auto": "AUTO", "vr": "VR HEADSET", "flat": "ON SCREEN"}[m], func() -> void: Settings.set_v("eva", "mode", m), 18, 48)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mr.add_child(mb)
		live["evamode_" + m] = func() -> void: mb.modulate = C_GREEN if str(Settings.get_v("eva", "mode")) == m else Color.WHITE
	var im := button("", func() -> void: Settings.set_v("eva", "in_missions", not bool(Settings.get_v("eva", "in_missions"))), 18, 48)
	a.add_child(im)
	live["eva_inm"] = func() -> void:
		im.text = "EVA IN MISSIONS: %s (a spacewalk objective near the end of launch, docking, asteroids, lunar, sandbox)" % ("ON" if bool(Settings.get_v("eva", "in_missions")) else "OFF")
		im.modulate = C_GREEN if bool(Settings.get_v("eva", "in_missions")) else Color.WHITE
	a.add_child(label("VR HEADSET (Meta Quest 3 via WiVRn, see docs/game/VR_SETUP.md)", 18, C_EVA, false))
	var vr := hbox(a, 8)
	var lb := button("LAUNCH VR CLIENT", func() -> void: Eva.launch_client(), 20, 56)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vr.add_child(lb)
	vr.add_child(button("STOP VR CLIENT", func() -> void: Eva.stop_client(), 20, 56))
	var vst := label("", 18, C_TEXT)
	a.add_child(vst)
	var cg := grid(a, 2, 6)
	var opt := func(title: String, key: String, vals: Array, names: Array) -> void:
		var row := HBoxContainer.new()
		cg.add_child(row)
		var tl := label(title, 18, C_DIM, false)
		tl.custom_minimum_size.x = 110
		row.add_child(tl)
		for i in vals.size():
			var v: Variant = vals[i]
			var ob := button(str(names[i]), func() -> void: Settings.set_v("eva", key, v), 16, 40)
			row.add_child(ob)
			live["evaopt_%s_%d" % [key, i]] = func() -> void: ob.modulate = C_GREEN if str(Settings.get_v("eva", key)) == str(v) else Color.WHITE
	opt.call("SNAP TURN", "snap_deg", [15.0, 30.0, 45.0], ["15°", "30°", "45°"])
	opt.call("VIGNETTE", "vignette", [0.0, 0.4, 0.7, 1.0], ["OFF", "LOW", "MED", "HIGH"])
	opt.call("PLAY", "play_height", ["standing", "seated"], ["STANDING", "SEATED"])
	opt.call("TETHER", "tether_m", [10.0, 20.0, 30.0], ["10 m", "20 m", "30 m"])
	opt.call("VR QUALITY", "vr_quality", ["low", "medium", "high"], ["LOW", "MED", "HIGH"])
	a.add_child(label("Safety: clear 2 x 2 m of floor OUTSIDE the cockpit frame, Guardian / boundary ON, a grown-up spotter. Recenter: hold the Menu button.", 16, C_AMBER))
	live["eva_page"] = func() -> void:
		var av := Eva.available()
		for id: String in sbtn:
			var b: Button = sbtn[id]
			b.disabled = not id in av or Eva.active
			b.modulate = C_GREEN if id == _eva_pick or (_eva_pick == "" and not av.is_empty() and id == av[0]) else Color.WHITE
		var pick := _eva_pick if _eva_pick in av else (av[0] if not av.is_empty() else "")
		brief.text = str(EvaScenarios.BRIEFS.get(pick, "No spacewalk possible right now: the Falcon must be in space with the engine off (or landed on the Moon)."))
		go.disabled = Eva.active or av.is_empty()
		ab.disabled = not Eva.active
		st.text = ("OUTSIDE: %s · %s · %s" % [str(Eva.scen.get("title", "")), "VR HEADSET" if Eva.driver == "vr" else "ON SCREEN", Eva.sim.step_text() if Eva.sim else ""]) if Eva.active else ("Last EVA: " + Eva.result_text if Eva.result_text != "" else "Ready.")
		vst.text = Eva.status_text() + ("  ·  link %d Hz" % int(Eva.rx_hz) if Eva.client_connected() else "")
	var b2 := panel(h, "ON-SCREEN SPACEWALK  ·  HELMET CAM / DRONE", true, true, C_EVA)
	b2.get_parent().size_flags_stretch_ratio = 1.4
	_eva_view = EvaControlView.new()
	_eva_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_eva_view.custom_minimum_size = Vector2(320, 300)
	b2.add_child(_eva_view)
	var vr2 := hbox(b2, 8)
	vr2.add_child(button("FIRST PERSON", func() -> void: _eva_view.kind = "HELMET CAM", 18, 44))
	vr2.add_child(button("DRONE", func() -> void: _eva_view.kind = "EVA DRONE", 18, 44))
	var tele := label("", 18, C_TEXT)
	tele.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vr2.add_child(tele)
	var tasks := label("", 18, C_TEXT)
	b2.add_child(tasks)
	live["eva_tasks"] = func() -> void:
		tasks.text = ConsoleUI.eva_task_text()
		var t := Eva.telemetry()
		tele.text = "" if t.is_empty() else "O2 %d%%  BATT %d%%  CO2 %.1f  %.1f°C  HR %d  GAS %d%%  TETHER %.1f m" % [int(t["o2"]), int(t["batt"]), float(t["co2"]), float(t["temp"]), int(t["hr"]), int(t["gas"]), float(t["tether"])]


# ======================================================================== SETUP
func _build_setup(page: Control) -> void:
	# panels wrap onto a new row when the screen is too narrow (then the page scrolls down)
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 12)
	h.add_theme_constant_override("v_separation", 12)
	page.add_child(h)
	var a := panel(h, "SCREENS", true, true)
	a.get_parent().size_flags_stretch_ratio = 1.3
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
		l.custom_minimum_size.x = 190
		row.add_child(l)
		var lb := button("◀", func() -> void: _cycle_screen(role, -1), 24, 52)
		lb.custom_minimum_size.x = 56
		row.add_child(lb)
		var val := label("", 18, C_GREEN, false)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # long "AUTO → #2 22\" … DisplayPort-0" texts wrap
		val.custom_minimum_size.x = 120
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(val)
		var rb := button("▶", func() -> void: _cycle_screen(role, 1), 24, 52)
		rb.custom_minimum_size.x = 56
		row.add_child(rb)
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
	var vrl := label("", 18, C_EVA)
	b.add_child(vrl)
	live["setup_vr"] = func() -> void:
		vrl.text = "VR / SPACEWALK: " + Eva.status_text() + "  (Commander > EVA)"
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
	b.add_child(button("QUIT GAME", func() -> void: Game.quit_game(), 22, 56))
	var c := panel(h, "HEADSETS + PANELS", true, true, C_AMBER)
	c.get_parent().size_flags_stretch_ratio = 1.1
	c.add_child(label("Intercom headset per seat (matched by name + USB serial/port, so re-plugging keeps them). IDENTIFY beeps in that headset.", 17, C_DIM))
	_headset_rows(c, false)
	var cr := hbox(c, 6)
	var rsb := button("RESCAN", func() -> void: Ics.rescan(), 20, 52)
	rsb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cr.add_child(rsb)
	var more := button("INTERCOM ▶", func() -> void: show_page("ICS"), 20, 52)
	more.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cr.add_child(more)
	c.add_child(label("VIRTUAL PANELS (on-screen controls)", 20, C_EDGE))
	c.add_child(setting_toggle("input", "force_virtual_panels", "ALWAYS SHOW", 20, 56))
	var bst := label("", 18)
	c.add_child(bst)
	c.add_child(label("CREW POSITION SENSES", 20, C_EDGE))
	c.add_child(setting_toggle("pod", "callouts", "POD CALLOUTS", 20, 52))
	setting_stepper(c, "pod", "travel_s", "Travel time", 5.0, 10.0, 120.0, "%.0f s", 150, 18)
	var ub := button("", func() -> void:
		var order := ["auto", "yes", "no"]
		Settings.set_v("pod", "up_sense", order[(order.find(str(Settings.get_v("pod", "up_sense"))) + 1) % 3]), 18, 50)
	c.add_child(ub)
	live["setup_c"] = func() -> void:
		if current != "SETUP":
			return
		var t := ""
		for dev: String in InputHub.BOARDS:
			t += "%s: %s\n" % [dev, "plugged in" if InputHub.device_connected(dev) else "missing → virtual panel"]
		bst.text = t.strip_edges()
		ub.text = "POD UP SENSE fitted: " + str(Settings.get_v("pod", "up_sense")).to_upper()
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
	Game.hook_window(w)
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
