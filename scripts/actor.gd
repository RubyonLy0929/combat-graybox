extends CharacterBody2D
const Rules := preload("res://scripts/combat_rules.gd")
const Weapons := preload("res://scripts/weapons.gd")
const CharacterState := preload("res://scripts/systems/character_state.gd")
const CharacterProfile := preload("res://scripts/data/character_profile.gd")
const ItemInstance := preload("res://scripts/systems/item_instance.gd")
const Catalog := preload("res://scripts/data/starter_catalog.gd")
const Stats := preload("res://scripts/systems/stat_calculator.gd")
const GridInventory := preload("res://scripts/systems/grid_inventory.gd")
const CombatRuntime := preload("res://scripts/systems/combat_runtime.gd")
const DelayedAttack := preload("res://scripts/delayed_attack.gd")
const EightWayVisual := preload("res://scripts/visuals/eight_way_visual.gd")
var runtime
var chain_id: int = 0
var chain_switched: bool = false
var attack_serial: int = 0
var cross_remaining: float = 0.0
var pending_switch: bool = false
var switching: bool = false
var weapon_signature: String = ""
var queued_skill: Dictionary = {}
var queued_skill_remaining: float = 0.0
var tactical_status: String = ""
var tactical_remaining: float = 0.0
var skill_slow: float = 1.0
var skill_slow_remaining: float = 0.0
var skill_root_remaining: float = 0.0
var attack_chain_invalidated: bool = false
var death_sent: bool = false
var inventory_model
var visual
var input_buffer := 0.0
var attack_requires_release := false
var facing_octant := 0
var character_state
var mana := 0.0
var max_mana := 0.0

func initialize_character_data() -> void:
	var profile = preload("res://data/default_character.tres").duplicate(true)
	profile.base["max_health"] = max_health
	profile.base["move_speed"] = Rules.MOVE_SPEED
	character_state = CharacterState.new(profile, preload("res://data/stat_config.tres").duplicate(true))
	character_state.health = health
	if is_player:
		character_state.equip("weapon_a", ItemInstance.new(Catalog.weapon(slots[0])))
		character_state.equip("weapon_b", ItemInstance.new(Catalog.weapon(slots[1])))
	character_state.stats_changed.connect(on_stats_changed)
	character_state.recalculate()
	inventory_model = GridInventory.new(character_state)
	runtime = CombatRuntime.new(self)
	weapon_signature = loadout_weapon_signature()

func on_stats_changed(values: Dictionary) -> void:
	if runtime != null and not switching:
		var signature: String = loadout_weapon_signature()
		if signature != weapon_signature:
			attack_chain_invalidated = phase != "idle"
			chain_id += 1
			reset_chain()
			pending_switch = false
			queued_skill.clear()
		weapon_signature = signature
	max_health = values.max_health
	max_mana = values.max_mana
	health = character_state.health
	mana = character_state.mana
	carried_weight = values.actual_weight
	if is_player:
		for i in range(2):
			var item = character_state.equipment.slots.get("weapon_a" if i == 0 else "weapon_b")
			slots[i] = item.definition.attack_template if item != null else -1
		slot = 0 if character_state.equipment.active_weapon_slot == "weapon_a" else 1
		weapon = slots[slot]

func loadout_weapon_signature() -> String:
	var result: String = ""
	for key in ["weapon_a", "weapon_b"]:
		var item = character_state.equipment.slots.get(key)
		result += (item.instance_id if item != null else "empty") + ":"
	return result

func sync_resources() -> void:
	if character_state == null: return
	character_state.health = health
	character_state.mana = mana

func restore_health(amount: float) -> void:
	if health <= 0.0: return
	health = minf(max_health, health + maxf(0.0, amount))
	sync_resources()

func restore_mana(amount: float) -> void:
	if health <= 0.0: return
	mana = minf(max_mana, mana + maxf(0.0, amount))
	sync_resources()

func receive_lifesteal(actual_damage: float) -> void:
	restore_health(maxf(0.0, actual_damage) * float(character_state.stats.lifesteal))

func set_tactical_status(value: String, duration: float) -> void:
	tactical_status = value
	tactical_remaining = duration
	queue_redraw()

func reset_chain() -> void:
	next_combo = 0
	combo_window = 0.0
	cross_remaining = 0.0
	chain_switched = false
	if runtime != null: runtime.prepared.clear()

