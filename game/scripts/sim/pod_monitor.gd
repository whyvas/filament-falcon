class_name PodMonitor
extends RefCounted
## Crew-position state from the READ-ONLY sense contacts on Falcon Command. The cradle and pod
## actuators are hardwired (key, hold-to-run, release lever, limit switches, E-stop; see SPEC
## "Safety"): the game can never move anything, it only shows what the contacts say.
##   cradle_reclined  closed = cradle on its recline stop          (GPIO39, HID 15)
##   pod_down_locked  closed = pod on its DOWN stop, pawls in      (GPIO40, HID 26)
##   pod_up_locked    optional: closed = pod parked UP, latched     (GPIO41, HID 27)
## The hardwired interlock guarantees: the pod can only leave UP while the cradle is fully
## reclined, and the cradle only moves while the pod is up and latched. So:
##   pod DOWN-LOCKED  pod_down_locked
##   pod UP           cradle not reclined (interlock), or the up contact is closed
##   pod MOVING       up contact fitted: neither contact closed; without it: up to travel_s
##                    after leaving DOWN, else "UP / MOVING" (cannot tell apart)
##   seats RECLINED / MOVING (travel_s after leaving the recline stop) / UPRIGHT

enum Pod { UP, MOVING, DOWN_LOCKED, UNKNOWN_UP_OR_MOVING }
enum Seats { UPRIGHT, MOVING, RECLINED }
const POD_NAMES := ["UP", "MOVING", "DOWN-LOCKED", "UP / MOVING"]
const SEAT_NAMES := ["UPRIGHT", "MOVING", "RECLINED"]

var pod := Pod.UP
var seats := Seats.UPRIGHT
var up_sense_seen := false
var travel_s := 40.0
var up_sense_mode := "auto"     # auto | yes | no
var _reclined := false
var _down := false
var _up := false
var _since_down_left := 1e9
var _since_recline_left := 1e9
var _first := true


func has_up_sense() -> bool:
	return up_sense_mode == "yes" or (up_sense_mode == "auto" and up_sense_seen)


## Feed the three contacts every frame. Returns a list of callout events:
## "reclined", "pod_coming_down", "pod_down", "pod_going_up", "pod_up", "seats_coming_up".
func update(dt: float, reclined: bool, down: bool, up: bool) -> Array[String]:
	var ev: Array[String] = []
	if up:
		up_sense_seen = true
	_since_down_left += dt
	_since_recline_left += dt
	if not _first:
		if reclined and not _reclined:
			ev.append("reclined")
			if not has_up_sense():
				ev.append("pod_coming_down")      # next motion (FLT held + lever) is the pod
		if has_up_sense() and _up and not up and reclined and not down:
			ev.append("pod_coming_down")
		if down and not _down:
			ev.append("pod_down")
		if _down and not down:
			ev.append("pod_going_up")
			_since_down_left = 0.0
		if has_up_sense() and up and not _up and not _first:
			ev.append("pod_up")
		if _reclined and not reclined:
			ev.append("seats_coming_up")
			_since_recline_left = 0.0
	_first = false
	_reclined = reclined
	_down = down
	_up = up
	# pod
	if down:
		pod = Pod.DOWN_LOCKED
	elif not reclined:
		pod = Pod.UP
	elif has_up_sense():
		pod = Pod.UP if up else Pod.MOVING
	elif _since_down_left < travel_s:
		pod = Pod.MOVING
	else:
		pod = Pod.UNKNOWN_UP_OR_MOVING
	# seats
	if reclined:
		seats = Seats.RECLINED
	elif _since_recline_left < travel_s:
		seats = Seats.MOVING
	else:
		seats = Seats.UPRIGHT
	return ev


func pod_text() -> String:
	return POD_NAMES[pod]


func seats_text() -> String:
	return SEAT_NAMES[seats]


static func callout_text(e: String) -> String:
	return str({
		"reclined": "Seats reclined.",
		"pod_coming_down": "Stand by, pod coming down. Heads back, hands in.",
		"pod_down": "Pod down and locked.",
		"pod_going_up": "Pod going up.",
		"pod_up": "Pod up and locked.",
		"seats_coming_up": "Seats coming up. Hands in.",
	}.get(e, ""))
