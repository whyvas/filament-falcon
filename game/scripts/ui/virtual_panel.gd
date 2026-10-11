class_name VirtualPanel
extends TouchControl
## One real panel drawn on screen, from config/virtual_panels.json (generated from the CAD
## layouts by tools/gen_virtual_panels.py): same controls, positions and printed legends,
## scaled to fit, with finger-sized hit areas. Shown while its board is unplugged (or when
## SETUP forces virtual panels). Behaviour matches the hardware:
##   toggle            tap flips it (a board that is plugged in wins: then it only mirrors)
##   guarded toggle    two steps: tap lifts the red cover, tap again flips; the cover drops
##                     back after 4 s
##   ON-OFF-ON         tap the upper / lower half; tap the same side again for centre-off
##   push buttons      held while the finger is on them (multi-touch)
##   encoder knob      tap left = turn left, right = turn right, centre = push; the printed
##                     mode legends light up
##   lever slots       drag the throttle; tap the gear lever
##   key switch        tap to turn
##   hardwired (MOTION key, CREW POS, E-STOP)  drawn grey and inert: the game can never move
##                     the seats or the pod

const FILE := "res://config/virtual_panels.json"
const MIN_HIT_PX := 42.0
const COVER_S := 4.0
const HIT_MM := {"tog6": 14.0, "tog6g": 17.0, "tog3": 15.0, "tog12": 15.0, "arc22": 16.0, "arc19": 14.0,
	"btn16": 13.0, "key19": 15.0, "ec11": 16.0, "estop22": 17.0}

static var _data := {}

var panel_id := ""
var data := {}
var show_title := true
var _ptr := {}            # pointer index -> {"i": control index, "part": String}
var _cover_until := {}    # control index -> time the guard cover drops
var _held := {}           # action -> fingers holding it
var _s := 1.0
var _o := Vector2.ZERO


static func load_all() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(FILE, FileAccess.READ)
		if f:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				_data = (d as Dictionary).get("panels", {})
	return _data


static func make(id: String) -> VirtualPanel:
	var vp := VirtualPanel.new()
	vp.panel_id = id
	vp.data = load_all().get(id, {})
	return vp


func _init() -> void:
	super()
	custom_minimum_size = Vector2(240, 190)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func controls() -> Array:
	return data.get("controls", [])


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _layout() -> void:
	var w := float(data.get("w", 200))
	var h := float(data.get("h", 160))
	_s = minf(size.x / w, size.y / h)
	_o = (size - Vector2(w, h) * _s) * 0.5


func to_px(x: float, y: float) -> Vector2:
	return _o + Vector2(x, float(data.get("h", 160)) - y) * _s


func to_mm(p: Vector2) -> Vector2:
	var q := (p - _o) / _s
	return Vector2(q.x, float(data.get("h", 160)) - q.y)


# ---------------------------------------------------------------- input
func hit(pos: Vector2) -> int:
	_layout()
	var best := -1
	var best_d := 1e9
	var cs := controls()
	for i in cs.size():
		var c: Dictionary = cs[i]
		var k := str(c["kind"])
		if k == "led5":
			continue
		var cp := to_px(float(c["x"]), float(c["y"]))
		if k == "slot":
			var hw := maxf((float(c["w"]) * 0.5 + 10.0) * _s, MIN_HIT_PX)
			var hl := (float(c["l"]) * 0.5 + 8.0) * _s
			if absf(pos.x - cp.x) <= hw and absf(pos.y - cp.y) <= hl:
				return i
			continue
		var r := maxf(float(HIT_MM.get(k, 14.0)) * _s, MIN_HIT_PX)
		var d := pos.distance_to(cp)
		if d <= r and d < best_d:
			best = i
			best_d = d
	return best


func _hw(action: String) -> bool:
	return InputHub.has_hardware_for(action)


func _hold(action: String, down: bool) -> void:
	var n := int(_held.get(action, 0)) + (1 if down else -1)
	n = maxi(n, 0)
	_held[action] = n
	InputHub.set_switch(action, n > 0)