var is_player := false
var rank := 0
var ranged_enemy := false
var dummy := false
var title := "近战怪"
var radius := 18.0
var health := 180.0
var max_health := 180.0
var facing := Vector2.RIGHT
var weapon := 0
var slots := [0,4]
var slot := 0
var switch_remaining := 0.0
var target
var phase := "idle"
var phase_remaining := 0.0
var active_elapsed := 0.0
var attack_data: Dictionary = {}
var attack_facing := Vector2.RIGHT
var shot_direction := Vector2.RIGHT
var combo := 0
var next_combo := 0
var combo_window := 0.0
var buffered := false
var hit_ids: Dictionary = {}
var stagger := 0.0
var flash := 0.0
var carried_weight := 0.0
var armor_type := "light"
var last_push_distance := 0.0
var push_direction := Vector2.ZERO
var push_remaining := 0.0
var push_used := 0.0
var push_speed := 0.0
var shot_done := false
var interrupted := false
var path_remaining := 0.0
var path := PackedVector2Array()
var path_index := 0
var walk_time := 0.0

func _ready() -> void:
	initialize_character_data()
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2 if is_player else 4
	collision_mask = 1 | 2 | 4
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	add_to_group("players" if is_player else "enemies")
	visual = EightWayVisual.new()
	add_child(visual)

func _unhandled_input(event: InputEvent) -> void:
	if not is_player or get_parent().inventory_open or health <= 0.0 or get_parent().get("combat_frozen") == true or get_parent().get("mechanism_moving") == true: return
	if event is InputEventKey:
		if not event.pressed or event.echo: return
		match event.physical_keycode:
			KEY_Q: switch_weapon()
			KEY_1: request_skill(1)
			KEY_2: request_skill(2)
			KEY_3: request_skill(3)
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			switch_weapon()
			get_viewport().set_input_as_handled()

func switch_weapon() -> void:
	if health <= 0.0 or switch_remaining > 0.0 or phase == "transition": return
	var destination: String = "weapon_b" if slot == 0 else "weapon_a"
	if character_state.equipment.slots.get(destination) == null: return
	if phase in ["windup", "active"]:
		pending_switch = true
		return
	if phase == "recovery" and cross_remaining <= 0.0:
		pending_switch = true
		return
	execute_switch(phase == "recovery" or cross_remaining > 0.0)

func execute_switch(inherit: bool) -> void:
	if switch_remaining > 0.0:
		pending_switch = false
		return
	var destination: String = "weapon_b" if slot == 0 else "weapon_a"
	if character_state.equipment.slots.get(destination) == null:
		pending_switch = false
		return
	sync_resources()
	switching = true
	character_state.set_active_weapon(destination)
	switching = false
	pending_switch = false
	switch_remaining = 0.35
	if not inherit or next_combo == 0:
		reset_chain()
	else:
		chain_switched = true
	phase = "transition"
	phase_remaining = 0.10
	queued_skill.clear()
	if runtime != null: runtime.emit_event("switch", {"inherits": inherit, "next_step": next_combo})

func request_skill(key: int) -> void:
	var skill: Dictionary = runtime.skill_for_key(key)
	if get_parent().get("hold_fire") == true and float(skill.get("multiplier", 0.0)) > 0.0: return
	if skill.is_empty(): return
	if phase == "idle" and stagger <= 0.0:
		begin_skill(skill)
	else:
		queued_skill = skill
		queued_skill_remaining = 0.7

func begin_skill(skill: Dictionary) -> void:
	if phase != "idle" or health <= 0.0 or stagger > 0.0: return
	# A buffered request must still belong to a currently equipped, selected source.
	var valid: bool = false
	for key in [1, 2, 3]:
		var current: Dictionary = runtime.skill_for_key(key)
		if current.get("source_instance", "") == skill.get("source_instance", "") and current.get("id", "") == skill.get("id", ""):
			valid = true
	queued_skill.clear()
	if not valid or not runtime.activate(skill): return
	reset_chain()
	attack_serial += 1
	combo = 0
	attack_data = Weapons.skill_step(weapon, skill)
	attack_data["skill"] = skill.duplicate(true)
	if skill.get("mode", "") == "sidestep":
		var movement: Vector2 = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))).normalized()
		attack_data["dash_direction"] = movement if not movement.is_zero_approx() else -mouse_direction()
	attack_data["context"] = runtime.snapshot("skill", 0, skill)
	configure_attack_values(false)
	start_attack_phase()
	queued_skill.clear()

