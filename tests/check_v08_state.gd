extends SceneTree
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	if not value: failures.append(label)
func disable_ticks(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): disable_ticks(child)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var room = load("res://scenes/boss_arena.tscn").instantiate()
	root.add_child(room)
	await process_frame
	disable_ticks(room)
	room.invincible = true
	var boss = room.boss
	check(root.content_scale_size == Vector2i(1280, 720), "logical viewport")
	check(ProjectSettings.get_setting("display/window/stretch/aspect") == "keep", "aspect")
	boss.enter_stage_two()
	var amount: float = boss.take_hit(100000.0)
	check(amount > 0.0 and boss.pending_checkpoint == 45, "first damage crossing")
	check(is_equal_approx(boss.health, boss.max_health * 0.45), "threshold floor")
	check(boss.deferred_damage > 0.0, "overflow retained")
	for threshold in [45, 30, 15]:
		check(boss.pending_checkpoint == threshold, "ordered checkpoint %d" % threshold)
		room.begin_marathon(threshold)
		check(room.combat_frozen and room.marathon_active and room.hold_fire, "safe intro")
		room.marathon.finish_intro()
		check(not room.combat_frozen and room.hold_fire, "dodge control")
		var hp: float = boss.health
		check(boss.take_hit(1000.0) == 0.0 and boss.health == hp, "shield")
		room.player.begin_attack()
		check(room.player.phase == "idle", "held attacks blocked")
		var timer: float = room.marathon.clock
		room.freeze_ai = true
		room.marathon._physics_process(1.0)
		check(room.marathon.clock == timer, "F pauses mechanism")
		room.freeze_ai = false
		for i in range(1000):
			if not room.marathon.active: break
			room.marathon._physics_process(0.1)
		check(not room.marathon.active and not room.hold_fire and not room.combat_frozen, "control restored")
		check(boss.checkpoints_done.has(threshold) and boss.core_open and boss.mode_time == 4.0, "recovery window")
		if threshold == 30: check(room.marathon.shot_count == 9, "nine shells")
		room.clear_transient_attacks()
		await process_frame
		boss._physics_process(4.01)
	check(room.finished and boss.health <= 0.0, "banked lethal damage after all checkpoints")
	var hazard = load("res://scripts/boss/boss_hazard.gd").new()
	hazard.kind = "donut"
	hazard.inner_radius = 145.0
	hazard.radius = 690.0
	check(not hazard.contains(Vector2.ZERO, 18.0), "donut center safe")
	check(hazard.contains(Vector2(150, 0), 18.0), "donut collision radius")
	hazard.free()
	print("V08_STATE_CHECKS ", "PASS" if failures.is_empty() else failures)
	room.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
