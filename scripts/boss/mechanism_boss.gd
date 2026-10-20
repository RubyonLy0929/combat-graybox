extends "res://scripts/actor.gd"
## Reuses health/defense, equipment hit events and tactical status from Actor.
const Hazard = preload("res://scripts/boss/boss_hazard.gd")
var stage: int = 1
var checkpoints_done: Dictionary = {}
var pending_checkpoint: int = 0
var deferred_damage: float = 0.0
var settle_deferred: bool = false
var mode: String = "idle"
var mode_time: float = 1.5
var action_clock: float = 0.0
var cast_name: String = "识别失败 · 守卫启动"
var cast_total: float = 1.0
var schedule_index: int = 0
var transition_pending: bool = false
var core_open: bool = false
var aimed: Vector2 = Vector2.DOWN
var shot_index: int = 0
var sweep_protection: Dictionary = {}
var dash_end: Vector2 = Vector2.ZERO
var dash_hit: bool = false
var slash_index: int = 0
var sword_angle: float = 0.0
var summon_progress: float = 0.0
var last_cover_bonus: bool = false
@export var encounter_health: float = 2800.0
@export_range(0.1, 0.9) var release_threshold: float = 0.6

func _ready() -> void:
	rank = 2
	title = "古代防线守卫 · 镇疆魔神"
	radius = 68.0
	max_health = encounter_health
	health = max_health
	super._ready()
	visual.visible = false
	character_state.profile.base["defense"] = 10.0
	character_state.profile.base["health_regen"] = 0.0
	character_state.recalculate()

func _physics_process(delta: float) -> void:
	var room = get_parent()
	if health <= 0.0 or room.combat_over: return
	queue_redraw()
	if room.combat_frozen or room.mechanism_moving or room.freeze_ai or room.marathon_active: return
	flash = maxf(0.0, flash - delta)
	tactical_remaining = maxf(0.0, tactical_remaining - delta)
	if tactical_remaining <= 0.0: tactical_status = ""
	skill_slow_remaining = maxf(0.0, skill_slow_remaining - delta)
	if skill_slow_remaining <= 0.0: skill_slow = 1.0
	mode_time -= delta
	action_clock += delta
	match mode:
		"idle":
			if mode_time <= 0.0:
				if settle_deferred:
					settle_deferred = false
					apply_deferred_damage()
					if health <= 0.0: return
				if stage == 2 and pending_checkpoint > 0:
					room.begin_marathon(pending_checkpoint)
				elif stage == 1 and transition_pending:
					room.begin_transition()
				else: choose_action()
		"sword":
			if shot_index < 2 and action_clock >= 0.9 + shot_index * 0.6:
				var bearing: Vector2 = aimed.rotated(-0.28 if shot_index == 0 else 0.28)
				spawn_hazard({"kind": "projectile", "position": position + bearing * 80.0, "direction": bearing, "radius": 15.0, "speed": 240.0, "damage": 35.0, "push": 0.35})
				shot_index += 1
			if mode_time <= 0.0: rest(1.5)
		"salvo":
			if shot_index < 3 and action_clock >= 0.5 + shot_index * 0.8:
				spawn_hazard({"kind": "circle", "position": room.player.position, "radius": 64.0, "delay": 1.35, "damage": 42.0, "number": shot_index + 1, "push": 0.25})
				shot_index += 1
			if mode_time <= 0.0: rest(2.0)
		"machine":
			if action_clock >= 1.0 and shot_index < 16 and action_clock >= 1.0 + shot_index * 0.1:
				var bearing: Vector2 = Vector2.DOWN.rotated(-1.05 + float(shot_index) / 15.0 * 2.1)
				var blocker = room.cover_between(position, room.player.position)
				var offset: Vector2 = room.player.position - position
				if absf(wrapf(offset.angle() - bearing.angle(), -PI, PI)) < 0.11:
					if blocker != null: sweep_protection[blocker.get_instance_id()] = blocker
					else: room.hurt_player(7.0, bearing, 0.04)
				spawn_hazard({"kind": "line", "position": position, "direction": bearing, "reach": 1000.0, "width": 10.0, "delay": 0.0, "duration": 0.08, "damage": 0.0})
				shot_index += 1
			if mode_time <= 0.0:
				for cover in sweep_protection.values():
					if is_instance_valid(cover): cover.consume()
				rest(2.0)
		"barrage":
			if mode_time <= 0.0: rest(3.0)
		"clearance":
			if mode_time <= 0.0:
				room.launch_mechanism()
				set_mode("blast", 1.6, "破城横扫 · 落在掩体后或南侧安全带")
		"blast":
			if mode_time <= 0.0:
				room.resolve_clearance()
				rest(3.0)
		"chase":
			chase_player(delta)
		"slash":
			if mode_time > 0.25: aimed = (room.player.position - position).normalized()
			if mode_time <= 0.0:
				spawn_hazard({"kind": "sector", "position": position, "direction": aimed, "reach": 185.0 if slash_index < 2 else 220.0, "arc": deg_to_rad(105.0 if slash_index < 2 else 80.0), "delay": 0.0, "duration": 0.15, "damage": 30.0 if slash_index < 2 else 52.0, "push": 0.2 if slash_index < 2 else 0.65})
				sword_angle = aimed.angle() + (0.6 if slash_index % 2 == 0 else -0.6)
				set_mode("slash_gap", 0.35 if slash_index == 0 else 0.5, "连斩落刀 · 侧移")
		"slash_gap":
			if mode_time <= 0.0:
				slash_index += 1
				if slash_index >= 3: rest(2.4)
				else: set_mode("slash", 0.45 if slash_index == 1 else 0.8, "三连顺劈 %d/3" % (slash_index + 1))
		"dash_charge":
			if mode_time > 0.6: aimed = (room.player.position - position).normalized()
			if mode_time <= 0.0:
				dash_end = room.clamp_boss_point(position + aimed * 410.0)
				dash_hit = false
				last_cover_bonus = false
				set_mode("dash", 0.65, "破阵突进")
		"dash":
			var old: Vector2 = position
			var travel: Vector2 = aimed * minf(650.0 * delta, position.distance_to(dash_end))
			var cover = room.cover_between(position, position + travel + aimed * radius)
			if cover != null:
				cover.consume()
				last_cover_bonus = true
				mode_time = 0.0
			else:
				var collision = move_and_collide(travel)
				if collision != null: mode_time = 0.0
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(room.player.position, old, position)
			if not dash_hit and near.distance_to(room.player.position) <= radius + room.player.radius:
				dash_hit = true
				room.hurt_player(62.0, aimed, 0.75)
			if mode_time <= 0.0 or position.distance_to(dash_end) < 6.0:
				rest(3.5 if last_cover_bonus else 3.0)
		"shot":
			if shot_index < 2 and action_clock >= 0.8 + shot_index * 0.6:
				aimed = (room.player.position - position).normalized()
				spawn_hazard({"kind": "projectile", "position": position + aimed * 78.0, "direction": aimed, "speed": 210.0, "radius": 10.0, "damage": 24.0, "push": 0.12})
				shot_index += 1
			if mode_time <= 0.0: rest(1.2)
		"crossfire", "reversal":
			if mode_time <= 0.0: rest(2.4)
		"ring":
			if mode_time <= 0.0:
				spawn_hazard({"kind": "circle", "position": position, "radius": 155.0, "delay": 0.0, "damage": 32.0, "push": 0.35})
				rest(1.8)
	if mode in ["slash", "dash_charge", "shot"]: facing = aimed

