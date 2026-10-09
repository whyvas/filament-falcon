class_name CameraOverlay
extends Control
## Crosshairs / readouts drawn over the console camera feeds.

var kind := ""
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font


func _process(_dt: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var col := Color(0.4, 1.0, 0.6, 0.8)
	var gd: Dictionary = Game.mission.guidance if Game.mission else {}
	match kind:
		"DOCKING CAMERA":
			draw_line(c - Vector2(60, 0), c - Vector2(15, 0), col, 2.0)
			draw_line(c + Vector2(15, 0), c + Vector2(60, 0), col, 2.0)
			draw_line(c - Vector2(0, 60), c - Vector2(0, 15), col, 2.0)
			draw_line(c + Vector2(0, 15), c + Vector2(0, 60), col, 2.0)
			draw_arc(c, 90.0, 0, TAU, 48, Color(col, 0.4), 2.0)
			if gd.has("docking"):
				var info: Dictionary = gd["docking"]
				draw_string(font, Vector2(14, size.y - 50), "RANGE %.1f m" % float(info["range"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, col)
				draw_string(font, Vector2(14, size.y - 18), "CLOSING %.2f m/s" % float(info["closing"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, col)
		"ARM CAMERA":
			draw_arc(c, 40.0, 0, TAU, 32, Color(0.4, 0.8, 1.0, 0.8), 3.0)
			var txt := "ARM %s   BEAM %s" % ["READY" if Game.arm_extend > 0.95 else "STOWED", "ON" if Game.beam_on else "OFF"]
			draw_string(font, Vector2(14, size.y - 18), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.4, 0.8, 1.0))
		_:
			draw_string(font, Vector2(14, size.y - 18), "SPEED %d m/s" % int(Game.sim.surface_vel.length()), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, col)
	draw_string(font, Vector2(14, 34), kind + "  ● REC" if fmod(Time.get_ticks_msec() / 500.0, 2.0) < 1.0 else kind, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 0.4, 0.4))
