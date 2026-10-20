extends "res://scripts/data/item_definition.gd"
@export_enum("sword", "blade", "whip", "spear", "bow") var weapon_type: String = "sword"
@export var base_damage: float = 18.0
@export var strength_scaling: float = 0.5
@export var agility_scaling: float = 0.2
@export var attack_template: int = 0
@export var damage_type: String = "physical"
@export var attack_range: float = 100.0
@export var impact_multiplier: float = 1.0
func _init() -> void:
	item_type = "weapon"
	max_stack = 1
