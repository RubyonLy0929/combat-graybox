extends RefCounted
const Profile := preload("res://scripts/data/character_profile.gd")
const Config := preload("res://scripts/data/stat_config.gd")
const Loadout := preload("res://scripts/systems/equipment_loadout.gd")
const Calculator := preload("res://scripts/systems/stat_calculator.gd")
signal stats_changed(stats: Dictionary)
var profile: Profile
var config: Config
var equipment := Loadout.new()
var inventory: Array = []
var buffs: Array = []
var gold: int = 0
## Key quest pickups are tracked independently, with no grid or weight usage.
var quest_items: Dictionary = {}
var health: float = 0.0
var mana: float = 0.0
var stats: Dictionary = {}
var breakdown: Dictionary = {}
func _init(base_profile: Profile = null, tuning: Config = null) -> void:
	profile = base_profile if base_profile != null else Profile.new()
	config = tuning if tuning != null else Config.new()
	recalculate()
	health = stats.max_health
	mana = stats.max_mana
func recalculate() -> void:
	breakdown = Calculator.calculate(profile, equipment, inventory, buffs, config)
	stats = breakdown.stats
	# Equipment changes never heal or replenish mana.
	health = clampf(health, 0.0, stats.max_health)
	mana = clampf(mana, 0.0, stats.max_mana)
	stats_changed.emit(stats.duplicate(true))
func equip(slot_name: String, item) -> Dictionary:
	var result := equipment.equip(slot_name, item)
	if result.ok: recalculate()
	return result
func unequip(slot_name: String):
	var previous = equipment.slots.get(slot_name)
	equipment.slots.erase(slot_name)
	recalculate()
	return previous
func set_active_weapon(slot_name: String) -> bool:
	if not ["weapon_a", "weapon_b"].has(slot_name): return false
	equipment.active_weapon_slot = slot_name
	recalculate()
	return true
func tick_regeneration(delta: float) -> void:
	if health <= 0.0: return
	health = minf(stats.max_health, health + stats.health_regen * maxf(0.0, delta))
	mana = minf(stats.max_mana, mana + stats.mana_regen * maxf(0.0, delta))
func spend_mana(amount: float) -> bool:
	if amount < 0.0 or mana < amount: return false
	mana -= amount
	return true
func add_gold(amount: int) -> bool:
	if amount < 0: return false
	gold += amount
	return true
func spend_gold(amount: int) -> bool:
	if amount < 0 or gold < amount: return false
	gold -= amount
	return true