func mouse_direction() -> Vector2:
	var offset := get_global_mouse_position() - global_position
	return offset.normalized() if offset.length() > 6.0 else facing

func _physics_process(delta: float) -> void:
	if get_parent().get("combat_frozen") == true or get_parent().get("mechanism_moving") == true: return
	if character_state != null and not get_parent().combat_over:
		character_state.health = health
		character_state.mana = mana
		character_state.tick_regeneration(delta)
		health = character_state.health
		mana = character_state.mana
	if health > 0.0 and not get_parent().combat_over:
		runtime.tick(delta)
	tactical_remaining = maxf(0.0, tactical_remaining - delta)
	if tactical_remaining <= 0.0: tactical_status = ""
	skill_slow_remaining = maxf(0.0, skill_slow_remaining - delta)
	if skill_slow_remaining <= 0.0: skill_slow = 1.0
	skill_root_remaining = maxf(0.0, skill_root_remaining - delta)
	cross_remaining = maxf(0.0, cross_remaining - delta)
	queued_skill_remaining = maxf(0.0, queued_skill_remaining - delta)
	if queued_skill_remaining <= 0.0: queued_skill.clear()
	flash = maxf(0.0, flash - delta)
	switch_remaining = maxf(0.0, switch_remaining - delta)
	stagger = maxf(0.0, stagger - delta)
	combo_window = maxf(0.0, combo_window - delta)
	input_buffer = maxf(0.0, input_buffer - delta)
	if phase == "idle" and combo_window <= 0.0 and cross_remaining <= 0.0: reset_chain()
	var desired := Vector2.ZERO
	if health > 0.0 and not get_parent().combat_over:
		if is_player:
			desired = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))).normalized()
			if attack_requires_release and not Input.is_action_pressed("attack"): attack_requires_release = false
			if not attack_requires_release and Input.is_action_just_pressed("attack"): input_buffer = 0.15
			if phase == "idle":
				if not queued_skill.is_empty() and stagger <= 0.0: begin_skill(queued_skill.duplicate(true))
				if phase == "idle" and not desired.is_zero_approx(): facing = desired
				if phase == "idle" and queued_skill.is_empty() and not attack_requires_release and stagger <= 0.0 and weapon >= 0 and (input_buffer > 0.0 or Input.is_action_pressed("attack")):
					facing = mouse_direction()
					begin_attack()
			elif phase == "windup":
				facing = mouse_direction()
				attack_facing = facing
				shot_direction = facing
		elif not dummy and not get_parent().freeze_ai and phase == "idle" and stagger <= 0.0:
			desired = enemy_input(delta)
			if phase == "idle" and not desired.is_zero_approx(): facing = desired
		if phase != "idle":
			advance_attack(delta)
	if phase != "idle":
		var factors: Array = Weapons.MOVE_FACTORS[maxi(0, int(attack_data.get("weapon", weapon)))] if is_player else [0.3, 0.15, 0.5]
		var phase_index: int = {"windup": 0, "active": 1, "recovery": 2}.get(phase, 2)
		desired *= 0.75 if phase == "transition" else (float(attack_data.get("movement", factors[phase_index])) if attack_data.has("skill") else float(factors[phase_index]))
	if stagger > 0.0 or health <= 0.0 or get_parent().combat_over: desired = Vector2.ZERO
	var slow: float = minf(skill_slow, 0.85 if tactical_status == "牵制" else 1.0)
	if skill_root_remaining > 0.0: desired = Vector2.ZERO
	velocity = desired * float(character_state.stats.final_move_speed) * slow
	move_and_slide()
	if desired.length() > 0.0: walk_time += delta * 12.0
	apply_push(delta)
	facing_octant = posmod(int(round(facing.angle() / (PI / 4.0))), 8)
	visual.set_pose(self)
	queue_redraw()

func move_external(displacement: Vector2) -> float:
	var before := position
	move_and_collide(displacement)
	return position.distance_to(before)

