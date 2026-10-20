extends Node2D
## Fixed health checkpoints: safe introduction, controllable dodge sequence, recovery.
const Hazard = preload("res://scripts/boss/boss_hazard.gd")
var active: bool = false
var intro: bool = false
var checkpoint: int = 0
var clock: float = 0.0
var end_time: float = 0.0
var next_shot: float = 0.0
var shot_count: int = 0
var serial: int = 0
var travel_gap: float = 2.4
var entry_speed: float = 200.0
var title: String = ""
var origin: Vector2 = Vector2(640, 380)

func start(value: int) -> void:
	var room = get_parent()
	checkpoint = value
	serial += 1
	active = true
	intro = true
	clock = 0.0
	room.marathon_active = true
	room.hold_fire = true
	room.combat_frozen = true
	room.clear_transient_attacks()
	room.reset_player_action()
	room.boss.core_open = false
	room.boss.set_mode("marathon", 1.8, "核心封闭 · 固定机制演出")
	title = {45: "剑阵封庭", 30: "九连炮击", 15: "魔神审判"}.get(value, "防线肃清")
	room.overlay.visible = true
	room.cinema_label.visible = true
	room.cinema_label.text = "%d%% · %s\n核心封闭：接下来只需移动躲避 / Esc 跳过引子" % [value, title]

func finish_intro() -> void:
	if not active or not intro: return
	var room = get_parent()
	intro = false
	clock = 0.0
	room.combat_frozen = false
	room.overlay.visible = false
	room.cinema_label.visible = false
	room.boss.position = Vector2(640, 235)
	if room.player.position.distance_to(room.boss.position) < room.boss.radius + room.player.radius + 12.0:
		room.player.position = Vector2(640, 565)
	room.boss.velocity = Vector2.ZERO
	var speed: float = maxf(1.0, float(room.player.character_state.stats.final_move_speed))
	travel_gap = maxf(2.2, 300.0 / speed + 0.8)
	entry_speed = speed
	shot_count = 0
	next_shot = 0.8
	match checkpoint:
		45:
			var first: float = maxf(3.0, 800.0 / speed + 1.0)
			for wave in range(3):
				for lane in range(5):
					if lane == wave + 1: continue
					hazard({"kind": "line", "position": Vector2(192 + lane * 224, 140), "direction": Vector2.DOWN, "reach": 480.0, "width": 224.0, "delay": first + wave * travel_gap, "damage": 42.0, "push": 0.0, "attack_group": group_id(wave)})
			end_time = first + 2.0 * travel_gap + 0.8
			room.notify_player("剑阵：空白通道依次向右移动；进入已爆通道。停手期间可移动、换武器、使用侧步")
		30:
			travel_gap = maxf(1.0, 170.0 / speed + 0.4)
			end_time = next_shot + 8.0 * travel_gap + maxf(1.5, 155.0 / speed + 0.8) + 0.8
			room.notify_player("九连炮击：每次落点记录后固定，保持移动；第九发结束核心开放")
		15:
			var first: float = maxf(3.0, 350.0 / speed + 1.0)
			for wave in range(3):
				var north: bool = wave % 2 == 0
				hazard({"kind": "line", "position": Vector2(80, 240 if north else 480), "direction": Vector2.RIGHT, "reach": 1120.0, "width": 200.0 if north else 280.0, "delay": first + wave * travel_gap, "damage": 46.0, "push": 0.0, "attack_group": group_id(wave)})
			var inner_at: float = first + 2.0 * travel_gap + maxf(3.0, 260.0 / speed + 1.0)
			hazard({"kind": "circle", "position": origin, "radius": 145.0, "delay": inner_at, "damage": 46.0, "push": 0.0, "attack_group": group_id(3)})
			var outer_at: float = inner_at + maxf(3.0, 600.0 / speed + 1.0)
			hazard({"kind": "donut", "position": origin, "inner_radius": 145.0, "radius": 690.0, "delay": outer_at, "damage": 54.0, "push": 0.0, "attack_group": group_id(4)})
			end_time = outer_at + 0.8
			room.notify_player("审判：南 → 北 → 南躲三次扫场，再先远离中心、最后回到中心")
	room.boss.set_mode("marathon", end_time, title + " · 停手走位，核心封闭")

func group_id(wave: int) -> String:
	return "marathon_%d_%d" % [serial, wave]

func hazard(values: Dictionary) -> void:
	if checkpoint in [45, 15]:
		var wave: int = int(str(values.get("attack_group", "_0")).get_slice("_", 2))
		values["telegraph_time"] = float(values.get("delay", 0.0)) if wave == 0 else travel_gap
		if checkpoint == 15 and wave >= 3:
			var speed: float = maxf(1.0, float(get_parent().player.character_state.stats.final_move_speed))
			values["telegraph_time"] = maxf(3.0, (600.0 if wave == 4 else 260.0) / speed + 1.0)
	var effect = Hazard.new()
	effect.configure(values)
	get_parent().add_child(effect)

func _physics_process(delta: float) -> void:
	if not active: return
	var room = get_parent()
	if room.combat_over or room.finished:
		cancel()
		return
	if room.freeze_ai: return
	clock += delta if intro else delta * time_scale()
	queue_redraw()
	if intro:
		if clock >= 1.8: finish_intro()
		return
	room.boss.mode_time = maxf(0.0, end_time - clock)
	if checkpoint == 30 and shot_count < 9 and clock >= next_shot:
		var speed: float = entry_speed
		hazard({"kind": "circle", "position": room.player.position, "radius": 64.0, "delay": maxf(1.5, 155.0 / speed + 0.8), "damage": 34.0, "push": 0.0, "number": shot_count + 1, "attack_group": group_id(shot_count)})
		shot_count += 1
		next_shot += travel_gap
		room.boss.cast_name = "九连炮击 %d/9 · 落点锁定后移动" % shot_count
	if clock >= end_time:
		cancel()
		room.boss.complete_marathon(checkpoint)
		room.notify_player(title + "结束 · 核心暴露4秒，可以接换武器连段")

func time_scale() -> float:
	if intro: return 1.0
	var current_speed: float = maxf(1.0, float(get_parent().player.character_state.stats.final_move_speed))
	return minf(1.0, current_speed / maxf(1.0, entry_speed))

func cancel() -> void:
	active = false
	intro = false
	var room = get_parent()
	room.marathon_active = false
	room.hold_fire = false
	room.combat_frozen = false
	room.overlay.visible = false
	room.cinema_label.visible = false
	room.reset_player_action()
	queue_redraw()

func _draw() -> void:
	if not active: return
	var room = get_parent()
	var at: Vector2 = room.boss.position
	if intro:
		for i in range(8):
			var angle: float = float(i) * TAU / 8.0 + clock * 0.7
			var ray: Vector2 = Vector2.from_angle(angle)
			draw_line(at + ray * 35.0, at + ray * (80.0 + clock * 28.0), Color(0.83, 0.66, 1.0, 0.55), 5.0)
		var spirit: Vector2 = at + Vector2(0, -100.0 - sin(clock * PI / 1.8) * 35.0)
		draw_circle(spirit, 22.0, Color(0.88, 0.67, 1.0, 0.5))
	draw_arc(at, 100.0 + sin(clock * 4.0) * 4.0, 0, TAU, 64, Color("d4b9ef"), 3.0)
	draw_string(preload("res://assets/NotoSansSC.ttf"), at + Vector2(-42, -132), "核心封闭", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("dbc0ef"))
