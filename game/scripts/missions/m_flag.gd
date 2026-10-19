extends "res://scripts/missions/m_lunar.gd"
## PLANT THE FLAG: the lunar landing, then a MOONWALK spacewalk (VR or on screen) to plant the
## flag and collect moon rocks. (Mars is not in the game universe yet: Moon only.)


func setup() -> void:
	super.setup()
	id = "flag"
	title = "PLANT THE FLAG"
	tagline = "Land on the Moon and plant our flag"
	briefing = "We land on the Moon, then one of us climbs down the ladder, plants our flag and picks up moon rocks. One small step!"
	start_callout = "Moon landing and moonwalk. Altitude 9 kilometres."
	star_thresholds = [1300, 1900]
	objectives.append({"text": "ENGINE ARM off, then MOONWALK: plant the flag!", "role": "EVA"})


func update(dt: float) -> void:
	if step < 4:
		super.update(dt)
		return
	if not eva_inserted and not Eva.active:
		if "moonwalk" in Eva.available():
			start_eva_step("moonwalk")
		else:
			guidance["flash"] = "ENGINE ARM OFF"


func cheat_advance() -> void:
	if step >= 4:
		advance()
	else:
		super.cheat_advance()


func final_score() -> void:
	super.final_score()
	game.add_score("Flag planted", 300)
