extends Resource
@export var strength: float = 10.0
@export var agility: float = 10.0
@export var constitution: float = 10.0
@export var spirit: float = 10.0
## Baseline derived stats before core-attribute growth and equipment.
@export var base: Dictionary = {
	"max_health": 100.0, "max_mana": 50.0,
	"health_regen": 0.0, "mana_regen": 1.0, "magic_power": 0.0,
	"damage": 0.0, "defense": 0.0, "move_speed": 200.0,
	"move_multiplier": 1.0, "attack_speed": 1.0,
	"crit_chance": 0.0, "crit_multiplier": 1.5, "lifesteal": 0.0,
	"carry_capacity": 30.0, "knockback_resistance": 0.0,
	"burden_reduction": 0.0
}
