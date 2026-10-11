class_name FalconPanel
extends Control
## Shared look and widgets for the two touch/mouse UIs (kids' console and Commander screen):
## theme, panels, big buttons, live-updating bars and switch toggles. Subclasses register
## refresh callbacks in `live`; they run 10 times a second.

const C_BG := Color(0.02, 0.04, 0.08)
const C_PANEL := Color(0.04, 0.09, 0.15, 0.95)
const C_EDGE := Color(0.2, 0.75, 1.0)
const C_TEXT := Color(0.85, 0.95, 1.0)
const C_DIM := Color(0.6, 0.72, 0.85)
const C_GREEN := Color(0.3, 1.0, 0.45)
const C_AMBER := Color(1.0, 0.7, 0.15)
const C_RED := Color(1.0, 0.3, 0.25)
const C_PILOT := Color(0.35, 0.85, 1.0)
const C_OPS := Color(1.0, 0.6, 0.25)

var display: Node                # DisplayManager (may be null in tests)
var live := {}                   # key -> Callable updating a widget
var _acc := 0.0


func _process(dt: float) -> void:
	_acc += dt
	if _acc < 0.1:
		return
	_acc = 0.0
	refresh()


func refresh() -> void:
	for k in live:
		var cb: Callable = live[k]
		if cb.is_valid():
			cb.call()


# ======================================================================== theme / widgets
static func sb(c: Color, edge: Color, w: int = 2, r: int = 12) -> StyleBoxFlat:
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


func make_theme(base_font: int = 26) -> Theme:
	var t := Theme.new()
	t.default_font_size = base_font
	t.set_stylebox("normal", "Button", sb(Color(0.06, 0.14, 0.24), C_EDGE * 0.8))
	t.set_stylebox("hover", "Button", sb(Color(0.09, 0.2, 0.33), C_EDGE))
	t.set_stylebox("pressed", "Button", sb(Color(0.1, 0.45, 0.6), Color(0.6, 1, 1), 3))
	t.set_stylebox("hover_pressed", "Button", sb(Color(0.1, 0.45, 0.6), Color(0.6, 1, 1), 3))
	t.set_stylebox("disabled", "Button", sb(Color(0.04, 0.06, 0.09), Color(0.2, 0.3, 0.4)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.75, 0.85, 0.95, 0.8))
	t.set_color("font_color", "Label", C_TEXT)
	t.set_stylebox("panel", "PanelContainer", sb(C_PANEL, C_EDGE * 0.6, 2, 16))
	t.set_stylebox("normal", "LineEdit", sb(Color(0.03, 0.06, 0.1), C_EDGE * 0.6))
	t.set_stylebox("background", "ProgressBar", sb(Color(0.02, 0.04, 0.07), C_EDGE * 0.5, 2, 6))
	t.set_stylebox("fill", "ProgressBar", sb(C_GREEN, C_GREEN, 0, 6))
	t.set_stylebox("normal", "OptionButton", sb(Color(0.06, 0.14, 0.24), C_EDGE * 0.8))
	return t


