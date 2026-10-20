extends Node2D
## Snapshot geometry: echoes never follow the player's later position or aim.
var source_actor
var data: Dictionary = {}
var direction: Vector2 = Vector2.RIGHT
var delay: float = 0.30
var visible_remaining: float = 0.0
var released: bool = false

func configure(source, original: Dictionary, bearing: Vector2) -> void:
	source_actor = weakref(source)
	position = source.position
	direction = bearing
	data = original.duplicate(true)
	data.damage = float(original.context.get("echo_damage", original.damage)) * 0.35
	data.push = 0.0
	data.strength = 0.0
	data.erase("skill")
	data.context = {"kind": "secondary", "step": int(original.context.step),
		"weapon": int(original.context.weapon), "base": float(original.context.base),
		"lifesteal": 0.0, "effects": [], "prepared": false, "cross": false,
		"rewarded": true, "hit_targets": [], "piercing": false, "source_id": source.get_instance_id()}

func _ready() -> void:
	add_to_group("delayed_attacks")

func _physics_process(delta: float) -> void:
	if get_parent().get("combat_frozen") == true or get_parent().get("mechanism_moving") == true: return
	var source = source_actor.get_ref()
	if not is_instance_valid(source) or source.health <= 0.0 or get_parent().combat_over:
		queue_free()
		return
	if not released:
		delay -= delta
		if delay <= 0.0:
			released = true
			visible_remaining = 0.16
			release(source)
	else:
		visible_remaining -= delta
		if visible_remaining <= 0.0: queue_free()
	queue_redraw()

func release(source) -> void:
	if data.shape == "arrow":
		var shared: Dictionary = {}
		var angles: Array = [-15, 0, 15] if int(data.context.step) == 2 else [0]
		for angle in angles:
			get_parent().fire_arrow(source, direction.rotated(deg_to_rad(float(angle))), data, shared, position)
		return
	for target in get_tree().get_nodes_in_group("enemies"):
		if target.health <= 0.0: continue
		var inside: bool = false
		var samples: Array = target.hit_samples(position) if target.has_method("hit_samples") else [target.position]
		for point in samples:
			var offset: Vector2 = point - position
			var geometry_hit: bool = false
			if data.shape == "thrust":
				geometry_hit = offset.dot(direction) >= 0.0 and offset.dot(direction) <= float(data.range) and absf(offset.cross(direction)) <= float(data.width) * 0.5
			else:
				geometry_hit = offset.length() <= float(data.range) and absf(wrapf(offset.angle() - direction.angle(), -PI, PI)) <= float(data.arc) * 0.5
			if geometry_hit and get_parent().clear_line(position, point):
				inside = true
				break
		if inside:
			target.take_hit(float(data.damage), 0.0, Vector2.ZERO, 0.0, data.context)
	# Terrain takes damage too, but it never grants combat procs or resource rewards.
	for terrain in get_parent().terrains:
		if terrain.destroyed or not terrain.destructible: continue
		var offset: Vector2 = terrain.position - position
		var inside: bool = offset.length() <= float(data.range) and absf(wrapf(offset.angle() - direction.angle(), -PI, PI)) <= float(data.arc) * 0.5
		if data.shape == "thrust": inside = offset.dot(direction) >= 0.0 and offset.dot(direction) <= float(data.range) and absf(offset.cross(direction)) <= float(data.width) * 0.5
		if inside and get_parent().clear_line(position, terrain.position, false, [terrain.get_rid()]):
			terrain.take_hit(float(data.damage))

func _draw() -> void:
	var color: Color = Color(0.67, 0.61, 0.95, 0.60 if released else 0.13)
	draw_circle(Vector2.ZERO, 15.0, Color(color, 0.2))
	draw_line(Vector2.ZERO, direction * 22.0, color, 3.0)
	if not released: return
	if data.shape == "thrust":
		draw_line(Vector2.ZERO, direction * float(data.range), color, maxf(2.0, float(data.width) * 0.5))
	elif data.shape != "arrow":
		draw_arc(Vector2.ZERO, float(data.range), direction.angle() - float(data.arc) * 0.5, direction.angle() + float(data.arc) * 0.5, 40, color, 3.0)
