extends "res://scripts/data/item_definition.gd"
@export var inventory_size: Vector2i = Vector2i(8, 6)
@export var carry_capacity_bonus: float = 0.0
## Reduces effective burden only, not physical mass.
@export_range(0.0, 0.8) var burden_reduction: float = 0.0
func _init() -> void:
	item_type = "backpack"
	max_stack = 1
