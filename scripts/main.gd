extends Node2D
const ExplorationCamera = preload("res://scripts/visuals/exploration_camera.gd")
@export var exploration_bounds: Rect2 = Rect2(0, 0, 1280, 720)
const FONT := preload("res://assets/NotoSansSC.ttf")
const Weapons := preload("res://scripts/weapons.gd")
const Actor := preload("res://scripts/actor.gd")
const Projectile := preload("res://scripts/projectile.gd")
const Rules := preload("res://scripts/combat_rules.gd")
const Terrain := preload("res://scripts/terrain.gd")
const InventoryPanel := preload("res://scripts/ui/inventory_panel.gd")
const Loot := preload("res://scripts/world_loot.gd")
const Instance := preload("res://scripts/systems/item_instance.gd")
const Catalog := preload("res://scripts/data/starter_catalog.gd")
var skill_labels: Array[Label] = []
var combo_hint: Label
var inventory_open := false
var inventory_panel
var auto_materials := false
var auto_consumables := false
var pickup_clock := 0.0
var pickup_hint: Label
var notification: Label
var notification_remaining := 0.0
var mp_bar: ProgressBar
var random := RandomNumberGenerator.new()
const MAP_DATA := [
 {"rect": Rect2(440, 220, 100, 180), "title": "STONE"},
 {"rect": Rect2(720, 410, 180, 70), "ranged_pass": true, "title": "LOW COVER"},
 {"rect": Rect2(900, 180, 80, 120), "title": "STONE"},
 {"rect": Rect2(240, 480, 120, 12), "pass_direction": Vector2.UP, "ranged_pass": true, "title": ""},
 {"rect": Rect2(620, 340, 80, 60), "destructible": true, "title": "BREAKABLE"},
 {"rect": Rect2(1040, 200, 20, 60), "destructible": true, "reveals_secret": true, "title": ""},
 {"rect": Rect2(1040, 140, 140, 20), "title": ""},
 {"rect": Rect2(1160, 140, 20, 180), "title": ""},
 {"rect": Rect2(1040, 300, 140, 20), "title": ""},
 {"rect": Rect2(1040, 160, 20, 40), "title": ""},
 {"rect": Rect2(1040, 260, 20, 40), "title": ""}
]
var terrains: Array = []
var secret_revealed := false
var player
var combat_over := false
var nav := AStar2D.new()
var info: Label
var result_label: Label
var hp_bar: ProgressBar
var defeated := 0
var total := 5
var freeze_ai := false
var invincible := false
var show_ranges := true
var log_label: Label
var damage_labels: Array = []
var status_label: Label

func _ready() -> void:
	setup_inputs()
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	random.randomize()
	for rect in [Rect2(60, 90, 1160, 20), Rect2(60, 620, 1160, 20), Rect2(60, 90, 20, 550), Rect2(1200, 90, 20, 550)]:
		add_wall(rect)
	for data in MAP_DATA:
		var terrain := Terrain.new()
		terrain.configure(data)
		add_child(terrain)
		terrains.append(terrain)
	setup_nav()
	player = Actor.new()
	player.is_player = true
	player.max_health = 300.0
	player.health = 300.0
	player.position = Vector2(260, 360)
	player.facing = Vector2.RIGHT
	add_child(player)
	for item in [[Vector2(370,290),0,false,true],[Vector2(370,410),0,false,true],[Vector2(620,230),0,false,false],[Vector2(660,530),0,true,false],[Vector2(860,350),1,false,false],[Vector2(1080,520),2,false,false],[Vector2(1100,370),0,false,false]]:
		var enemy = Actor.new()
		enemy.position = item[0]
		enemy.rank = item[1]
		enemy.ranged_enemy = item[2]
		enemy.dummy = item[3]
		enemy.radius = 18.0
		enemy.max_health = 220.0 + enemy.rank*160.0
		enemy.health = enemy.max_health
		enemy.title = "训练木偶" if enemy.dummy else ("守卫首领" if enemy.rank==2 else ("精英卫士" if enemy.rank==1 else ("远程斥候" if enemy.ranged_enemy else "近战游荡者")))
		enemy.target = player
		add_child(enemy)
	var camera = ExplorationCamera.new()
	camera.target_actor = player
	camera.map_bounds = exploration_bounds
	add_child(camera)
	setup_hud()
	setup_inventory_and_drops()

