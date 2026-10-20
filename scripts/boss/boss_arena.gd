extends "res://scripts/main.gd"
const Boss = preload("res://scripts/boss/mechanism_boss.gd")
const Cover = preload("res://scripts/boss/one_use_cover.gd")
const Marathon = preload("res://scripts/boss/boss_marathon.gd")
const BossHazard = preload("res://scripts/boss/boss_hazard.gd")
const FIELD = Rect2(80, 140, 1120, 480)
const FALLBACK = Rect2(92, 550, 1096, 58)
var boss
var marathon
var marathon_active: bool = false
var hold_fire: bool = false
var covers: Array = []
var active_pair: int = -1
var combat_frozen: bool = false
var mechanism_moving: bool = false
var finished: bool = false
var cinematic_elapsed: float = 0.0
var launch_clock: float = 0.0
var launch_from: Vector2 = Vector2.ZERO
var launch_to: Vector2 = Vector2.ZERO
var impact_flash: float = 0.0
var boss_bar: ProgressBar
var cast_bar: ProgressBar
var boss_label: Label
var cast_label: Label
var overlay: ColorRect
var cinema_label: Label
var view_shake: float = 0.0
var hazard_groups_hit: Dictionary = {}
var barrage_serial: int = 0

func _ready() -> void:
	setup_inputs()
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	random.randomize()
	for box in [Rect2(60, 120, 1160, 20), Rect2(60, 620, 1160, 20), Rect2(60, 120, 20, 520), Rect2(1200, 120, 20, 520)]: add_wall(box)
	for row in range(3):
		for x in [450.0, 830.0]:
			var cover = Cover.new()
			cover.pair_index = row
			cover.configure({"rect": Rect2(x - 42, 335 + row * 75, 84, 24), "title": "一次掩体"})
			add_child(cover)
			covers.append(cover)
			terrains.append(cover)
	setup_nav()
	player = Actor.new()
	player.is_player = true
	player.max_health = 300.0
	player.health = 300.0
	player.position = Vector2(640, 565)
	player.facing = Vector2.UP
	add_child(player)
	boss = Boss.new()
	boss.position = Vector2(640, 235)
	boss.target = player
	add_child(boss)
	marathon = Marathon.new()
	add_child(marathon)
	var camera = Camera2D.new()
	camera.position = Vector2(640, 360)
	camera.position_smoothing_enabled = false
	add_child(camera)
	total = 1
	setup_hud()
	setup_inventory_and_drops()
	notify_player("60%脱困；二阶段45%/30%/15%固定机制。F3/F4/F5/F6调试，R重开")

func setup_nav() -> void:
	nav.clear()
	for x in range(64):
		for y in range(36):
			var point: Vector2 = Vector2(x * 20 + 10, y * 20 + 10)
			var blocked: bool = not Rect2(156, 210, 968, 330).has_point(point)
			for cover in covers:
				if not cover.destroyed and cover.rect.grow(74.0).has_point(point): blocked = true
			if not blocked: nav.add_point(y * 64 + x, point)
	for id in nav.get_point_ids():
		var x: int = id % 64
		var y: int = int(id / 64)
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0: continue
				if x + dx < 0 or x + dx >= 64: continue
				var other: int = (y + dy) * 64 + x + dx
				if not nav.has_point(other): continue
				if dx != 0 and dy != 0 and (not nav.has_point(y * 64 + x + dx) or not nav.has_point((y + dy) * 64 + x)): continue
				nav.connect_points(id, other, false)

func terrain_destroyed(_terrain) -> void:
	# Mechanic walls are not loot sources; one-use consumption cannot farm rewards.
	setup_nav.call_deferred()
	if boss != null: boss.path_remaining = 0.0
	queue_redraw()