func apply_push(delta: float) -> void:
	if push_remaining<=.001:
		push_remaining=0
		push_used=0
		return
	var distance := minf(push_remaining,push_speed*delta)
	var actual := move_external(push_direction*distance)
	push_remaining -= distance
	push_used += actual
	if actual < distance-.01: push_remaining=0

func enemy_input(delta: float) -> Vector2:
	if not is_instance_valid(target) or target.health<=0: return Vector2.ZERO
	var offset: Vector2 = target.position-position
	if offset.length()>480: return Vector2.ZERO
	facing = offset.normalized()
	var d := Weapons.enemy(ranged_enemy,rank)
	if offset.length()<=float(d.range) and get_parent().clear_line(position,target.position,ranged_enemy):
		begin_attack()
		return Vector2.ZERO
	path_remaining -= delta
	if path_remaining<=0:
		path_remaining=.25
		path=get_parent().find_path(position,target.position)
		path_index=1 if path.size()>1 else 0
	while path_index<path.size() and position.distance_to(path[path_index])<10: path_index+=1
	if path_index<path.size(): return (path[path_index]-position).normalized()
	return Vector2.ZERO

func begin_attack() -> void:
	if is_player and not get_viewport().get_visible_rect().has_point(get_viewport().get_mouse_position()): return
	if is_player and get_parent().get("hold_fire") == true: return
	if phase != "idle" or stagger > 0.0 or health <= 0.0: return
	if is_player and weapon < 0: return
	if next_combo == 0:
		chain_id += 1
		chain_switched = false
		runtime.prepared.clear()
	combo = next_combo if is_player else 0
	attack_serial += 1
	attack_data = Weapons.step(weapon, combo) if is_player else Weapons.enemy(ranged_enemy, rank)
	var context: Dictionary = runtime.snapshot("normal" if is_player else "enemy", combo)
	if not runtime.pay_attack_cost(context):
		attack_requires_release = true
		input_buffer = 0.0
		reset_chain()
		return
	# Life-cost-triggered buffs apply to this attack, not only to the following one.
	context.lifesteal = float(character_state.stats.lifesteal)
	attack_data["context"] = context
	configure_attack_values(true)
	start_attack_phase()

func configure_attack_values(allow_crit: bool) -> void:
	var values: Dictionary = character_state.stats
	var context: Dictionary = attack_data.context
	if is_player:
		var reference_damage: float = Weapons.step(weapon, 0).damage
		if attack_data.has("skill"):
			attack_data.damage = float(values.damage) * float(attack_data.skill.get("multiplier", 0.0))
		else:
			attack_data.damage = float(values.damage) * float(attack_data.damage) / maxf(0.001, reference_damage)
			if runtime.has_effect(context.effects, "blood_cost"):
				attack_data.damage *= 1.0 + runtime.effect_value(context.effects, "blood_cost", "bonus", 0.15)
		context["echo_damage"] = float(attack_data.damage)
		var chance: float = float(values.crit_chance)
		if weapon == 0 and combo == 3 and context.prepared: chance += 0.20
		if allow_crit and randf() < minf(character_state.config.max_crit_chance, chance):
			attack_data.damage *= float(values.crit_multiplier)
	attack_data.strength = values.strength
	attack_data.push *= values.impact_multiplier
	if is_player and weapon == 1 and combo == 3 and context.prepared:
		attack_data.push = minf(0.95, float(attack_data.push) * 1.2)
	attack_data.windup = maxf(character_state.config.min_windup, float(attack_data.windup) / float(values.final_attack_speed))
	attack_data.active = maxf(character_state.config.min_active, float(attack_data.active) / float(values.final_attack_speed))
	attack_data.recovery = maxf(character_state.config.min_recovery, float(attack_data.recovery) / float(values.final_attack_speed))
	context["range"] = float(attack_data.range)
	context["origin"] = position

func start_attack_phase() -> void:
	attack_chain_invalidated = false
	buffered = false
	input_buffer = 0.0
	cross_remaining = 0.0
	combo_window = 0.0
	attack_facing = facing if not is_player else mouse_direction()
	facing = attack_facing
	interrupted = false
	shot_direction = attack_facing
	phase = "windup"
	phase_remaining = float(attack_data.windup)
	active_elapsed = 0.0
	hit_ids.clear()
	shot_done = false
	runtime.emit_event("attack_commit", {"context": attack_data.context})