func _pointer_down(idx: int, pos: Vector2) -> void:
	var i := hit(pos)
	if i < 0:
		return
	var c: Dictionary = controls()[i]
	if c.get("hardwired", false):
		return
	var k := str(c["kind"])
	var part := ""
	match k:
		"tog6", "key19":
			_toggle(str(c["action"]))
		"tog6g":
			if _now() < float(_cover_until.get(i, 0.0)):
				_toggle(str(c["action"]))
			else:
				Sfx.tone(700.0, 0.04, 0.12)
			_cover_until[i] = _now() + COVER_S
		"tog3":
			var up := to_mm(pos).y >= float(c["y"])
			var a := str(c["up"]) if up else str(c["down"])
			var other := str(c["down"]) if up else str(c["up"])
			if not _hw(a):
				var was := InputHub.on(a)
				InputHub.set_switch(a, not was)
				InputHub.set_switch(other, false)
				Sfx.click()
		"arc22", "arc19", "btn16":
			part = str(c["action"])
			_hold(part, true)
			Sfx.click()
		"ec11":
			var e: Dictionary = c["enc"]
			var dx := to_mm(pos).x - float(c["x"])
			if absf(dx) < 6.0:
				part = str(e["push"])
				_hold(part, true)
			elif e.has("axis"):
				var ax := str(e["axis"])
				InputHub.set_axis_override(ax, clampf(float(InputHub.latch.get(ax, 0.7)) + (0.1 if dx > 0.0 else -0.1), 0.0, 1.0))
			else:
				InputHub.pulse(str(e["next"]) if dx > 0.0 else str(e["prev"]))
			Sfx.click()
		"slot":
			if str(c["action"]) == "throttle":
				part = "throttle"
				_drag_throttle(c, pos)
			else:
				_toggle("gear")
	_ptr[idx] = {"i": i, "part": part}
	queue_redraw()


func _toggle(action: String) -> void:
	if _hw(action):
		return
	InputHub.set_switch(action, not InputHub.on(action))
	Sfx.click()


func _drag_throttle(c: Dictionary, pos: Vector2) -> void:
	var l := float(c["l"])
	var y0 := float(c["y"]) - l * 0.5 + 4.0
	var t := clampf((to_mm(pos).y - y0) / (l - 8.0), 0.0, 1.0)
	InputHub.set_axis_override("throttle", t)


func _pointer_move(idx: int, pos: Vector2) -> void:
	if not _ptr.has(idx):
		return
	var p: Dictionary = _ptr[idx]
	if str(p["part"]) == "throttle":
		_drag_throttle(controls()[int(p["i"])], pos)


func _pointer_up(idx: int) -> void:
	if not _ptr.has(idx):
		return
	var p: Dictionary = _ptr[idx]
	_ptr.erase(idx)
	var part := str(p["part"])
	if part != "" and part != "throttle":
		_hold(part, false)
	queue_redraw()


func release_all() -> void:
	for idx in _ptr.keys():
		_pointer_up(int(idx))
	_ptr.clear()