func cover_between(from: Vector2, to: Vector2):
	var best = null
	var best_distance: float = INF
	for cover in covers:
		if cover.destroyed: continue
		var box: Rect2 = cover.rect
		var vertices: Array[Vector2] = [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
		for i in range(4):
			var hit = Geometry2D.segment_intersects_segment(from, to, vertices[i], vertices[(i + 1) % 4])
			if hit != null:
				var distance: float = from.distance_to(hit)
				if distance < best_distance:
					best = cover
					best_distance = distance
	return best

func clearance_warning() -> float:
	# Includes a travel allowance at the current burden-reduced speed.
	var speed: float = maxf(1.0, float(player.character_state.stats.final_move_speed))
	return maxf(4.5, 550.0 / speed + 1.2)

func prepare_clearance() -> void:
	clear_boss_hazards()
	active_pair = -1
	for row in range(3):
		for cover in covers:
			if cover.pair_index == row and not cover.destroyed:
				active_pair = row
				break
		if active_pair >= 0: break
	for cover in covers:
		cover.highlighted = cover.pair_index == active_pair and not cover.destroyed
		cover.queue_redraw()
	notify_player("击退落点可见：对准绿色掩体后方；南侧绿色安全带始终可用")

func predicted_landing(from: Vector2) -> Vector2:
	var destination: Vector2 = Vector2(clampf(from.x, 102.0, 1178.0), minf(584.0, from.y + 155.0))
	if active_pair >= 0: destination.y = maxf(destination.y, 397.0 + active_pair * 75.0)
	for cover in covers:
		if not cover.destroyed and cover.rect.grow(player.radius + 3.0).has_point(destination):
			destination.y = cover.rect.end.y + player.radius + 5.0
	return Vector2(destination.x, clampf(destination.y, 170.0, 584.0))

func launch_mechanism() -> void:
	launch_from = player.position
	launch_to = predicted_landing(launch_from)
	launch_clock = 0.0
	mechanism_moving = true
	player.velocity = Vector2.ZERO
	player.push_remaining = 0.0
	player.phase = "idle"
	player.queued_skill.clear()
	player.pending_switch = false
	player.reset_chain()
	player.input_buffer = 0.0
	player.attack_requires_release = true
	# Explicit launch ignores intermediate low walls; only the checked landing is solid.

func resolve_clearance() -> void:
	var protector = null
	for cover in covers:
		if cover.destroyed or cover.pair_index != active_pair: continue
		if cover_shadow(cover).has_point(player.position):
			protector = cover
			break
	if protector != null:
		protector.consume()
		notify_player("掩体挡住横扫并破坏 · 核心暴露")
	elif FALLBACK.grow(-player.radius).has_point(player.position):
		notify_player("南侧撤离成功 · 返回核心反击")
	else:
		hurt_player(90.0, Vector2.DOWN, 0.8)
		notify_player("横扫命中：下次调整绿色落点或进入南侧安全带")
	for cover in covers:
		cover.highlighted = false
		cover.queue_redraw()
	impact_flash = 0.20

func cover_shadow(cover) -> Rect2:
	return Rect2(cover.rect.position.x + player.radius, cover.rect.end.y + player.radius + 3.0, cover.rect.size.x - player.radius * 2.0, 605.0 - cover.rect.end.y - player.radius * 2.0)

func spawn_barrage() -> float:
	# Three adjacent rows leave a route from the last row into the first detonated row.
	barrage_serial += 1
	var speed: float = maxf(1.0, float(player.character_state.stats.final_move_speed))
	var gap: float = maxf(1.6, 140.0 / speed + 0.95)
	var first: float = maxf(1.6, 125.0 / speed + 0.8)
	for row in range(3):
		for column in range(5):
			var effect = BossHazard.new()
			effect.configure({"kind": "circle", "position": Vector2(200 + column * 220, 230 + row * 140), "radius": 115.0, "delay": first + row * gap, "damage": 42.0, "push": 0.3, "number": row + 1, "attack_group": "barrage_%d_%d" % [barrage_serial, row]})
			add_child(effect)
	return first + 2.0 * gap + 0.4

func hurt_player(raw: float, bearing: Vector2, amount: float, attack_group: String = "") -> void:
	if raw <= 0.0 or player.health <= 0.0 or combat_over or combat_frozen or finished: return
	if not attack_group.is_empty():
		if hazard_groups_hit.has(attack_group): return
		hazard_groups_hit[attack_group] = true
	player.take_hit(raw, 18.0, bearing, amount, {"kind": "enemy", "source": "boss"})
	view_shake = 0.12

func clamp_boss_point(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, 154, 1126), clampf(point.y, 218, 544))

func clear_boss_hazards() -> void:
	for effect in get_tree().get_nodes_in_group("boss_hazards"):
		effect.set_physics_process(false)
		effect.queue_free()

func clear_transient_attacks() -> void:
	clear_boss_hazards()
	for group in ["arrows", "delayed_attacks"]:
		for effect in get_tree().get_nodes_in_group(group):
			effect.set_physics_process(false)
			effect.queue_free()

