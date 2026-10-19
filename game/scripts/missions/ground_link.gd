class_name GroundLink
extends Node
## GROUND CREW: a 4th person joins as MISSION CONTROL from any phone / tablet browser on the
## home network. A tiny built-in HTTP server (no internet, no app): GET / = the control page,
## /s = live status JSON (polled once a second), /c?x=CMD = a button press.
## Port: Settings ground/port (8088). Anyone on the LAN can press the buttons: home use only.

const MSGS := {
	"go": "Mission Control: you are GO!",
	"hello": "Mission Control says hello, crew!",
	"great": "Mission Control: great job, crew!",
	"careful": "Mission Control: nice and careful now.",
	"home": "Mission Control: time to come home.",
}
var server := TCPServer.new()
var port := 8088
var peers: Array = []          # [[StreamPeerTCP, started_ms, buffer]]
var log_lines: Array[String] = []
var presses := 0
var last_seen_ms := -100000


static func get_link(start: bool = true) -> GroundLink:
	var g: GroundLink = Game.get_node_or_null("GroundLink")
	if g == null and start:
		g = GroundLink.new()
		g.name = "GroundLink"
		Game.add_child(g)
	return g


func _ready() -> void:
	port = int(Settings.get_v("ground", "port"))
	if server.listen(port, "*") != OK:
		push_warning("Ground crew: port %d busy" % port)


func running() -> bool:
	return server.is_listening()


func connected() -> bool:
	return Time.get_ticks_msec() - last_seen_ms < 4000


func urls() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or (a.begins_with("172.") and a.count(".") == 3):
			out.append("http://%s:%d" % [a, port])
	if out.is_empty():
		out.append("http://<this-pc>:%d" % port)
	return out


func _process(_dt: float) -> void:
	while server.is_connection_available():
		peers.append([server.take_connection(), Time.get_ticks_msec(), ""])
	for p: Array in peers.duplicate():
		var c: StreamPeerTCP = p[0]
		c.poll()
		if c.get_status() == StreamPeerTCP.STATUS_CONNECTED and c.get_available_bytes() > 0:
			p[2] = str(p[2]) + c.get_utf8_string(c.get_available_bytes())
		if str(p[2]).contains("\r\n\r\n"):
			_serve(c, str(p[2]).get_slice(" ", 1))
			c.disconnect_from_host()
			peers.erase(p)
		elif Time.get_ticks_msec() - int(p[1]) > 3000 or c.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			c.disconnect_from_host()
			peers.erase(p)


func _serve(c: StreamPeerTCP, path: String) -> void:
	last_seen_ms = Time.get_ticks_msec()
	if path.begins_with("/c?x="):
		command(path.substr(5).uri_decode())
		_reply(c, "application/json", JSON.stringify({"ok": true}))
	elif path.begins_with("/s"):
		_reply(c, "application/json", JSON.stringify(status()))
	else:
		_reply(c, "text/html; charset=utf-8", PAGE)


func _reply(c: StreamPeerTCP, ctype: String, body: String) -> void:
	var b := body.to_utf8_buffer()
	c.put_data(("HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [ctype, b.size()]).to_utf8_buffer())
	c.put_data(b)


func status() -> Dictionary:
	var m: Mission = Game.mission
	var o := m.current_objective() if m else {}
	var s: ShipSim = Game.sim
	return {"title": m.title if m else "", "state": Game.STATE_NAMES[Game.state], "objective": str(o.get("text", "")),
		"role": str(o.get("role", "")), "alt_km": snappedf(s.altitude / 1000.0, 0.1), "speed": int(s.vel.length() if s.dominant == null else s.surface_vel.length()),
		"fuel": int(s.fuel * 100.0 / maxf(s.fuel_max, 1.0)), "hull": int(Game.hull), "o2": int(Game.o2),
		"faults": Game.failures.keys().filter(func(k: String) -> bool: return Game.failures[k]),
		"card": str(m.card.get("title", "")) if m else "", "log": log_lines.slice(-6), "score": Game.score_total}


func command(cmd: String) -> void:
	presses += 1
	log_lines.append("%s  %s" % [Time.get_time_string_from_system(), cmd.to_upper()])
	var m: Mission = Game.mission
	if m and m.on_ground(cmd):
		return
	if MSGS.has(cmd):
		Voice.say(MSGS[cmd], 1)
		Sfx.tone(2525.0, 0.18, 0.15)
	elif cmd.begins_with("fail_") and Game.state == Game.State.ACTIVE:
		Game.inject_failure(cmd.substr(5))


const PAGE := """<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Falcon Mission Control</title><style>
body{background:#050a14;color:#d8f0ff;font-family:sans-serif;margin:0;padding:12px}
h1{font-size:22px;color:#ffb326;margin:4px 0}#st{font-size:18px;line-height:1.5;background:#0a1626;border:2px solid #2a8fd0;border-radius:12px;padding:10px}
.g{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:12px}
button{font-size:22px;padding:22px 6px;border-radius:14px;border:2px solid #3cb4ff;background:#0d2238;color:#fff}
.go{background:#145c2a;border-color:#4dff7a}.f{background:#4a1410;border-color:#ff5040}#log{font-size:14px;color:#8ab;margin-top:10px;white-space:pre}
</style></head><body><h1>🛰 FALCON MISSION CONTROL</h1><div id="st">connecting...</div>
<div class="g">
<button class="go" onclick="c('go')">✅ GO!</button><button onclick="c('hello')">👋 HELLO CREW</button>
<button onclick="c('great')">⭐ GREAT JOB</button><button onclick="c('careful')">🐢 CAREFUL</button>
<button onclick="c('photo')">📷 PHOTO RECEIVED</button><button onclick="c('home')">🏠 COME HOME</button>
<button class="f" onclick="c('fail_sensor')">⚠ SENSOR GLITCH</button><button class="f" onclick="c('fail_leak')">⚠ AIR LEAK</button>
</div><div id="log"></div><script>
function c(x){fetch('/c?x='+x).then(p)}
function p(){fetch('/s').then(r=>r.json()).then(s=>{document.getElementById('st').innerHTML=
'<b>'+s.title+'</b> · '+s.state+'<br>NOW: '+s.objective+' <i>('+s.role+')</i><br>ALT '+s.alt_km+' km · SPEED '+s.speed+' m/s<br>FUEL '+s.fuel+'% · HULL '+s.hull+'% · AIR '+s.o2+'%'+
(s.faults.length?'<br><b style="color:#ff6050">FAULT: '+s.faults.join(', ')+'</b>':'')+(s.card?'<br>CARD: '+s.card:'')+'<br>SCORE '+s.score;
document.getElementById('log').textContent=s.log.join('\\n')}).catch(()=>{document.getElementById('st').textContent='no link...'})}
setInterval(p,1000);p();</script></body></html>"""
