extends SceneTree
const Weapons:=preload("res://scripts/weapons.gd")
const Rules:=preload("res://scripts/combat_rules.gd")
var room
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if ok: print("PASS ",message)
	else:
		failures+=1
		push_error("FAIL "+message)
func tick(frames: int=2) -> void:
	for i in range(frames):
		await physics_frame
		await process_frame
func key(code: Key,pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.physical_keycode=code
	event.keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)
func move_player(at: Vector2,code: Key,frames: int) -> void:
	var p=room.player
	p.position=at
	p.phase="idle"
	p.stagger=0
	p.push_remaining=0
	p.set_physics_process(true)
	key(code,true)
	await tick(frames)
	key(code,false)
	p.set_physics_process(false)
func reset_actor(actor,at: Vector2) -> void:
	actor.position=at
	actor.health=actor.max_health
	actor.phase="idle"
	actor.stagger=0
	actor.push_remaining=0
	actor.push_used=0
	actor.next_combo=0
	actor.combo_window=0
	actor.set_physics_process(false)
func run() -> void:
	room=load("res://scenes/main.tscn").instantiate()
	root.add_child(room)
	await tick()
	var p=room.player
	var enemies:=get_nodes_in_group("enemies")
	for enemy in enemies:
		enemy.set_physics_process(false)
		enemy.position=Vector2(1100,550)
	p.set_physics_process(false)
	# Every template preserves all three phases and produces a finite next combo.
	for w in range(5):
		for n in range(4):
			reset_actor(p,Vector2(260,270))
			p.equip(w)
			p.next_combo=n
			p.aim_mode=2
			p.facing=Vector2.RIGHT
			p.begin_attack()
			var d: Dictionary=p.attack_data
			p.advance_attack(float(d.windup)*.9)
			var before: bool=p.phase=="windup" and p.hit_ids.is_empty()
			p.advance_attack(float(d.windup)*.1+.00001)
			var during: bool=p.phase=="active"
			p.advance_attack(float(d.active)+float(d.recovery)+.01)
			check(before and during and p.phase=="idle" and p.next_combo==(n+1)%4,"weapon %d combo %d phases" % [w,n])
	await tick(50)
	reset_actor(p,Vector2(260,270))
	p.equip(4)
	p.aim_mode=0
	var near=enemies[0]
	var strong=enemies[5]
	near.position=Vector2(300,270)
	strong.position=Vector2(380,270)
	await tick()
	p.locked_target=null
	p.refresh_target()
	check(p.locked_target==near,"nearest mode selects nearest")
	p.aim_mode=1
	p.locked_target=null
	p.refresh_target()
	check(p.locked_target==strong,"strongest mode selects boss")
	near.position=Vector2(280,270)
	p.refresh_target()
	check(p.locked_target==strong,"lock stays stable")
	strong.position=Vector2(1000,550)
	p.refresh_target()
	check(p.locked_target==near,"out-of-range lock reacquires")
	p.aim_mode=2
	p.refresh_target()
	check(p.locked_target==null,"manual mode has no target")
	near.position=Vector2(1100,550)
	p.facing=Vector2.RIGHT
	await move_player(Vector2(260,270),KEY_S,15)
	check(p.position.y>290 and p.facing==Vector2.DOWN,"manual facing follows movement")
	p.set_physics_process(true)
	await tick(3)
	p.set_physics_process(false)
	check(p.facing==Vector2.DOWN,"manual facing persists after stopping")
	for mode in [0,1]:
		p.aim_mode=mode
		p.locked_target=null
		near.position=Vector2(340,270)
		await move_player(Vector2(260,270),KEY_S,8)
		check(p.facing==Vector2.RIGHT and p.locked_target==near,"auto lock stays independent mode %d" % mode)
	near.position=Vector2(1100,550)
	p.aim_mode=2
	# Movement permitted only for blade during attack; recoveries cannot be skipped.
	for w in [0,1,2,3]:
		reset_actor(p,Vector2(260,270))
		p.equip(w)
		p.begin_attack()
		p.set_physics_process(true)
		key(KEY_S,true)
		await tick(5)
		key(KEY_S,false)
		p.set_physics_process(false)
		check((p.position.y>272) if w==1 else is_equal_approx(p.position.y,270),"movement rule weapon %d" % w)
	# Real melee sweep strikes each target once, leaves rear untouched.
	reset_actor(p,Vector2(260,270))
	p.equip(0)
	p.facing=Vector2.RIGHT
	near.dummy=false
	reset_actor(near,Vector2(335,270))
	var back=enemies[1]
	back.dummy=false
	reset_actor(back,Vector2(205,270))
	await tick()
	p.begin_attack()
	p.advance_attack(.17)
	check(near.health==near.max_health-18 and back.health==back.max_health,"sword directional one hit")
	p.resolve_melee(0,1)
	check(near.health==near.max_health-18,"same swing cannot double-hit")
	# 360-degree third spear sweep can hit rear.
	reset_actor(p,Vector2(260,270))
	p.equip(3)
	p.next_combo=2
	p.begin_attack()
	p.advance_attack(.5)
	check(back.health==back.max_health-32,"spear third sweeps behind")
	# Bow spread has exactly three arrows, shares per-volley hit IDs.
	reset_actor(p,Vector2(260,270))
	p.equip(4)
	p.next_combo=2
	p.facing=Vector2.RIGHT
	p.aim_mode=2
	near.position=Vector2(340,270)
	near.health=near.max_health
	back.position=Vector2(1100,550)
	await tick()
	p.begin_attack()
	p.advance_attack(.26)
	check(get_nodes_in_group("arrows").size()==3,"bow third fires three arrows")
	await tick(30)
	check(near.health==near.max_health-23,"spread cannot shotgun one target")
	await tick(30)
	# Fourth retreat is physical and independent of voluntary movement.
	reset_actor(p,Vector2(260,270))
	p.equip(4)
	p.next_combo=3
	p.begin_attack()
	p.set_physics_process(true)
	await tick(12)
	p.set_physics_process(false)
	check(p.position.x<250 and p.position.x>=241.9,"bow fourth retreats half body")
	# Exponential push and actual chained cap.
	check(Rules.push_distance(36,.72,10,1,0,"light")<36,"push below one body")
	check(Rules.push_distance(36,.72,10,1,50,"heavy")<Rules.push_distance(36,.72,10,1,0,"light"),"weight and armor reduce push")
	reset_actor(near,Vector2(600,250))
	var origin: Vector2=near.position
	for i in range(20):
		near.take_hit(1,100,Vector2.RIGHT,.99)
		near.apply_push(.01)
	for i in range(30): near.apply_push(.01)
	check(near.position.distance_to(origin)<=36.01,"continuous knockback capped at body width")
	# Terrain regression through actual character physics.
	p.aim_mode=2
	await move_player(Vector2(400,300),KEY_D,30)
	check(p.position.x<423,"stone blocks movement")
	await move_player(Vector2(300,535),KEY_W,45)
	check(p.position.y<470,"one-way permits up")
	await move_player(Vector2(300,430),KEY_S,45)
	check(p.position.y<465,"one-way blocks down")
	check(room.clear_line(Vector2(800,370),Vector2(800,530),true),"low cover permits arrows")
	check(not room.clear_line(Vector2(800,370),Vector2(800,530)),"low cover blocks melee")
	room.terrains[5].take_hit(100)
	await tick()
	await move_player(Vector2(1010,230),KEY_D,40)
	check(room.secret_revealed and p.position.x>1070,"breakable becomes hidden walkable floor")
	# Enemy stops at range and misses if player leaves locked sector.
	var enemy=enemies[2]
	reset_actor(enemy,Vector2(600,250))
	reset_actor(p,Vector2(680,250))
	var input: Vector2=enemy.enemy_input(.02)
	check(input==Vector2.ZERO and enemy.phase=="windup","enemy stops within range")
	p.position=Vector2(600,150)
	room.invincible=false
	var hp: float=p.health
	enemy.advance_attack(.7)
	check(p.health==hp,"enemy locked attack can miss")
	reset_actor(p,Vector2(260,270))
	p.equip(0)
	p.next_combo=2
	p.begin_attack()
	p.take_hit(1,10,Vector2.RIGHT,.1)
	p.advance_attack(.4)
	check(p.next_combo==0,"interrupted combo resets after recovery")
	reset_actor(p,Vector2(260,270))
	p.equip(4)
	p.aim_mode=0
	near.position=Vector2(340,300)
	p.locked_target=near
	p.facing=Vector2.RIGHT
	p.begin_attack()
	p.aim_mode=2
	p.locked_target=null
	p.advance_attack(.19)
	check(p.shot_direction.y>0,"mode change waits until next attack")
	print("RESULT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