func reset_player_action() -> void:
	player.phase = "idle"
	player.pending_switch = false
	player.queued_skill.clear()
	player.input_buffer = 0.0
	player.push_remaining = 0.0
	player.stagger = 0.0
	player.velocity = Vector2.ZERO
	player.reset_chain()
	player.attack_requires_release = true

func begin_marathon(value: int) -> void:
	marathon.start(value)

func begin_transition() -> void:
	combat_frozen = true
	mechanism_moving = false
	cinematic_elapsed = 0.0
	clear_transient_attacks()
	player.phase = "idle"
	player.pending_switch = false
	player.queued_skill.clear()
	player.input_buffer = 0.0
	player.push_remaining = 0.0
	player.velocity = Vector2.ZERO
	player.reset_chain()
	player.attack_requires_release = true
	overlay.visible = true
	cinema_label.visible = true
	cinema_label.text = "防线失效……解除机动限制\n魔神正在挣脱封印  /  Esc 跳过"

func finish_transition() -> void:
	boss.enter_stage_two()
	boss.summon_progress = 1.0
	# Avoid materializing the boss on top of the player.
	if player.position.distance_to(boss.position) < boss.radius + player.radius + 15.0:
		player.position = Vector2(640, 565)
	combat_frozen = false
	cinema_label.visible = false
	overlay.visible = false
	player.attack_requires_release = true
	notify_player("二阶段：锁方向后侧移，第三刀／突进结束是反击窗口")

func setup_hud() -> void:
	var layer = CanvasLayer.new()
	add_child(layer)
	info = make_label(layer, Vector2(80, 10), "", 15)
	info.size = Vector2(320, 48)
	info.clip_text = true
	status_label = make_label(layer, Vector2(930, 15), "", 12)
	status_label.size = Vector2(275, 44)
	status_label.clip_text = true
	hp_bar = make_bar(layer, Vector2(80, 66), Vector2(245, 9), Color("c46760"))
	mp_bar = make_bar(layer, Vector2(80, 82), Vector2(245, 8), Color("588fd2"))
	boss_bar = make_bar(layer, Vector2(410, 15), Vector2(475, 12), Color("ba816c"))
	boss_label = make_label(layer, Vector2(410, 32), "", 15)
	for i in range(3):
		var label: Label = make_label(layer, Vector2(365 + i * 265, 60), "", 13)
		label.size = Vector2(255, 42)
		label.clip_text = true
		skill_labels.append(label)
	cast_label = make_label(layer, Vector2(330, 105), "", 16)
	cast_label.size = Vector2(880, 25)
	cast_label.clip_text = true
	cast_bar = make_bar(layer, Vector2(85, 116), Vector2(235, 6), Color("d7b474"))
	pickup_hint = make_label(layer, Vector2(795, 658), "", 13)
	pickup_hint.size = Vector2(390, 24)
	pickup_hint.clip_text = true
	notification = make_label(layer, Vector2(145, 635), "", 14)
	notification.size = Vector2(1050, 24)
	notification.clip_text = true
	result_label = make_label(layer, Vector2(375, 285), "", 26)
	combo_hint = make_label(layer, Vector2(95, 658), "", 13)
	combo_hint.size = Vector2(660, 24)
	combo_hint.clip_text = true
	make_label(layer, Vector2(80, 689), "WASD 移动 · 鼠标攻击 · Q/滚轮切武器 · 1/2/3技能 · I背包 · E拾取 · TAB掉落 · R重开 · F1/F2房间", 12)
	var cinema_layer = CanvasLayer.new()
	cinema_layer.layer = 15
	add_child(cinema_layer)
	overlay = ColorRect.new()
	overlay.color = Color(0.03, 0.03, 0.04, 0.35)
	overlay.size = Vector2(1280, 720)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	cinema_layer.add_child(overlay)
	cinema_label = make_label(cinema_layer, Vector2(285, 395), "", 24)
	cinema_label.visible = false

func make_bar(parent: Node, at: Vector2, dimensions: Vector2, tint: Color) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.position = at
	bar.size = dimensions
	bar.show_percentage = false
	var style = StyleBoxFlat.new()
	style.bg_color = tint
	bar.add_theme_stylebox_override("fill", style)
	parent.add_child(bar)
	return bar

