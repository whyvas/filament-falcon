extends Node
func _ready() -> void:
	print("map: ", InputHub.map_source, " errors: ", InputHub.map_errors)
	print("led unknown: ", LedLink.unknown_labels)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()