func advance_attack(delta: float) -> void:
	var left: float = delta
	while left > 0.0 and phase != "idle":
		var used: float = minf(left, phase_remaining)
		if phase == "windup" and is_player and attack_data.context.kind == "normal" and int(attack_data.weapon) == 4 and combo == 3:
			move_external(-attack_facing * radius * used / maxf(0.001, float(attack_data.windup)))
		if phase == "active" and attack_data.has("skill"):
			var skill: Dictionary = attack_data.skill
			var direction: Vector2 = attack_data.get("dash_direction", attack_facing)
			move_external(direction * radius * 2.0 * float(skill.get("dash", 0.0)) * used / maxf(0.001, float(attack_data.active)))
		if phase == "active":
			var previous: float = active_elapsed / float(attack_data.active)
			active_elapsed += used
			resolve_melee(previous, minf(1.0, active_elapsed / float(attack_data.active)))
		phase_remaining -= used
		left -= used
		if phase_remaining > 0.000001: break
		match phase:
			"windup":
				phase = "active"
				phase_remaining = float(attack_data.active)
				attack_data.context.origin = position
				if attack_data.shape == "arrow": release_arrows()
				if attack_data.context.kind == "normal" and runtime.has_effect(attack_data.context.effects, "shadow_echo"):
					var echo = DelayedAttack.new()
					echo.configure(self, attack_data, attack_facing)
					get_parent().add_child(echo)
			"active":
				phase = "recovery"
				phase_remaining = float(attack_data.recovery)
				var normal: bool = attack_data.context.kind in ["normal", "enemy"] and not attack_chain_invalidated
				next_combo = (combo + 1) % 4 if normal and not interrupted else 0
				cross_remaining = 0.50 if normal and not interrupted else 0.0
				runtime.emit_event("segment_end", {"context": attack_data.context})
				if pending_switch and switch_remaining <= 0.0 and cross_remaining > 0.0:
					execute_switch(true)
			"recovery":
				phase = "idle"
				combo_window = 0.50
				if interrupted or attack_chain_invalidated or attack_data.context.kind == "skill": reset_chain()
				if pending_switch: execute_switch(false)
			"transition":
				phase = "idle"
				combo_window = maxf(combo_window, cross_remaining)

func release_arrows() -> void:
	if shot_done: return
	shot_done=true
	var shared_hits: Dictionary={}
	var angles := [-15,0,15] if is_player and combo==2 and not attack_data.has("skill") else [0]
	for degrees in angles:
		get_parent().fire_arrow(self,shot_direction.rotated(deg_to_rad(degrees)),attack_data,shared_hits)

func point_in_sweep(point: Vector2, previous: float, current: float) -> bool:
	var offset:=point-position
	var reach: float=attack_data.range
	if attack_data.shape=="thrust":
		var along:=offset.dot(attack_facing)
		var side:=absf(offset.cross(attack_facing))
		return along>=0 and along<=reach*current and side<=float(attack_data.width)/2
	if offset.length()>reach: return false
	var arc: float=attack_data.arc
	var a: float=-arc/2+arc*previous
	var b: float=-arc/2+arc*current
	if combo==1:
		a=arc/2-arc*current
		b=arc/2-arc*previous
	var relative:=wrapf(offset.angle()-attack_facing.angle()-(a+b)/2,-PI,PI)
	return absf(relative)<=(b-a)/2+.035

func resolve_melee(previous: float, current: float) -> void:
	if attack_data.shape in ["arrow", "none"]: return
	var candidates: Array = get_tree().get_nodes_in_group("enemies" if is_player else "players")
	candidates.sort_custom(func(a, b): return position.distance_squared_to(a.position) < position.distance_squared_to(b.position))
	for other in candidates:
		if other.health <= 0.0 or hit_ids.has(other.get_instance_id()): continue
		var context: Dictionary = attack_data.context
		var limit: int = int(attack_data.get("target_limit", 0))
		if is_player and int(context.weapon) == 0 and int(context.step) == 2 and context.kind == "normal": limit = 2 if context.piercing else 1
		if limit > 0 and context.hit_targets.size() >= limit: break
		var contact: bool = false
		var samples: Array = other.hit_samples(position) if other.has_method("hit_samples") else [other.position]
		for point in samples:
			if point_in_sweep(point, previous, current) and get_parent().clear_line(position, point):
				contact = true
				break
		if contact:
			hit_ids[other.get_instance_id()] = true
			deal_hit(other, attack_data, (other.position - position).normalized())
	get_parent().damage_terrain(self, previous, current)