func setup_inventory_and_drops() -> void:
	player.character_state.equip("backpack", Instance.new(load("res://data/items/basic_pack.tres")))
	for id in ["crit_ring", "vampire_ring", "gloves_light", "starter_spear"]:
		player.inventory_model.add(Instance.new(load("res://data/items/" + id + ".tres")))
	var layer = CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	inventory_panel = InventoryPanel.new()
	inventory_panel.configure(self, player.inventory_model)
	layer.add_child(inventory_panel)
	for i in range(Catalog.BD_IDS.size()):
		spawn_item_drop(Instance.new(load("res://data/items/" + Catalog.BD_IDS[i] + ".tres")), Vector2(150 + (i % 4) * 42, 530 + int(i / 4) * 44))
	for pair in [["starter_blade", Vector2(1050, 545)], ["starter_whip", Vector2(1090, 545)], ["body_heavy", Vector2(1050, 580)], ["harness_pack", Vector2(1090, 580)]]:
		spawn_item_drop(Instance.new(load("res://data/items/" + pair[0] + ".tres")), pair[1])
	spawn_gold(15, Vector2(610, 565))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F1:
			get_tree().change_scene_to_file("res://scenes/main.tscn")
			return
		if event.physical_keycode == KEY_ESCAPE and combat_frozen:
			if marathon_active: marathon.finish_intro()
			else: finish_transition()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_F3 and not combat_frozen and not mechanism_moving and boss.stage == 1 and not finished and not combat_over:
			boss.health = minf(boss.health, boss.max_health * boss.release_threshold)
			boss.sync_resources()
			begin_transition()
			return
		if event.physical_keycode in [KEY_F4, KEY_F5, KEY_F6] and boss.stage == 2 and not marathon_active and not combat_frozen and not finished and not combat_over:
			boss.debug_checkpoint({KEY_F4: 45, KEY_F5: 30, KEY_F6: 15}[event.physical_keycode])
			return
		if combat_frozen or mechanism_moving:
			return
	super._unhandled_input(event)

func _physics_process(delta: float) -> void:
	if not combat_frozen and not mechanism_moving: super._physics_process(delta)
	if mechanism_moving:
		launch_clock += delta
		var progress: float = clampf(launch_clock / 0.45, 0.0, 1.0)
		player.position = launch_from.lerp(launch_to, progress)
		if progress >= 1.0:
			mechanism_moving = false
			player.attack_requires_release = true

func _process(delta: float) -> void:
	if combat_frozen:
		if Input.is_action_just_pressed("restart"):
			get_tree().reload_current_scene()
			return
		if not marathon_active: cinematic_elapsed += delta
		if not marathon_active:
			boss.summon_progress = clampf(cinematic_elapsed / 6.0, 0.0, 1.0)
			boss.stage = 2 if cinematic_elapsed >= 3.0 else 1
			boss.position.y = lerpf(235.0, 255.0, boss.summon_progress)
			if cinematic_elapsed >= 6.0: finish_transition()
	else:
		super._process(delta)
		if finished: combo_hint.text = "守卫已击败 · 可拾取战利品，R重新挑战"
	info.text = "巨型魔神灰盒 · %s / %s槽\n生命 %.0f/%.0f · 法力 %.0f/%.0f" % [weapon_name(player.weapon), "A" if player.slot == 0 else "B", player.health, player.max_health, player.mana, player.max_mana]
	status_label.text = "金币 %d · 负重 %.1f/%.1f\nF暂停 %s · G无敌 %s" % [player.character_state.gold, player.character_state.stats.effective_burden, player.character_state.stats.carry_capacity, "开" if freeze_ai else "关", "开" if invincible else "关"]
	boss_bar.max_value = boss.max_health
	boss_bar.value = boss.health
	boss_label.text = "镇疆魔神 · %s  %.0f%%" % ["固定防线" if boss.stage == 1 else "脱困追击", boss.health / boss.max_health * 100.0]
	cast_label.text = boss.cast_name if not finished else "守卫停止 · 战斗结束"
	if boss.pending_checkpoint > 0 and not marathon_active: cast_label.text = "阶段护盾 · 完成当前动作后进入%d%%固定机制" % boss.pending_checkpoint
	cast_bar.value = clampf(1.0 - boss.mode_time / maxf(0.01, boss.cast_total), 0.0, 1.0) * 100.0
	impact_flash = maxf(0.0, impact_flash - delta)
	view_shake = maxf(0.0, view_shake - delta)
	queue_redraw()