func _process(_dt: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


# ---------------------------------------------------------------- state for drawing
func lamp_color(name: String) -> Color:
	var off := Color(0.12, 0.13, 0.12)
	var blink := fmod(_now() * 2.5, 2.0) < 1.0
	if name.begins_with("action:"):
		return Color(0.3, 1.0, 0.4) if InputHub.on(name.substr(7)) else off
	match name:
		"flaps":
			return Color(0.3, 1.0, 0.4) if InputHub.on("flaps_up") or InputHub.on("flaps_down") else off
		"caution":
			return Color(1.0, 0.2, 0.15) if Game.caution_active and blink else off
		"gear":
			return Color(0.3, 1.0, 0.4) if InputHub.on("gear") else off
		"pilot_ready":
			return Color(0.3, 1.0, 0.4) if InputHub.on("engine_arm") or Game.state == Game.State.ACTIVE else Color(1, 0.65, 0.1)
		"ops_ready":
			return Color(0.3, 1.0, 0.4) if InputHub.on("pwr_reactor") else Color(1, 0.65, 0.1)
		"pod_flt":
			if Game.pod.pod == PodMonitor.Pod.DOWN_LOCKED:
				return Color(0.3, 1.0, 0.4)
			if Game.pod.pod == PodMonitor.Pod.MOVING or Game.pod.seats == PodMonitor.Seats.MOVING:
				return Color(1, 0.65, 0.1) if blink else off
			return off
		"pod_brd":
			return Color(0.3, 1.0, 0.4) if Game.pod.pod == PodMonitor.Pod.UP and Game.pod.seats == PodMonitor.Seats.UPRIGHT else off
	return off


static func cap_color(desc: String) -> Color:
	var d := desc.to_lower()
	if d.contains("(red)"):
		return Color(0.85, 0.12, 0.1)
	if d.contains("(yellow)"):
		return Color(0.95, 0.8, 0.1)
	if d.contains("(green)"):
		return Color(0.15, 0.75, 0.25)
	if d.contains("(blue)"):
		return Color(0.15, 0.4, 0.95)
	if d.contains("(amber)"):
		return Color(1.0, 0.55, 0.05)
	return Color(0.16, 0.17, 0.19)


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	_layout()
	if data.is_empty():
		draw_string(font(), Vector2(10, 30), "no layout for " + panel_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.RED)
		return
	var w := float(data["w"])
	var h := float(data["h"])
	var plate := Rect2(_o, Vector2(w, h) * _s)
	# plate: dark anodised look, lighter top edge, four corner screws
	draw_rect(plate, Color(0.13, 0.14, 0.16))
	draw_rect(Rect2(plate.position, Vector2(plate.size.x, 20.0 * _s)), Color(0.1, 0.11, 0.12))
	draw_rect(Rect2(plate.position + Vector2(0, plate.size.y - 20.0 * _s), Vector2(plate.size.x, 20.0 * _s)), Color(0.1, 0.11, 0.12))
	draw_rect(plate, Color(0.4, 0.43, 0.47), false, 2.0)
	for sx in [8.0, w - 8.0]:
		for sy in [8.0, h - 8.0]:
			var sp := to_px(sx, sy)
			draw_circle(sp, maxf(2.2 * _s, 3.0), Color(0.3, 0.32, 0.35))
			draw_line(sp - Vector2(1.6, 0) * _s, sp + Vector2(1.6, 0) * _s, Color(0.12, 0.12, 0.13), 1.5)
	for g: Array in data.get("grooves", []):
		var a := to_px(float(g[0]), float(g[3]))
		var b := to_px(float(g[2]), float(g[1]))
		draw_rect(Rect2(a, b - a), Color(0.75, 0.78, 0.82, 0.5), false, 2.0)
	var f := font()
	for L: Dictionary in data.get("labels", []):
		var fs := maxi(int(float(L["cap"]) * _s / 0.72), 9)
		var col := Color(0.92, 0.94, 0.96)
		if L.has("group"):
			var on := InputHub.group(str(L["group"])) == int(L["value"])
			col = Color(0.35, 1.0, 0.5) if on else Color(0.55, 0.58, 0.62)
			if on:
				var lp := to_px(float(L["x"]), float(L["y"]))
				draw_circle(lp + Vector2(-34.0 * _s * 0.5 - 6.0, -fs * 0.35), maxf(2.0 * _s, 4.0), col)
		var p := to_px(float(L["x"]), float(L["y"]))
		draw_string(f, Vector2(p.x - 400.0, p.y + fs * 0.36), str(L["text"]), HORIZONTAL_ALIGNMENT_CENTER, 800.0, fs, col)
		if L.has("lamp"):
			draw_circle(p + Vector2(-float(fs) * 1.6, 0), maxf(2.6 * _s, 6.0), lamp_color(str(L["lamp"])))
	var cs := controls()
	for i in cs.size():
		_draw_control(i, cs[i])
	if show_title:
		var hint := str(data.get("title", panel_id)).to_upper()
		draw_string(f, plate.position + Vector2(8, 15), hint, HORIZONTAL_ALIGNMENT_LEFT, plate.size.x - 16, 13, Color(0.6, 0.7, 0.8, 0.8))


func _draw_control(i: int, c: Dictionary) -> void:
	var k := str(c["kind"])
	var p := to_px(float(c["x"]), float(c["y"]))
	var s := _s
	var held := false
	for v: Dictionary in _ptr.values():
		if int(v["i"]) == i:
			held = true
	match k:
		"led5":
			var col := lamp_color(str(c.get("lamp", "")))
			if str(c.get("lamp", "")) == "jump_charge":
				col = Color(0.3, 0.45, 1.0) if Game.jump_charge >= (int(c.get("index", 0)) + 1) * 100.0 / 6.0 else Color(0.12, 0.13, 0.12)
			draw_circle(p, maxf(3.2 * s, 6.0), Color(0.05, 0.05, 0.05))
			draw_circle(p, maxf(2.5 * s, 5.0), col)
			if col.v > 0.5:
				draw_circle(p, maxf(5.0 * s, 9.0), Color(col.r, col.g, col.b, 0.18))
		"tog6", "tog6g", "tog3", "tog12":
			_draw_toggle(i, c, p, k)
		"arc22", "arc19", "btn16":
			var r := {"arc22": 11.0, "arc19": 9.5, "btn16": 8.0}[k] as float
			var base := cap_color(str(c.get("desc", "")))
			var on := InputHub.on(str(c.get("action", "")))
			draw_circle(p, (r + 1.6) * s, Color(0.55, 0.57, 0.6))
			draw_circle(p, r * s, base.lightened(0.35) if on or held else base)
			draw_circle(p + Vector2(-0.25, -0.3) * r * s, r * s * 0.35, Color(1, 1, 1, 0.12))
			if held:
				draw_arc(p, (r + 3.0) * s, 0, TAU, 32, Color(1, 1, 1, 0.8), 3.0)
		"key19":
			var on := InputHub.on(str(c.get("action", "")))
			var hw := bool(c.get("hardwired", false))
			draw_circle(p, 9.5 * s, Color(0.6, 0.62, 0.65) if not hw else Color(0.35, 0.36, 0.38))
			draw_circle(p, 7.0 * s, Color(0.25, 0.26, 0.28))
			var ang := (0.0 if on else -PI * 0.5) + PI * 0.5
			var d := Vector2(cos(ang - PI * 0.5), sin(ang - PI * 0.5))
			draw_line(p - d * 5.0 * s, p + d * 5.0 * s, Color(0.85, 0.85, 0.8), maxf(2.0 * s, 3.0))
		"ec11":
			draw_circle(p, 9.0 * s, Color(0.08, 0.08, 0.09))
			draw_circle(p, 7.5 * s, Color(0.2, 0.21, 0.23))
			var e: Dictionary = c["enc"]
			var a := -PI * 0.5
			if e.has("group"):
				a = -PI * 0.75 + InputHub.group(str(e["group"])) * PI * 0.5
			elif e.has("axis"):
				a = -PI * 1.25 + float(InputHub.axis(str(e["axis"]))) * PI * 1.5
			draw_line(p, p + Vector2(cos(a), sin(a)) * 7.0 * s, Color(0.95, 0.95, 0.95), maxf(1.5 * s, 2.5))
			var f := font()
			var fs := maxi(int(6.0 * s), 14)
			draw_string(f, p + Vector2(-16.0 * s - fs, fs * 0.35), "◀", HORIZONTAL_ALIGNMENT_CENTER, fs * 2, fs, Color(0.6, 0.85, 1.0, 0.75))
			draw_string(f, p + Vector2(16.0 * s - fs, fs * 0.35), "▶", HORIZONTAL_ALIGNMENT_CENTER, fs * 2, fs, Color(0.6, 0.85, 1.0, 0.75))
			if held:
				draw_arc(p, 10.5 * s, 0, TAU, 32, Color(1, 1, 1, 0.8), 3.0)
		"estop22":
			draw_circle(p, 16.0 * s, Color(0.85, 0.75, 0.1))
			draw_circle(p, 12.0 * s, Color(0.55, 0.08, 0.06))
			draw_circle(p, 9.0 * s, Color(0.65, 0.1, 0.08))
		"slot":
			_draw_slot(c, p)
	if c.get("hardwired", false):
		var f := font()
		var fs := maxi(int(4.0 * s), 11)
		draw_string(f, p + Vector2(-60, 20.0 * s + fs), "HARDWIRED", HORIZONTAL_ALIGNMENT_CENTER, 120, fs, Color(1.0, 0.7, 0.2, 0.85))
		draw_circle(p, 17.0 * s, Color(0.1, 0.1, 0.1, 0.35))
	elif c.has("action") and _hw(str(c["action"])) and k in ["tog6", "tog6g", "key19"]:
		var f2 := font()
		draw_string(f2, p + Vector2(10.0 * s, -10.0 * s), "HW", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.9, 1.0, 0.8))