func choose_action() -> void:
	core_open = false
	shot_index = 0
	aimed = (get_parent().player.position - position).normalized()
	if stage == 1:
		var choices: Array[String] = ["sword", "clearance", "salvo", "machine", "barrage"]
		var choice: String = choices[schedule_index % choices.size()]
		schedule_index += 1
		match choice:
			"sword": set_mode("sword", 2.1, "裂阵剑气 · 两道慢速剑气")
			"clearance":
				get_parent().prepare_clearance()
				set_mode("clearance", get_parent().clearance_warning(), "防线清场 · 看落点，选掩体或南侧安全带")
			"salvo": set_mode("salvo", 3.6, "追踪炮击 · 标记后立即移动")
			"machine":
				sweep_protection.clear()
				set_mode("machine", 2.8, "扇面扫射 · 掩体只保护一次")
			"barrage":
				var sequence_time: float = get_parent().spawn_barrage()
				set_mode("barrage", sequence_time, "阵列炮击 · 站晚爆区，再进入已爆区")
	else:
		var choices: Array[String] = ["chase", "crossfire", "dash_charge", "reversal", "chase", "sword", "ring", "shot"]
		var choice: String = choices[schedule_index % choices.size()]
		schedule_index += 1
		match choice:
			"chase": set_mode("chase", 4.0, "追击 · 进入攻击距离后停步")
			"dash_charge": set_mode("dash_charge", 1.6, "破阵突进 · 红线锁定后侧移")
			"ring": set_mode("ring", 1.1, "环身震荡 · 离开脚下范围")
			"shot": set_mode("shot", 2.0, "炮口点射 · 两发慢弹")
			"sword": set_mode("sword", 2.1, "追猎剑气 · 锁向后的两道慢波")
			"crossfire":
				var warning: float = maxf(1.6, 115.0 / maxf(1.0, float(get_parent().player.character_state.stats.final_move_speed)) + 0.8)
				for bearing in [Vector2.RIGHT, Vector2.DOWN]:
					var at: Vector2 = Vector2(80, position.y) if bearing == Vector2.RIGHT else Vector2(position.x, 140)
					spawn_hazard({"kind": "line", "position": at, "direction": bearing, "reach": 1120.0 if bearing == Vector2.RIGHT else 480.0, "width": 70.0, "delay": warning, "damage": 38.0, "push": 0.2, "attack_group": "cross_%d" % schedule_index})
				set_mode("crossfire", warning + 0.3, "交叉炮线 · 走出横纵两条线")
			"reversal":
				var speed: float = maxf(1.0, float(get_parent().player.character_state.stats.final_move_speed))
				var first: float = maxf(1.6, 180.0 / speed + 0.8)
				var second: float = first + maxf(2.0, 400.0 / speed + 0.8)
				spawn_hazard({"kind": "circle", "position": position, "radius": 165.0, "delay": first, "damage": 32.0, "push": 0.0})
				spawn_hazard({"kind": "donut", "position": position, "inner_radius": 165.0, "radius": 400.0, "delay": second, "telegraph_time": second - first, "damage": 40.0, "push": 0.0})
				set_mode("reversal", second + 0.3, "内外逆转 · 先离开，再靠近核心")