func deal_hit(other, data: Dictionary, direction: Vector2) -> float:
	var context: Dictionary = data.get("context", {"kind": "secondary"})
	var modifiers: Dictionary = runtime.before_hit(other, context)
	var raw: float = float(data.damage) * float(modifiers.multiplier)
	if context.get("piercing", false) and context.get("hit_targets", []).size() > 0: raw *= 0.6
	var actual: float = other.take_hit(raw, float(data.get("strength", 0.0)), direction, float(data.get("push", 0.0)), context, float(modifiers.defense_ratio))
	if actual > 0.0 and data.has("skill"):
		var skill: Dictionary = data.skill
		var status: String = str(skill.get("status", ""))
		if status == "slow":
			other.skill_slow = 0.85 if other.rank == 2 else 0.65
			other.skill_slow_remaining = 0.75 if other.rank == 2 else 1.5
		elif status == "root":
			if other.rank == 2:
				other.skill_slow = 0.8
				other.skill_slow_remaining = 0.8
			else: other.skill_root_remaining = 0.6
		elif status == "破绽": other.set_tactical_status("破绽", 2.0)
	runtime.on_hit(other, context, actual, modifiers)
	return actual

func take_hit(damage: float, strength: float = 10.0, direction: Vector2 = Vector2.RIGHT, fraction: float = 0.2, context: Dictionary = {}, defense_ratio: float = 1.0) -> float:
	if health <= 0.0: return 0.0
	var applied_damage: float = Stats.damage_after_defense(damage, float(character_state.stats.defense) * defense_ratio, character_state.config)
	var old_health: float = health
	if not (is_player and get_parent().invincible) and not dummy: health = maxf(0.0, health - applied_damage)
	var actual: float = maxf(0.0, old_health - health)
	sync_resources()
	last_push_distance = Stats.knockback_distance(radius * 2.0, fraction, strength, applied_damage / 30.0, character_state.stats)
	var budget: float = maxf(0.0, radius * 2.0 - push_used)
	if fraction > 0.0:
		push_remaining = minf(maxf(push_remaining, last_push_distance), budget)
		push_direction = direction
		push_speed = push_remaining / Rules.PUSH_DURATION
	flash = 0.14
	var stable: bool = runtime.ignore_interrupt() if actual > 0.0 else false
	if not dummy and not stable and fraction > 0.0:
		stagger = 0.10
		if phase == "windup":
			interrupted = true
			phase = "recovery"
			phase_remaining = float(attack_data.recovery)
			buffered = false
			pending_switch = false
			queued_skill.clear()
			reset_chain()
	runtime.on_health_damage(actual)
	get_parent().show_damage(position, applied_damage)
	if health <= 0.0 and not death_sent:
		death_sent = true
		runtime.emit_event("death", {"context": context})
		phase = "idle"
		reset_chain()
		pending_switch = false
		queued_skill.clear()
		push_remaining = 0.0
		set_deferred("collision_layer", 0)
		set_deferred("collision_mask", 0)
		get_parent().actor_died(self)
	return actual