func actor_died(actor) -> void:
	clear_transient_attacks()
	if marathon_active: marathon.cancel()
	mechanism_moving = false
	if actor == player:
		combat_over = true
		result_label.text = "挑战失败 · R重新挑战"
	else:
		finished = true
		defeated = 1
		result_label.text = "防线突破 · 可拾取战利品"
		boss.cast_name = "守卫停止"
		spawn_gold(100, Vector2(640, 430))
		spawn_item_drop(Instance.new(load("res://data/items/body_heavy.tres")), Vector2(610, 430))
		spawn_item_drop(Instance.new(load("res://data/items/iron_fragment.tres"), 8), Vector2(680, 430))
		boss.set_deferred("collision_layer", 0)
		boss.set_deferred("collision_mask", 0)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("172229"))
	draw_rect(FIELD, Color("303d43"))
	for x in range(80, 1200, 40): draw_line(Vector2(x, 140), Vector2(x, 620), Color("37484d"))
	for y in range(140, 620, 40): draw_line(Vector2(80, y), Vector2(1200, y), Color("37484d"))
	draw_rect(FIELD, Color("8b8f86"), false, 5.0)
	for x in range(90, 1190, 85):
		draw_rect(Rect2(x, 140, 73, 20), Color("52585b"))
		draw_line(Vector2(x + 10, 147), Vector2(x + 48, 160), Color("929486"), 2.0)
	if boss != null and boss.stage == 1:
		draw_rect(Rect2(535, 160, 210, 70), Color("4c5358"))
		for side in [-1, 1]: draw_line(Vector2(640 + side * 42, 170), Vector2(640 + side * 125, 145), Color("a99876"), 6.0)
	draw_rect(FALLBACK, Color(0.24, 0.47, 0.40, 0.25))
	draw_string(FONT, Vector2(510, 583), "南侧撤离带 · 不消耗掩体", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("a5cdb4"))
	if boss != null and boss.mode in ["clearance", "blast"] and not finished:
		for cover in covers:
			if cover.highlighted:
				draw_rect(cover_shadow(cover), Color(0.34, 0.78, 0.58, 0.18))
		var landing: Vector2 = predicted_landing(player.position) if boss.mode == "clearance" else launch_to
		draw_line(player.position, landing, Color("8adbd2"), 3.0)
		draw_arc(landing, player.radius + 6, 0, TAU, 28, Color("8adbd2"), 3.0)
		draw_string(FONT, landing + Vector2(-25, -28), "落点", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("c5f8e7"))
	if boss != null and boss.mode == "sword":
		for angle in [-0.28, 0.28]: draw_line(boss.position, boss.position + boss.aimed.rotated(angle) * 900, Color(0.95, 0.65, 0.44, 0.38), 12.0)
	if boss != null and boss.mode == "machine":
		var angle: float = -1.05 + clampf((boss.action_clock - 1.0) / 1.5, 0, 1) * 2.1
		draw_line(boss.position, boss.position + Vector2.DOWN.rotated(angle) * 1000, Color("ecaa73"), 3.0)
	if boss != null and boss.mode == "dash_charge":
		var side: Vector2 = boss.aimed.orthogonal() * boss.radius
		var origin: Vector2 = boss.position
		draw_colored_polygon(PackedVector2Array([origin + side, origin - side, origin + boss.aimed * 410 - side, origin + boss.aimed * 410 + side]), Color(1, 0.32, 0.24, 0.2))
	if boss != null and boss.mode == "slash":
		var arc: float = deg_to_rad(105.0 if boss.slash_index < 2 else 80.0)
		var length: float = 185.0 if boss.slash_index < 2 else 220.0
		var points = PackedVector2Array([boss.position])
		for i in range(37): points.append(boss.position + boss.aimed.rotated(-arc / 2.0 + arc * float(i) / 36.0) * length)
		draw_colored_polygon(points, Color(0.95, 0.5, 0.32, 0.16))
	if boss != null and boss.mode == "ring": draw_arc(boss.position, 155, 0, TAU, 50, Color("dfa088"), 3.0)
	if player != null and not inventory_open and not combat_frozen:
		var mouse: Vector2 = get_global_mouse_position()
		draw_arc(mouse, 8, 0, TAU, 20, Color("a2dad2"), 1.0)
	if combat_frozen and not marathon_active:
		for i in range(12):
			var bearing: Vector2 = Vector2.from_angle(float(i) * TAU / 12.0)
			var at: Vector2 = Vector2(640, 235) + bearing * (80 + cinematic_elapsed * 25)
			draw_rect(Rect2(at, Vector2(9, 6)), Color("bdb4a1"))
	if impact_flash > 0.0: draw_rect(FIELD, Color(0.9, 0.76, 0.61, impact_flash * 0.4))