func chase_player(delta: float) -> void:
	var offset: Vector2 = get_parent().player.position - position
	if offset.length() <= 165.0:
		slash_index = 0
		aimed = offset.normalized()
		set_mode("slash", 0.65, "三连顺劈 1/3")
		return
	if mode_time <= 0.0:
		shot_index = 0
		set_mode("shot", 2.0, "炮口点射 · 两发慢弹")
		return
	path_remaining -= delta
	if path_remaining <= 0.0:
		path_remaining = 0.3
		path = get_parent().find_path(position, get_parent().player.position)
		path_index = 1 if path.size() > 1 else 0
	while path_index < path.size() and position.distance_to(path[path_index]) < 16.0: path_index += 1
	var bearing: Vector2 = (path[path_index] - position).normalized() if path_index < path.size() else offset.normalized()
	velocity = bearing * Rules.MOVE_SPEED * skill_slow
	move_and_slide()
	facing = bearing

func set_mode(value: String, seconds: float, label: String) -> void:
	mode = value
	mode_time = seconds
	cast_total = seconds
	action_clock = 0.0
	cast_name = label

func rest(seconds: float) -> void:
	core_open = true
	set_mode("idle", seconds, "核心过热 · 反击窗口 %.1f秒" % seconds)

func spawn_hazard(values: Dictionary) -> void:
	var effect = Hazard.new()
	effect.configure(values)
	get_parent().add_child(effect)

func take_hit(damage: float, strength: float = 10.0, direction: Vector2 = Vector2.RIGHT, _fraction: float = 0.2, context: Dictionary = {}, defense_ratio: float = 1.0) -> float:
	if get_parent().combat_frozen or get_parent().marathon_active or pending_checkpoint > 0 or health <= 0.0: return 0.0
	var scaled: float = damage * (1.25 if core_open else 1.0)
	# Keep phase-one at its threshold until the current action has finished.
	if stage == 1:
		var room_left: float = maxf(0.0, health - max_health * release_threshold)
		var applied: float = Stats.damage_after_defense(scaled, float(character_state.stats.defense) * defense_ratio, character_state.config)
		if applied > room_left: scaled *= room_left / maxf(0.001, applied)
	if stage == 2:
		var next: int = next_checkpoint()
		if next > 0:
			var budget: float = maxf(0.0, health - max_health * float(next) / 100.0)
			var applied: float = Stats.damage_after_defense(scaled, float(character_state.stats.defense) * defense_ratio, character_state.config)
			if applied >= budget:
				deferred_damage += maxf(0.0, applied - budget)
				scaled *= budget / maxf(0.001, applied)
				pending_checkpoint = next
	var actual: float = super.take_hit(scaled, strength, direction, 0.0, context, defense_ratio)
	last_push_distance = 0.0
	push_remaining = 0.0
	if stage == 1 and health <= max_health * release_threshold + 0.01: transition_pending = true
	return actual

func next_checkpoint() -> int:
	for value in [45, 30, 15]:
		if not checkpoints_done.has(value): return value
	return 0

func complete_marathon(value: int) -> void:
	checkpoints_done[value] = true
	pending_checkpoint = 0
	settle_deferred = true
	rest(4.0)