func _draw() -> void:
	if health<=0:
		draw_circle(Vector2(0,5),radius*.7,Color(0,0,0,.2))
		return
	var color:=Color("63d9ca") if is_player else (Color("dc8471") if rank==0 else Color("c9a46d"))
	if ranged_enemy: color=Color("b49aca")
	if dummy: color=Color("a2a7a2")
	if flash>0: color=Color.WHITE
	if is_player and weapon >= 0 and phase=="idle" and get_parent().show_ranges:
		draw_arc(Vector2.ZERO,Weapons.max_range(weapon),0,TAU,64,Color(0.4,0.8,0.8,.1),1)
	if phase=="windup" or phase=="active": draw_attack()
	if not tactical_status.is_empty():
		draw_string(preload("res://assets/NotoSansSC.ttf"), Vector2(-24, -46), tactical_status, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("9ccfe9"))
	if runtime.rage_remaining > 0.0: draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 24, Color("df6877"), 2.0)
	if runtime.stability_remaining > 0.0: draw_arc(Vector2.ZERO, radius + 8.0, 0.0, TAU, 24, Color("e4c987"), 2.0)
	draw_set_transform(Vector2(0,5),0,Vector2(1,.55))
	draw_circle(Vector2.ZERO,radius+5,Color(0,0,0,.35))
	draw_set_transform(Vector2.ZERO)
	if is_player:
		for i in range(2):
			if slots[i] < 0: continue
			var offset := Vector2(-9.0 if i == 0 else 9.0, -3.0)
			var bearing := Vector2(0.5 if i == 0 else -0.5, -1.0).normalized()
			if slots[i] == 4:
				draw_arc(offset, 17, bearing.angle() - PI / 2.0, bearing.angle() + PI / 2.0, 16, Color("b59b7b"), 2.5)
				draw_line(offset + bearing.orthogonal() * 17.0, offset - bearing.orthogonal() * 17.0, Color("cbd4c9"), 1.0)
			elif slots[i] == 2:
				draw_arc(offset, 10, 0, TAU, 18, Color("b59b7b"), 2.0)
			else:
				draw_line(offset - bearing * 12.0, offset + bearing * (35.0 if slots[i] == 3 else 22.0), Color("8194a0"), 4.0 if slots[i] == 1 else 2.5)
	var w: int = int(attack_data.get("weapon", weapon)) if is_player and phase != "idle" else (weapon if is_player else (4 if ranged_enemy else 1))
	var direction:=facing
	if is_player and w < 0: return
	if phase=="active" and attack_data.shape not in ["arrow", "none"]:
		var p:=active_elapsed/float(attack_data.active)
		direction=attack_facing.rotated(float(attack_data.arc)*(p-.5)*( -1 if combo==1 else 1)) if attack_data.shape=="arc" else attack_facing
	var hand:=direction*17
	if w==4:
		draw_arc(hand,14,direction.angle()-PI/2,direction.angle()+PI/2,14,Color("d1b48e"),3)
		draw_line(hand+direction.orthogonal()*14,hand-direction.orthogonal()*14,Color("dfe6d7"),1)
	elif w==3:
		draw_line(-direction*15,direction*53,Color("9c8971"),3)
		draw_line(direction*45,direction*62,Color("e5ebdd"),5)
	elif w==2:
		var points:=PackedVector2Array()
		for i in range(12): points.append(hand+direction*i*4+direction.orthogonal()*sin(i*.8)*4)
		draw_polyline(points,Color("d2b490"),2)
	else:
		draw_line(hand,hand+direction*(30 if w==0 else 37),Color("e4eddf"),4 if w==0 else 8)
		draw_line(hand+direction.orthogonal()*7,hand-direction.orthogonal()*7,Color("b99b72"),3)
	if not is_player:
		draw_rect(Rect2(-22,-37,44,4),Color("26353d"))
		draw_rect(Rect2(-22,-37,44*health/max_health,4),color)

func draw_attack() -> void:
	if attack_data.shape == "none": return
	var reach: float=attack_data.range
	var color:=Color(.35,.9,.8,.13) if is_player else Color(1,.45,.25,.19)
	if phase=="active": color.a=.30
	if attack_data.shape=="thrust":
		var width: float=attack_data.width
		var side:=attack_facing.orthogonal()*width/2
		draw_colored_polygon(PackedVector2Array([side,-side,attack_facing*reach-side,attack_facing*reach+side]),color)
	elif attack_data.shape == "arrow":
		draw_line(Vector2.ZERO, attack_facing * reach, color.lightened(0.35), 2.0)
	else:
		var arc: float=attack_data.arc
		var points:=PackedVector2Array([Vector2.ZERO])
		for i in range(49): points.append(attack_facing.rotated(-arc/2+arc*i/48)*reach)
		draw_colored_polygon(points,color)
		if phase=="active" and attack_data.shape=="arc":
			var progress:=active_elapsed/float(attack_data.active)
			var angle: float=arc*(progress-.5)*(-1 if combo==1 else 1)
			draw_line(Vector2.ZERO,attack_facing.rotated(angle)*reach,Color(color, .8),3)