func add_background() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func button(text: String, cb: Callable, fs: int = 28, min_h: int = 80) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, min_h)
	b.add_theme_font_size_override("font_size", fs)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func label(text: String, fs: int = 26, c: Color = C_TEXT, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func panel(parent: Control, title: String = "", expand_h := true, expand_v := false, title_color: Color = C_EDGE) -> VBoxContainer:
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
		v.add_child(label(title, 24, title_color))
	return v


func hbox(parent: Control, sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	parent.add_child(h)
	return h


func grid(parent: Control, cols: int, sep: int = 10) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", sep)
	g.add_theme_constant_override("v_separation", sep)
	parent.add_child(g)
	return g


## A horizontal bar with a title and value text. getter returns [fraction, text, color].
func bar(parent: Control, title: String, key: String, getter: Callable, title_w: int = 200, fs: int = 24) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := label(title, fs, C_TEXT, false)
	l.custom_minimum_size.x = title_w
	row.add_child(l)
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(160, fs + 10)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.show_percentage = false
	row.add_child(pb)
	var val := label("", fs, C_TEXT, false)
	val.custom_minimum_size.x = 150
	row.add_child(val)
	live[key] = func() -> void:
		var r: Array = getter.call()
		pb.value = clampf(float(r[0]), 0.0, 1.0) * 100.0
		val.text = str(r[1])
		var s: StyleBoxFlat = (pb.get_theme_stylebox("fill") as StyleBoxFlat).duplicate()
		s.bg_color = r[2]
		pb.add_theme_stylebox_override("fill", s)


## A touch toggle for a maintained switch. When the real board is present the button only
## mirrors the hardware (the physical switch wins).
func switch_button(id: String, text: String, fs: int = 26, min_h: int = 96) -> Button:
	var b := button(text, func() -> void: pass, fs, min_h)
	b.toggle_mode = true
	b.toggled.connect(func(on: bool) -> void:
		if not InputHub.has_hardware_for(id):
			InputHub.set_switch(id, on)
			Sfx.click())
	live["sw_" + id + "_" + str(b.get_instance_id())] = func() -> void:
		var on := InputHub.on(id)
		b.set_pressed_no_signal(on)
		b.disabled = InputHub.has_hardware_for(id)
		b.modulate = Color(0.6, 1.0, 0.7) if on else Color.WHITE
	return b


## A momentary touch button (virtual press of a hardware button).
func pulse_button(id: String, text: String, fs: int = 26, min_h: int = 96) -> Button:
	return button(text, func() -> void:
		InputHub.pulse(id)
		Sfx.click(), fs, min_h)


## A row of radio buttons for a latched rotary group ("fa" assist knob, "ops" mode knob).
func group_buttons(parent: Control, grp: String, names: Array, fs: int = 24, min_h: int = 90) -> void:
	for i in names.size():
		var v := i
		var b := button(str(names[i]), func() -> void:
			InputHub.set_group(grp, v)
			Sfx.click(), fs, min_h)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent.add_child(b)
		live["grp_%s_%d_%d" % [grp, i, b.get_instance_id()]] = func() -> void:
			var on := InputHub.group(grp) == v
			b.modulate = C_GREEN if on else Color.WHITE


## A "-  value  +" row for a numeric setting (saved immediately).
func setting_stepper(parent: Control, section: String, key: String, title: String, step: float, lo: float, hi: float, fmt: String = "%.2f", title_w: int = 150, fs: int = 20) -> HBoxContainer:
	var row := hbox(parent, 6)
	var l := label(title, fs, C_TEXT, false)
	l.custom_minimum_size.x = title_w
	row.add_child(l)
	row.add_child(button("-", func() -> void:
		Settings.set_v(section, key, clampf(snappedf(float(Settings.get_v(section, key)) - step, step * 0.01), lo, hi)), fs, 44))
	var v := label("", fs, C_GREEN, false)
	v.custom_minimum_size.x = 72
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(v)
	row.add_child(button("+", func() -> void:
		Settings.set_v(section, key, clampf(snappedf(float(Settings.get_v(section, key)) + step, step * 0.01), lo, hi)), fs, 44))
	for b in [row.get_child(1), row.get_child(3)]:
		(b as Button).custom_minimum_size.x = 44
	live["stp_%s_%s_%d" % [section, key, row.get_instance_id()]] = func() -> void:
		var x := float(Settings.get_v(section, key))
		v.text = ("OFF" if x <= 0.0 and fmt.contains("OFF") else (fmt.replace("|OFF", "") % x))
	return row


## A toggle button for a boolean setting.
func setting_toggle(section: String, key: String, text: String, fs: int = 20, min_h: int = 52) -> Button:
	var b := button("", func() -> void: Settings.set_v(section, key, not bool(Settings.get_v(section, key))), fs, min_h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	live["tgl_%s_%s_%d" % [section, key, b.get_instance_id()]] = func() -> void:
		var on := bool(Settings.get_v(section, key))
		b.text = "%s: %s" % [text, "ON" if on else "OFF"]
		b.modulate = C_GREEN if on else Color.WHITE
	return b


## Push-to-talk / ALL-CALL style hold pad wired to the intercom.
func ptt_pad(seat: String, text: String, sub: String, col: Color) -> HoldPad:
	var hp := HoldPad.new()
	hp.text = text
	hp.sub = sub
	hp.color = col
	hp.lit = func() -> bool: return Ics.keyed(seat)
	hp.held.connect(func(d: bool) -> void: Ics.touch_ptt[seat] = d)
	return hp


func level_meter(seat: String) -> LevelMeter:
	var m := LevelMeter.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.getter = func() -> Array:
		var st := Ics.seat(seat)
		var thr := float(Settings.get_v("ics", seat + "_vox_db")) if str(Settings.get_v("ics", seat + "_mode")) == "vox" else -99.0
		return [float(st.get("level", -90.0)), bool(st.get("open", false)), thr]
	return m
