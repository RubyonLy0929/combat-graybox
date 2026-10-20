extends "res://scripts/data/item_definition.gd"
@export_enum("belt", "body", "legs", "boots", "gloves", "helmet") var slot: String = "body"
## Descriptive only: no movement penalty or resistance inferred from this label.
@export_enum("cloth", "light", "heavy") var armor_material: String = "light"
@export var defense: float = 0.0
@export var knockback_resistance: float = 0.0
func _init() -> void:
	item_type = "armor"
	max_stack = 1
