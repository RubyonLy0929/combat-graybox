extends RefCounted
## Character-owned event bus, persistent cooldowns and equipment proc policy.
const Loadout := preload("res://scripts/systems/equipment_loadout.gd")
signal combat_event(event_name: String, payload: Dictionary)
var actor
var clock: float = 0.0
var cooldowns: Dictionary = {}
var proc_cooldowns: Dictionary = {}
var prepared: Dictionary = {}
var equipment_keys: Array[String] = ["boots", "body"]
var rage_remaining: float = 0.0
var stability_remaining: float = 0.0
var stability_hits: int = 0

func _init(owner_actor) -> void:
	actor = owner_actor

func emit_event(event_name: String, payload: Dictionary) -> void:
	combat_event.emit(event_name, payload)

func tick(delta: float) -> void:
	clock += delta
	if rage_remaining > 0.0:
		rage_remaining = maxf(0.0, rage_remaining - delta)
		if rage_remaining <= 0.0: refresh_rage_buff(false)
	if stability_remaining > 0.0:
		stability_remaining = maxf(0.0, stability_remaining - delta)
		actor.restore_health(actor.max_health * 0.02 * delta)
		if stability_remaining <= 0.0: stability_hits = 0

func passive_snapshot() -> Array:
	var result: Array = []
	var groups: Dictionary = {}
	for item in actor.character_state.equipment.contributing_items():
		for effect in item.definition.effects:
			var group: String = str(effect.get("id", ""))
			if group.is_empty() or groups.has(group): continue
			groups[group] = true
			result.append(effect.duplicate(true))
	return result

func has_effect(effects: Array, effect_id: String) -> bool:
	for effect in effects:
		if effect.get("id", "") == effect_id: return true
	return false

func effect_value(effects: Array, effect_id: String, key: String, fallback: float) -> float:
	for effect in effects:
		if effect.get("id", "") == effect_id: return float(effect.get(key, fallback))
	return fallback

func snapshot(kind: String, step: int, skill: Dictionary = {}) -> Dictionary:
	var item = actor.character_state.equipment.active_weapon()
	var instance: String = item.instance_id if item != null else ""
	var values: Dictionary = actor.character_state.stats
	var record: Dictionary = prepared.get(instance, {})
	return {"kind": kind, "step": step, "chain": actor.chain_id,
		"weapon": actor.weapon, "instance": instance,
		"prepared": record.get("chain", -1) == actor.chain_id and int(record.get("mask", 0)) == 3,
		"cross": actor.chain_switched, "effects": passive_snapshot(),
		"lifesteal": float(values.lifesteal), "base": float(values.damage),
		"skill_id": str(skill.get("id", "")), "cooldown_group": str(skill.get("cooldown_group", skill.get("id", ""))),
		"rewarded": false, "hit_targets": [], "piercing": false,
		"attack_id": actor.get_instance_id() * 1000000 + actor.attack_serial, "source_id": actor.get_instance_id()}

func proc_ready(group: String, delay: float) -> bool:
	if float(proc_cooldowns.get(group, 0.0)) > clock: return false
	proc_cooldowns[group] = clock + delay
	return true

func pay_attack_cost(context: Dictionary) -> bool:
	if context.kind != "normal" or not has_effect(context.effects, "blood_cost"): return true
	var cost: float = actor.max_health * effect_value(context.effects, "blood_cost", "cost", 0.01)
	if actor.health - cost < 1.0:
		actor.get_parent().notify_player("生命不足，无法支付血契出手成本")
		return false
	actor.health -= cost
	actor.sync_resources()
	emit_event("health_cost_paid", {"amount": cost, "attack_id": context.attack_id})
	trigger_rage(context.effects)
	return true

func trigger_rage(effects: Array) -> void:
	if not has_effect(effects, "hurt_rage") or not proc_ready("hurt_rage", 0.5): return
	rage_remaining = 1.5
	refresh_rage_buff(true)

func refresh_rage_buff(enabled: bool) -> void:
	var state = actor.character_state
	for i in range(state.buffs.size() - 1, -1, -1):
		if state.buffs[i].get("id", "") == "hurt_rage": state.buffs.remove_at(i)
	if enabled: state.buffs.append({"id": "hurt_rage", "flat": {"attack_speed": 0.15, "lifesteal": 0.04}})
	actor.sync_resources()
	state.recalculate()

func on_health_damage(amount: float) -> void:
	if amount <= 0.0 or actor.health <= 0.0: return
	emit_event("health_damage", {"amount": amount})
	trigger_rage(passive_snapshot())

func ignore_interrupt() -> bool:
	if stability_remaining <= 0.0 or stability_hits <= 0: return false
	stability_hits -= 1
	return true

func before_hit(target, context: Dictionary) -> Dictionary:
	var result: Dictionary = {"multiplier": 1.0, "defense_ratio": 1.0, "consume": false, "extra": 0.0}
	if context.get("kind", "") != "normal": return result
	var status: String = target.tactical_status
	var step: int = int(context.step)
	var type: int = int(context.weapon)
	if type == 0 and step == 2 and context.cross and status == "破绽":
		context.piercing = true
		result.consume = true
	elif type == 1 and step == 3 and context.cross and status == "破绽":
		result.defense_ratio = 0.8
		result.consume = true
	elif type == 2 and step == 3 and context.prepared and status == "牵制":
		result.extra = float(context.base) * 0.25
		result.consume = true
	elif type == 3 and step == 3 and context.prepared:
		if actor.position.distance_to(target.position) >= float(context.get("range", 190.0)) * 0.6:
			result.multiplier = 1.2
	elif type == 4 and step == 3:
		if context.cross and status == "失衡":
			result.multiplier = 1.2
			result.consume = true
		elif context.prepared and status == "猎印":
			context.piercing = true
			result.consume = true
	return result