func _draw_toggle(i: int, c: Dictionary, p: Vector2, k: String) -> void:
	var s := _s
	var metal := Color(0.8, 0.82, 0.85)
	var hw := bool(c.get("hardwired", false))
	if hw:
		metal = Color(0.45, 0.46, 0.48)
	var dirn := 0.0           # -1 down, 0 centre, +1 up (on)
	if k == "tog3":
		dirn = 1.0 if InputHub.on(str(c["up"])) else (-1.0 if InputHub.on(str(c["down"])) else 0.0)
	elif k == "tog12":
		dirn = 0.0
	else:
		dirn = 1.0 if InputHub.on(str(c.get("action", ""))) else -1.0
	var big := 1.4 if k == "tog12" else 1.0
	draw_circle(p, 6.5 * s * big, Color(0.5, 0.52, 0.55))      # hex nut
	draw_circle(p, 4.2 * s * big, Color(0.25, 0.26, 0.28))
	var tip := p + Vector2(0, -dirn * 10.0 * s * big)
	var w := maxf(2.6 * s * big, 4.0)
	draw_line(p, tip, metal, w)
	draw_circle(tip, w * 0.75, metal.lightened(0.2))
	if k == "tog6g":
		var open := _now() < float(_cover_until.get(i, 0.0))
		var g: Array[float] = [-12.0, -25.0, 12.0, 21.0]
		var a := p + Vector2(g[0], -g[3]) * s
		var b := p + Vector2(g[2], -g[1]) * s
		if open:
			# cover flipped up: draw it as a thin bar above the hinge (top), see-through
			draw_rect(Rect2(Vector2(a.x, a.y - 9.0 * s), Vector2(b.x - a.x, 8.0 * s)), Color(0.85, 0.1, 0.08, 0.85))
			var f := font()
			draw_string(f, Vector2(a.x - 40, b.y + 16), "TAP TO FLIP", HORIZONTAL_ALIGNMENT_CENTER, b.x - a.x + 80, maxi(int(4.0 * s), 11), Color(1, 0.8, 0.3))
		else:
			draw_rect(Rect2(a, b - a), Color(0.85, 0.1, 0.08, 0.72))
			draw_rect(Rect2(a, b - a), Color(1, 0.4, 0.3), false, 2.0)
			var f2 := font()
			draw_string(f2, Vector2(a.x - 40, b.y - (b.y - a.y) * 0.25), "LIFT", HORIZONTAL_ALIGNMENT_CENTER, b.x - a.x + 80, maxi(int(4.5 * s), 11), Color(1, 0.9, 0.85))