func setup_inputs() -> void:
	for action in ["attack", "swap_weapon", "restart"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", mouse)
	for pair in [["attack", KEY_J], ["attack", KEY_SPACE], ["swap_weapon", KEY_Q], ["restart", KEY_R]]:
		var key := InputEventKey.new()
		key.physical_keycode = pair[1]
		InputMap.action_add_event(pair[0], key)

func add_wall(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = rect.get_center()
	body.collision_layer = 1 | 8 | 16
	body.collision_mask = 0
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collider.shape = shape
	body.add_child(collider)
	add_child(body)

func setup_nav() -> void:
	nav.clear()
	for x in range(64):
		for y in range(36):
			var point := Vector2(x * 20 + 10, y * 20 + 10)
			var blocked := not Rect2(104, 134, 1072, 462).has_point(point)
			for terrain in terrains:
				if not terrain.destroyed and terrain.pass_direction.is_zero_approx() and terrain.rect.grow(22.0).has_point(point):
					blocked = true
			if not blocked:
				nav.add_point(y * 64 + x, point)
	for id in nav.get_point_ids():
		var x: int = id % 64
		var y: int = id / 64
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var other: int = (y + dy) * 64 + x + dx
				if x + dx < 0 or x + dx >= 64 or not nav.has_point(other):
					continue
				if dx != 0 and dy != 0 and (not nav.has_point(y * 64 + x + dx) or not nav.has_point((y + dy) * 64 + x)):
					continue
				if gate_allows(nav.get_point_position(id), nav.get_point_position(other)):
					nav.connect_points(id, other, false)

func gate_allows(from: Vector2, to: Vector2) -> bool:
	for terrain in terrains:
		if terrain.destroyed or terrain.pass_direction.is_zero_approx():
			continue
		var r: Rect2 = terrain.rect.grow(20.0)
		if r.has_point(from) or r.has_point(to):
			if (to - from).dot(terrain.pass_direction) <= 0.0:
				return false
	return true

func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	return nav.get_point_path(nav.get_closest_point(from), nav.get_closest_point(to))

func clear_line(from: Vector2, to: Vector2, ranged: bool = false, excluded: Array[RID] = []) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, 8 if ranged else 16)
	query.exclude = excluded
	query.hit_from_inside = true
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func damage_terrain(actor, previous: float, current: float) -> void:
	for terrain in terrains:
		if terrain.destroyed or not terrain.destructible or actor.hit_ids.has(terrain.get_instance_id()): continue
		var r: Rect2 = terrain.rect
		var closest:=Vector2(clampf(actor.position.x,r.position.x,r.end.x),clampf(actor.position.y,r.position.y,r.end.y))
		var samples: Array[Vector2]=[closest,r.get_center(),r.position,r.end,Vector2(r.position.x,r.end.y),Vector2(r.end.x,r.position.y)]
		for point in samples:
			if actor.point_in_sweep(point,previous,current) and clear_line(actor.position,point,false,[terrain.get_rid()]):
				actor.hit_ids[terrain.get_instance_id()]=true
				terrain.take_hit(float(actor.attack_data.damage))
				break

func terrain_destroyed(terrain) -> void:
	if terrain.reveals_secret:
		secret_revealed = true
		spawn_item_drop(Instance.new(load("res://data/items/harness_pack.tres")), Vector2(1110, 220))
		spawn_gold(35, Vector2(1095, 255))
		spawn_item_drop(Instance.new(load("res://data/items/old_city_rune.tres")), Vector2(1090, 230))
	else:
		spawn_item_drop(Instance.new(load("res://data/items/iron_fragment.tres"), 3), terrain.position)
	# Rebuild directed navigation after the obstacle becomes ordinary floor.
	setup_nav.call_deferred()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.path_remaining = 0.0
	queue_redraw()

func fire_arrow(actor,direction: Vector2,data: Dictionary,shared: Dictionary={}, origin: Vector2 = Vector2.INF) -> void:
	var arrow:=Projectile.new()
	arrow.position=actor.position if origin == Vector2.INF else origin
	arrow.attack_data = data.duplicate()
	# All arrows from a scatter group share the same reward/context tracker.
	arrow.attack_data["context"] = data.get("context", {"kind": "secondary"})
	arrow.direction=direction
	arrow.damage=float(data.damage)
	arrow.strength=float(data.strength)
	arrow.fraction=float(data.push)
	arrow.remaining=float(data.range)
	arrow.from_player=actor.is_player
	arrow.source_actor=actor
	arrow.shared_hits=shared
	add_child(arrow)

func show_damage(at: Vector2,damage: float) -> void:
	var label:=Label.new()
	label.text=str(int(damage))
	label.position=at+Vector2(-10,-48)
	label.add_theme_color_override("font_color",Color("f1d9aa"))
	label.add_theme_font_size_override("font_size",18)
	label.z_index=20
	add_child(label)
	var tween:=create_tween()
	tween.tween_property(label,"position:y",label.position.y-25,.5)
	tween.parallel().tween_property(label,"modulate:a",0.0,.5)
	tween.tween_callback(label.queue_free)

func actor_died(actor) -> void:
	if actor.is_player:
		combat_over = true
		result_label.text = "DEFEATED  /  R TO RESTART"
	else:
		if actor.dummy: return
		roll_enemy_loot(actor)
		defeated += 1
		if defeated == total:
			combat_over = true
			result_label.text = "ROOM CLEARED  /  EXPLORE OR PRESS R"
			combat_over = false

func make_label(parent: Node, at: Vector2, text: String, size: int=16) -> Label:
	var label:=Label.new()
	label.position=at
	label.add_theme_font_override("font",FONT)
	label.text=text
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color("d6dfd8"))
	parent.add_child(label)
	return label