func on_hit(target, context: Dictionary, actual: float, modifiers: Dictionary) -> void:
	if actual <= 0.0 or context.get("kind", "") == "secondary": return
	emit_event("direct_hit", {"target": target, "actual_damage": actual, "context": context})
	if modifiers.get("consume", false): target.set_tactical_status("", 0.0)
	var hits: Array = context.hit_targets
	hits.append(weakref(target))
	if context.kind == "normal":
		register_preparation(context)
		apply_tactical_status(target, context)
	actor.restore_health(actual * float(context.lifesteal))
	if not context.rewarded:
		context.rewarded = true
		emit_event("attack_hit_group", {"context": context})
		if has_effect(context.effects, "hit_heal") and proc_ready("hit_heal", 0.5):
			actor.restore_health(actor.max_health * effect_value(context.effects, "hit_heal", "amount", 0.005))
		if has_effect(context.effects, "hit_mana") and proc_ready("hit_mana", 0.5):
			actor.restore_mana(effect_value(context.effects, "hit_mana", "amount", 2.0))
	if float(modifiers.get("extra", 0.0)) > 0.0 and target.health > 0.0:
		target.take_hit(float(modifiers.extra), 0.0, Vector2.ZERO, 0.0, {"kind": "secondary"})
	if target.health <= 0.0:
		emit_event("kill", {"target": target, "context": context})
		if context.skill_id == "pursuit_dash":
			var group: String = context.cooldown_group
			cooldowns[group] = minf(float(cooldowns.get(group, clock)), clock + 0.8)

func register_preparation(context: Dictionary) -> void:
	if int(context.chain) != actor.chain_id or int(context.step) > 1: return
	var id: String = context.instance
	var record: Dictionary = prepared.get(id, {"chain": actor.chain_id, "mask": 0})
	if int(record.chain) != actor.chain_id: record = {"chain": actor.chain_id, "mask": 0}
	record.mask = int(record.mask) | (1 << int(context.step))
	prepared[id] = record

func apply_tactical_status(target, context: Dictionary) -> void:
	if int(context.step) != 1: return
	match int(context.weapon):
		1:
			if target.rank == 2 or target.last_push_distance >= target.radius * 2.0 * 0.15:
				target.set_tactical_status("失衡", 2.0)
		2:
			if context.hit_targets.size() >= 2:
				for reference in context.hit_targets:
					var other = reference.get_ref()
					if is_instance_valid(other) and other.health > 0.0: other.set_tactical_status("牵制", 2.0)
		3:
			if actor.position.distance_to(target.position) >= float(context.range) * 0.6:
				target.set_tactical_status("破绽", 2.0)
		4: target.set_tactical_status("猎印", 2.0)

func equipment_skill_slots() -> Array[String]:
	var result: Array[String] = []
	for key in Loadout.SLOTS:
		if str(key).begins_with("weapon_"): continue
		var item = actor.character_state.equipment.slots.get(key)
		if item != null and not item.definition.active_skill.is_empty(): result.append(key)
	return result

func cycle_equipment_key(index: int) -> void:
	var options: Array[String] = [""]
	options.append_array(equipment_skill_slots())
	var next: int = (options.find(equipment_keys[index]) + 1) % options.size()
	var choice: String = options[next]
	if not choice.is_empty() and equipment_keys[1 - index] == choice:
		choice = options[(next + 1) % options.size()]
	equipment_keys[index] = choice

func skill_for_key(key: int) -> Dictionary:
	var item
	if key == 1: item = actor.character_state.equipment.active_weapon()
	elif key in [2, 3]: item = actor.character_state.equipment.slots.get(equipment_keys[key - 2])
	if item == null or item.definition.active_skill.is_empty(): return {}
	var skill: Dictionary = item.definition.active_skill.duplicate(true)
	skill["source_name"] = item.definition.display_name
	skill["source_instance"] = item.instance_id
	return skill

func remaining(skill: Dictionary) -> float:
	var group: String = str(skill.get("cooldown_group", skill.get("id", "")))
	return maxf(0.0, float(cooldowns.get(group, 0.0)) - clock)

func activate(skill: Dictionary) -> bool:
	if skill.is_empty() or remaining(skill) > 0.0: return false
	var cost: float = float(skill.get("mana", 0.0))
	if actor.mana < cost:
		actor.get_parent().notify_player("法力不足：" + str(skill.get("name", "技能")))
		return false
	actor.mana -= cost
	actor.sync_resources()
	var group: String = str(skill.get("cooldown_group", skill.get("id", "")))
	cooldowns[group] = clock + float(skill.get("cooldown", 0.0))
	emit_event("skill_cast", {"skill": skill})
	if skill.get("mode", "") == "stability":
		stability_remaining = 1.5
		stability_hits = 2
	return true
