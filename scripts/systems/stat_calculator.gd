extends RefCounted
const Config := preload("res://scripts/data/stat_config.gd")
const Weapon := preload("res://scripts/data/weapon_definition.gd")
const Armor := preload("res://scripts/data/armor_definition.gd")
const Backpack := preload("res://scripts/data/backpack_definition.gd")
const CORES := ["strength", "agility", "constitution", "spirit"]
static func calculate(profile, loadout, inventory: Array, buffs: Array = [], config: Config = null) -> Dictionary:
	var c: Config = config if config != null else Config.new()
	var flat: Dictionary = {}
	var percent: Dictionary = {}
	var unknown: Array[String] = []
	var valid: Array = profile.base.keys() + CORES
	var parts: Array = []
	for item in loadout.contributing_items():
		var d = item.definition
		_merge(flat, d.flat, valid, unknown)
		_merge(percent, d.percent, valid, unknown)
		parts.append({"source": d.id, "flat": d.flat.duplicate(true), "percent": d.percent.duplicate(true)})
		if d is Armor:
			_add(flat, "defense", d.defense)
			_add(flat, "knockback_resistance", d.knockback_resistance)
		if d is Backpack:
			_add(flat, "carry_capacity", d.carry_capacity_bonus)
			_add(flat, "burden_reduction", d.burden_reduction)
	for buff in buffs:
		_merge(flat, buff.get("flat", {}), valid, unknown)
		_merge(percent, buff.get("percent", {}), valid, unknown)
	var stats: Dictionary = {}
	for key in CORES:
		stats[key] = maxf(0.0, (float(profile.get(key)) + float(flat.get(key, 0.0))) * maxf(0.0, 1.0 + float(percent.get(key, 0.0))))
	var con := maxf(0.0, stats.constitution - c.attribute_baseline)
	var spi := maxf(0.0, stats.spirit - c.attribute_baseline)
	var str_gain := maxf(0.0, stats.strength - c.attribute_baseline)
	var agi := maxf(0.0, stats.agility - c.attribute_baseline)
	var diminishing := agi / (agi + maxf(0.001, c.agility_half_saturation))
	var derived: Dictionary = profile.base.duplicate(true)
	_add(derived, "max_health", con * c.health_per_constitution)
	_add(derived, "max_mana", spi * c.mana_per_spirit)
	_add(derived, "health_regen", con * c.health_regen_per_constitution)
	_add(derived, "mana_regen", spi * c.mana_regen_per_spirit)
	_add(derived, "magic_power", spi * c.magic_per_spirit)
	_add(derived, "carry_capacity", str_gain * c.capacity_per_strength)
	_add(derived, "move_multiplier", (c.max_move_multiplier - 1.0) * diminishing)
	_add(derived, "attack_speed", (c.max_attack_speed - 1.0) * diminishing)
	_add(derived, "crit_chance", c.agility_crit_gain * diminishing)
	var active = loadout.active_weapon()
	if active != null and active.definition is Weapon:
		var w = active.definition
		_add(derived, "damage", maxf(0.0, w.base_damage) + str_gain * w.strength_scaling + agi * w.agility_scaling)
		stats["weapon_type"] = w.weapon_type
		stats["attack_template"] = w.attack_template
		stats["attack_range"] = maxf(0.0, w.attack_range)
		stats["impact_multiplier"] = maxf(0.0, w.impact_multiplier)
	else:
		stats["weapon_type"] = "unarmed"
		stats["attack_template"] = -1
		stats["attack_range"] = 0.0
		stats["impact_multiplier"] = 1.0
	for key in derived:
		stats[key] = maxf(0.0, (float(derived[key]) + float(flat.get(key, 0.0))) * maxf(0.0, 1.0 + float(percent.get(key, 0.0))))
	stats.max_health = maxf(1.0, stats.max_health)
	stats.carry_capacity = maxf(0.001, stats.carry_capacity)
	stats.crit_multiplier = maxf(1.0, stats.crit_multiplier)
	stats.crit_chance = clampf(stats.crit_chance, 0.0, c.max_crit_chance)
	stats.lifesteal = clampf(stats.lifesteal, 0.0, c.max_lifesteal)
	stats.burden_reduction = clampf(stats.burden_reduction, 0.0, c.max_burden_reduction)
	stats.knockback_resistance = clampf(stats.knockback_resistance, 0.0, c.max_knockback_resistance)
	stats.move_multiplier = clampf(stats.move_multiplier, 0.0, c.max_move_multiplier)
	stats.attack_speed = clampf(stats.attack_speed, 0.0, c.max_attack_speed)
	# Exactly one physical copy per instance_id; inventory and equipment may reference the same copy.
	var mass := 0.0
	var seen: Dictionary = {}
	for item in inventory + loadout.slots.values():
		if item == null or seen.has(item.instance_id): continue
		seen[item.instance_id] = true
		mass += item.actual_weight()
	stats["actual_weight"] = mass
	stats["effective_burden"] = mass * (1.0 - stats.burden_reduction)
	var ratio: float = stats.effective_burden / stats.carry_capacity
	stats["burden_ratio"] = ratio
	var at_capacity := clampf((ratio - c.penalty_start_ratio) / maxf(0.001, 1.0 - c.penalty_start_ratio), 0.0, 1.0)
	var overload := maxf(0.0, ratio - 1.0)
	stats["move_burden_factor"] = maxf(c.min_move_factor, 1.0 - c.move_penalty_at_capacity * at_capacity - c.move_penalty_per_overload * overload)
	stats["attack_burden_factor"] = maxf(c.min_attack_factor, 1.0 - c.attack_penalty_at_capacity * at_capacity - c.attack_penalty_per_overload * overload)
	stats["unburdened_move_speed"] = minf(stats.move_speed * stats.move_multiplier, maxf(0.0, float(profile.base.get("move_speed", 200.0))) * c.max_move_multiplier)
	stats["final_move_speed"] = stats.unburdened_move_speed * stats.move_burden_factor
	stats["final_attack_speed"] = maxf(0.01, stats.attack_speed * stats.attack_burden_factor)
	stats["mass_resistance"] = mass / (mass + maxf(0.001, c.mass_half_resistance))
	stats["final_knockback_resistance"] = 1.0 - (1.0 - stats.mass_resistance) * (1.0 - stats.knockback_resistance)
	stats["inventory_size"] = Vector2i(8, 6)
	var bag = loadout.slots.get("backpack")
	if bag != null: stats.inventory_size = bag.definition.inventory_size.max(Vector2i.ONE)
	return {"stats": stats, "sources": parts, "flat_totals": flat, "percent_totals": percent, "unknown_stats": unknown}
static func _add(values: Dictionary, key: String, amount: float) -> void:
	values[key] = float(values.get(key, 0.0)) + amount
static func _merge(target: Dictionary, source: Dictionary, valid: Array, unknown: Array[String]) -> void:
	for key in source:
		if not valid.has(key):
			if not unknown.has(str(key)): unknown.append(str(key))
			continue
		_add(target, key, float(source[key]))
static func damage_after_defense(raw: float, defense: float, config: Config = null) -> float:
	var c: Config = config if config != null else Config.new()
	var k := maxf(0.001, c.defense_constant)
	return maxf(0.0, raw) * k / (k + maxf(0.0, defense))
static func knockback_distance(body_width: float, fraction: float, strength: float, damage_ratio: float, stats: Dictionary) -> float:
	var impulse := -log(1.0 - clampf(fraction, 0.0, 0.99))
	impulse *= (0.7 + 0.2 * maxf(0.0, strength) / 10.0 + 0.1 * clampf(damage_ratio, 0.0, 3.0))
	impulse *= 1.0 - clampf(stats.get("final_knockback_resistance", 0.0), 0.0, 1.0)
	return maxf(0.0, body_width) * (1.0 - exp(-impulse))