func _draw_slot(c: Dictionary, p: Vector2) -> void:
	var s := _s
	var w := float(c["w"])
	var l := float(c["l"])
	var r := Rect2(p - Vector2(w, l) * 0.5 * s, Vector2(w, l) * s)
	draw_rect(r, Color(0.03, 0.03, 0.04))
	draw_rect(r, Color(0.45, 0.47, 0.5), false, 2.0)
	var t := 0.0
	var knob := Color(0.15, 0.15, 0.17)
	if str(c["action"]) == "throttle":
		t = InputHub.axis("throttle")
		knob = Color(0.2, 0.2, 0.22)
	else:
		t = 0.0 if InputHub.on("gear") else 1.0      # gear lever: up = UP, down = DOWN
		knob = Color(0.85, 0.85, 0.85)
	var y := r.position.y + r.size.y * (1.0 - t)
	var hw := maxf(w * 1.6, 22.0) * s
	var kr := Rect2(Vector2(p.x - hw * 0.5, y - 5.0 * s), Vector2(hw, 10.0 * s))
	draw_rect(kr, knob)
	draw_rect(kr, Color(0.7, 0.72, 0.75), false, 2.0)
	if str(c["action"]) == "throttle":
		var f := font()
		draw_string(f, Vector2(kr.end.x + 6, y + 7), "%d%%" % int(t * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(5.0 * s), 14), Color(0.6, 1.0, 0.7))