func setup_hud() -> void:
	var canvas:=CanvasLayer.new()
	add_child(canvas)
	info=make_label(canvas,Vector2(80,13),"",18)
	hp_bar=ProgressBar.new()
	hp_bar.position=Vector2(80,70)
	hp_bar.size=Vector2(250,8)
	hp_bar.max_value=player.max_health
	hp_bar.show_percentage=false
	canvas.add_child(hp_bar)
	status_label=make_label(canvas,Vector2(735,20),"",15)
	make_label(canvas,Vector2(80,648),"WASD 移动   左键 / J 攻击   Q / 滚轮 衔接   1 武器技能   2 / 3 装备技能   Tab 掉落   E 拾取   I / B 背包",14)
	make_label(canvas,Vector2(80,677),"F 怪物开关   G 无敌   V 攻击圈   R 重置   棕：可破坏   青：箭可穿过   紫：向上通行",14)
	mp_bar = ProgressBar.new()
	mp_bar.position = Vector2(80, 83)
	mp_bar.size = Vector2(250, 7)
	mp_bar.show_percentage = false
	var blue := StyleBoxFlat.new()
	blue.bg_color = Color("538bbf")
	mp_bar.add_theme_stylebox_override("fill", blue)
	canvas.add_child(mp_bar)
	var red := StyleBoxFlat.new()
	red.bg_color = Color("c15d56")
	hp_bar.add_theme_stylebox_override("fill", red)
	pickup_hint = make_label(canvas, Vector2(770, 593), "", 13)
	pickup_hint.size = Vector2(420, 24)
	pickup_hint.clip_text = true
	notification = make_label(canvas, Vector2(430, 562), "", 15)
	result_label=make_label(canvas,Vector2(415,315),"",25)
	for i in range(3):
		var label: Label = make_label(canvas, Vector2(365 + i * 265, 60), "", 13)
		label.size = Vector2(255, 44)
		label.clip_text = true
		skill_labels.append(label)
	combo_hint = make_label(canvas, Vector2(85, 593), "", 14)
	combo_hint.size = Vector2(675, 24)
	combo_hint.clip_text = true
	make_label(canvas,Vector2(105,130),"01 / 自由试招",15)
	make_label(canvas,Vector2(570,130),"02 / 障碍与交战",15)
	make_label(canvas,Vector2(1035,115),"03 / 隐藏区域",13)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_I, KEY_B: inventory_panel.open_panel()
		KEY_E:
			var drop = nearest_drop()
			if drop != null: collect_drop(drop, false)
		KEY_F: freeze_ai=not freeze_ai
		KEY_G: invincible=not invincible
		KEY_V: show_ranges=not show_ranges
		KEY_F2: get_tree().change_scene_to_file("res://scenes/boss_arena.tscn")