func apply_deferred_damage() -> void:
	var next: int = next_checkpoint()
	var floor_hp: float = max_health * float(next) / 100.0
	var actual: float = minf(deferred_damage, maxf(0.0, health - floor_hp))
	health -= actual
	deferred_damage -= actual
	sync_resources()
	if next > 0 and health <= floor_hp + 0.01: pending_checkpoint = next
	if health <= 0.0: get_parent().actor_died(self)

func debug_checkpoint(value: int) -> void:
	# Explicit preview skips earlier checkpoints, without consuming the chosen one.
	for earlier in [45, 30, 15]:
		if earlier > value: checkpoints_done[earlier] = true
	checkpoints_done.erase(value)
	deferred_damage = 0.0
	settle_deferred = false
	health = max_health * float(value) / 100.0
	sync_resources()
	pending_checkpoint = value
	get_parent().begin_marathon(value)

func enter_stage_two() -> void:
	stage = 2
	core_open = false
	transition_pending = false
	schedule_index = 0
	position = Vector2(640, 255)
	facing = Vector2.DOWN
	set_mode("idle", 1.5, "机动限制解除 · 魔神苏醒")

func hit_samples(origin: Vector2) -> Array[Vector2]:
	var near: Vector2 = (origin - position).normalized()
	return [position, position + near * radius, position + near.rotated(0.4) * radius, position + near.rotated(-0.4) * radius]

func _draw() -> void:
	if health <= 0.0:
		draw_rect(Rect2(-65, -35, 130, 70), Color("40454b"))
		draw_circle(Vector2.ZERO, 24, Color("4a5e5c"))
		return
	var body: Color = Color("b9b7a6") if flash > 0.0 else Color("626f78")
	var core: Color = Color("80f1ce") if core_open else Color("d18e69")
	if get_parent().combat_frozen: core = Color("ee986c")
	draw_set_transform(Vector2(0, 15), 0, Vector2(1, 0.4))
	draw_circle(Vector2.ZERO, 100, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
	for side in [-1, 1]:
		draw_rect(Rect2(side * 70 - 18, -20, 36, 78), Color("33414b"))
		for row in range(5): draw_line(Vector2(side * 70 - 16, -12 + row * 15), Vector2(side * 70 + 16, -12 + row * 15), Color("77838b"), 4.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-65, -34), Vector2(65, -34), Vector2(77, 42), Vector2(0, 68), Vector2(-77, 42)]), body)
	draw_rect(Rect2(-44, -74, 88, 64), body.lightened(0.1))
	draw_rect(Rect2(-31, -69, 62, 17), Color("263846"))
	draw_line(Vector2(-27, -60), Vector2(27, -60), core, 4.0)
	draw_circle(Vector2(0, -10), 22, core.darkened(0.4))
	draw_circle(Vector2(0, -10), 12 + (sin(action_clock * 6.0) + 1.0) * 2, core)
	for side in [-1, 1]:
		draw_rect(Rect2(side * 90 - 13, -49, 26, 47), Color("435662"))
		draw_circle(Vector2(side * 90, 0), 13, Color("223744"))
		draw_circle(Vector2(side * 90, 0), 6, Color("b59672"))
	if stage == 1:
		for side in [-1, 1]:
			draw_line(Vector2(side * 38, -68), Vector2(side * 125, -92), Color("a69a7c"), 6.0)
	else:
		draw_arc(Vector2.ZERO, 73, 0.0, TAU, 40, core, 2.0)
		var rise: float = summon_progress * 40.0
		draw_circle(Vector2(0, -85 - rise), 18, Color(core, 0.65))
		draw_line(Vector2(-15, -98 - rise), Vector2(-27, -113 - rise), core, 4.0)
		draw_line(Vector2(15, -98 - rise), Vector2(27, -113 - rise), core, 4.0)
	var bearing: Vector2 = aimed if mode in ["slash", "slash_gap", "dash_charge", "dash"] else facing
	var hand: Vector2 = bearing.orthogonal() * 72.0
	draw_line(hand, hand + bearing * 100.0, Color("b7c9c7"), 13.0)
	draw_line(hand - bearing.orthogonal() * 18, hand + bearing.orthogonal() * 18, Color("c8ac75"), 7.0)
	if core_open: draw_string(preload("res://assets/NotoSansSC.ttf"), Vector2(-35, -125), "核心暴露", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("9cf2d5"))
	if not tactical_status.is_empty(): draw_string(preload("res://assets/NotoSansSC.ttf"), Vector2(-25, 90), tactical_status, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("a7dfef"))