func weapon_name(index: int) -> String:
	return Weapons.NAMES[index] if index >= 0 and index < Weapons.NAMES.size() else "空"

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
		return
	notification_remaining = maxf(0.0, notification_remaining - delta)
	if notification_remaining <= 0.0: notification.text = ""
	var phase_name: String = {"idle":"就绪", "windup":"前摇", "active":"判定", "recovery":"后摇", "transition":"换武器"}[player.phase]
	info.text = "装备BD演武场   /   %s  ·  鼠标全向  ·  %s\n%s  连击 %d/4  %s %.2fs" % [weapon_name(player.weapon), "A槽" if player.slot == 0 else "B槽", player.attack_data.get("name", "待机"), player.combo + 1, phase_name, player.phase_remaining]
	for i in range(3):
		var skill: Dictionary = player.runtime.skill_for_key(i + 1)
		if skill.is_empty():
			skill_labels[i].text = "[%d] 未选择技能\n背包中点击技能栏选择来源" % (i + 1)
		else:
			var remaining: float = player.runtime.remaining(skill)
			var state_text: String = "CD %.1fs" % remaining if remaining > 0.0 else ("法力不足" if player.mana < float(skill.get("mana", 0.0)) else "就绪")
			skill_labels[i].text = "[%d] %s · %s · 蓝%.0f\n%s" % [i + 1, skill.name, state_text, skill.get("mana", 0.0), skill.source_name]
	combo_hint.text = "跨武器衔接 %.2fs → 第%d段" % [player.cross_remaining, player.next_combo + 1] if player.cross_remaining > 0.0 and player.next_combo > 0 else "1 武器主动；2/3 装备主动 · 血契 / 残像 / 突袭装备在起点左侧"
	var stats: Dictionary = player.character_state.stats
	status_label.text = "金币 %d  ·  负担 %.1f/%.1f kg  ·  击败 %d/%d\nA %s / B %s  ·  怪物 %s [F]  ·  无敌 %s [G]" % [player.character_state.gold, stats.effective_burden, stats.carry_capacity, defeated, total, weapon_name(player.slots[0]), weapon_name(player.slots[1]), "开" if not freeze_ai else "关", "开" if invincible else "关"]
	hp_bar.max_value = player.max_health
	hp_bar.value = player.health
	mp_bar.max_value = maxf(1.0, player.max_mana)
	mp_bar.value = player.mana
	var closest = nearest_drop()
	pickup_hint.text = "[E] " + closest.title() if closest != null else "金币自动拾取；装备按E拾取"
	if Input.is_physical_key_pressed(KEY_E):
		var labels: Array[String] = []
		for drop in nearby_drops(): labels.append(drop.title())
		pickup_hint.text = "附近：" + " / ".join(labels.slice(0, 4))
	var show_all_drops := Input.is_physical_key_pressed(KEY_TAB)
	for drop in get_tree().get_nodes_in_group("ground_loot"):
		drop.show_label = not drop.claimed and (show_all_drops or drop == closest or (Input.is_physical_key_pressed(KEY_E) and player.position.distance_to(drop.position) <= player.radius * 6.0))
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("172326"))
	draw_rect(Rect2(80, 110, 1120, 510), Color("243235"))
	for x in range(80, 1200, 40):
		draw_line(Vector2(x, 110), Vector2(x, 620), Color("2c3c3c"))
	for y in range(110, 620, 40):
		draw_line(Vector2(80, y), Vector2(1200, y), Color("2c3c3c"))
	draw_rect(Rect2(70, 100, 1140, 530), Color("6b8194"), false, 5.0)
	var hidden := Rect2(1060, 160, 100, 140)
	draw_rect(hidden, Color("294e4f") if secret_revealed else Color("0b111c"))
	if secret_revealed:
		draw_string(ThemeDB.fallback_font, Vector2(1070, 230), "SECRET", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ace7d2"))
	if player != null and not inventory_open:
		var mouse := get_global_mouse_position()
		draw_arc(mouse, 8, 0, TAU, 20, Color("a2dad2"), 1.0)
		draw_line(mouse - Vector2(12, 0), mouse + Vector2(12, 0), Color("a2dad2"), 1.0)
		draw_line(mouse - Vector2(0, 12), mouse + Vector2(0, 12), Color("a2dad2"), 1.0)


func notify_player(value: String) -> void:
	notification.text = value
	notification_remaining = 2.0

func setup_inventory_and_drops() -> void:
	var state = player.character_state
	state.equip("backpack", Instance.new(load("res://data/items/basic_pack.tres")))
	for id in ["crit_ring", "vampire_ring", "gloves_light"]:
		player.inventory_model.add(Instance.new(load("res://data/items/" + id + ".tres")))
	player.inventory_model.add(Instance.new(load("res://data/items/iron_fragment.tres"), 5))
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	inventory_panel = InventoryPanel.new()
	inventory_panel.configure(self, player.inventory_model)
	layer.add_child(inventory_panel)
	# Samples at reachable locations. Other gear is earned from fights and the hidden room.
	for pair in [[Vector2(180, 230), "starter_blade"], [Vector2(210, 230), "starter_whip"], [Vector2(240, 230), "starter_spear"], [Vector2(180, 270), "body_heavy"], [Vector2(210, 270), "boots_light"]]:
		spawn_item_drop(Instance.new(load("res://data/items/" + pair[1] + ".tres")), pair[0])
	spawn_gold(15, Vector2(280, 330))
	# Eight sample items form three freely mixed builds; no forced presets.
	for i in range(Catalog.BD_IDS.size()):
		var id: String = Catalog.BD_IDS[i]
		spawn_item_drop(Instance.new(load("res://data/items/" + id + ".tres")), Vector2(125 + (i % 4) * 48, 475 + int(i / 4) * 48))

func safe_drop_position(origin: Vector2) -> Vector2:
	for i in range(17):
		var candidate := origin if i == 0 else origin + Vector2.from_angle(float(i - 1) * TAU / 8.0) * (16.0 if i <= 8 else 32.0)
		if not Rect2(95, 125, 1090, 485).has_point(candidate): continue
		var blocked := false
		for terrain in terrains:
			if not terrain.destroyed and terrain.rect.grow(9.0).has_point(candidate): blocked = true
		if not blocked: return candidate
	return player.position

func spawn_item_drop(item, origin: Vector2, player_dropped: bool = false) -> void:
	var drop := Loot.new()
	drop.item = item
	drop.auto_disabled = player_dropped
	drop.position = safe_drop_position(origin)
	add_child(drop)

func spawn_gold(amount: int, origin: Vector2) -> void:
	var drop := Loot.new()
	drop.gold = maxi(1, amount)
	drop.position = safe_drop_position(origin)
	add_child(drop)

func roll_enemy_loot(actor) -> void:
	spawn_gold(random.randi_range(8, 15) + actor.rank * 12, actor.position + Vector2(-8, 5))
	if random.randf() < 0.65:
		spawn_item_drop(Instance.new(load("res://data/items/iron_fragment.tres"), random.randi_range(2, 6)), actor.position + Vector2(12, 5))
	if actor.rank > 0 or random.randf() < 0.35:
		var choices: Array = ["body_cloth", "legs_light", "helmet_heavy", "belt_light", "boots_light", "gloves_heavy"]
		if actor.rank == 2: choices = ["body_heavy", "vampire_ring", "harness_pack"]
		var id: String = choices[random.randi_range(0, choices.size() - 1)]
		spawn_item_drop(Instance.new(load("res://data/items/" + id + ".tres")), actor.position + Vector2(0, -14))

func pickup_clear(drop) -> bool:
	var query := PhysicsRayQueryParameters2D.create(player.position, drop.position, 1)
	query.hit_from_inside = true
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func nearby_drops() -> Array:
	var result: Array = []
	if player.health <= 0.0: return result
	for drop in get_tree().get_nodes_in_group("ground_loot"):
		if not drop.claimed and player.position.distance_to(drop.position) <= player.radius * 3.0 and pickup_clear(drop): result.append(drop)
	result.sort_custom(func(a, b): return player.position.distance_squared_to(a.position) < player.position.distance_squared_to(b.position))
	return result

func nearest_drop():
	var nearby := nearby_drops()
	if nearby.is_empty(): return null
	# Mouse hover chooses a nearby pile; otherwise E picks the closest to the character.
	var mouse := get_global_mouse_position()
	for drop in nearby:
		if mouse.distance_to(drop.position) < 18.0: return drop
	return nearby[0]

func collect_drop(drop, automatic: bool) -> void:
	if drop == null or drop.claimed or player.health <= 0.0: return
	var picked_title: String = drop.title()
	var result: Dictionary = {"ok": true}
	if drop.gold > 0:
		player.character_state.add_gold(drop.gold)
	elif drop.item != null and drop.item.definition.item_type == "quest":
		var key: String = drop.item.definition.id
		player.character_state.quest_items[key] = int(player.character_state.quest_items.get(key, 0)) + drop.item.quantity
	else:
		result = player.inventory_model.add(drop.item, automatic)
	if result.ok:
		drop.claimed = true
		notify_player("获得 " + picked_title)
		drop.queue_free()
	elif not automatic or not drop.notified:
		notify_player(result.error)
		drop.notified = true

func _physics_process(delta: float) -> void:
	if inventory_open or player.health <= 0.0: return
	pickup_clock -= delta
	if pickup_clock > 0.0: return
	pickup_clock = 0.12
	for drop in get_tree().get_nodes_in_group("ground_loot"):
		if drop.claimed or drop.auto_disabled or drop.age < 0.3: continue
		var kind: String = drop.item.definition.item_type if drop.item != null else "gold"
		var radius: float = player.radius * (6.0 if drop.gold > 0 else (4.0 if kind == "quest" else 3.0))
		var eligible: bool = drop.gold > 0 or kind == "quest" or (auto_materials and kind == "material")
		if auto_consumables and kind == "consumable":
			var room := 0
			for carried in player.character_state.inventory:
				if carried.definition.id == drop.item.definition.id and not carried.locked and is_equal_approx(carried.actual_weight_reduction, drop.item.actual_weight_reduction):
					room += maxi(0, carried.definition.max_stack - carried.quantity)
			eligible = room >= drop.item.quantity
		if eligible and player.position.distance_to(drop.position) <= radius and pickup_clear(drop): collect_drop(drop, true)
