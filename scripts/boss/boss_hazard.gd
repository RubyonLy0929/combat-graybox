extends Node2D
## Telegraph and damage share geometry. Each hazard can hurt the player once.
var kind: String = "circle"
var delay: float = 1.0
var duration: float = 0.18
var telegraph_time: float = INF
var elapsed: float = 0.0
var damage: float = 28.0
var push: float = 0.15
var radius: float = 55.0
var inner_radius: float = 0.0
var direction: Vector2 = Vector2.DOWN
var reach: float = 220.0
var width: float = 36.0
var arc: float = PI * 0.6
var speed: float = 180.0
var distance_left: float = 900.0
var blocked_by_cover: bool = false
var hit_done: bool = false
var number: int = 0
var attack_name: String = "炮击"
var attack_group: String = ""

func configure(values: Dictionary) -> void:
	for key in values:
		set(key, values[key])

func _ready() -> void:
	add_to_group("boss_hazards")
	z_index = 3

func _physics_process(delta: float) -> void:
	var room = get_parent()
	if room.combat_frozen or room.mechanism_moving or room.freeze_ai: return
	if room.combat_over or room.finished:
		queue_free()
		return
	if room.marathon_active: delta *= room.marathon.time_scale()
	var previous: float = elapsed
	elapsed += delta
	if kind == "projectile":
		move_projectile(delta)
	elif elapsed >= delay:
		if not hit_done and contains(room.player.position, room.player.radius):
			var cover = room.cover_between(position, room.player.position) if blocked_by_cover else null
			if cover == null:
				hit_done = true
				room.hurt_player(damage, (room.player.position - position).normalized(), push, attack_group)
		if previous < delay:
			room.impact_flash = 0.10
		if elapsed >= delay + duration: queue_free()
	queue_redraw()

func contains(point: Vector2, body_radius: float) -> bool:
	var offset: Vector2 = point - position
	if kind == "circle": return offset.length() <= radius + body_radius
	if kind == "donut": return offset.length() >= inner_radius - body_radius and offset.length() <= radius + body_radius
	if kind == "line":
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, position, position + direction * reach)
		return point.distance_to(closest) <= width * 0.5 + body_radius
	if kind == "sector":
		if offset.length() > reach + body_radius: return false
		var allowance: float = asin(clampf(body_radius / maxf(body_radius, offset.length()), 0.0, 1.0))
		return absf(wrapf(offset.angle() - direction.angle(), -PI, PI)) <= arc * 0.5 + allowance
	return false

func move_projectile(delta: float) -> void:
	var room = get_parent()
	var from: Vector2 = position
	var travel: float = minf(distance_left, speed * delta)
	var to: Vector2 = from + direction * travel
	var closest: Vector2 = Geometry2D.get_closest_point_to_segment(room.player.position, from, to)
	var query = PhysicsRayQueryParameters2D.create(from, to, 8)
	query.hit_from_inside = true
	var obstruction: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	var player_distance: float = from.distance_to(closest)
	var meets_player: bool = closest.distance_to(room.player.position) <= radius + room.player.radius
	if not obstruction.is_empty() and (not meets_player or from.distance_to(obstruction.position) <= player_distance):
		queue_free()
		return
	if meets_player and not hit_done:
		hit_done = true
		room.hurt_player(damage, direction, push)
		queue_free()
		return
	position = to
	distance_left -= travel
	if distance_left <= 0.0: queue_free()

func _draw() -> void:
	if elapsed < delay - telegraph_time: return
	if kind == "projectile":
		draw_circle(Vector2.ZERO, radius, Color("f3b96a"))
		draw_line(-direction * 25.0, Vector2.ZERO, Color("c76e58"), 5.0)
		return
	var active: bool = elapsed >= delay
	var tint: Color = Color(1.0, 0.39, 0.25, 0.48 if active else 0.16)
	var border: Color = Color("ffc88a") if active else Color("da8c76")
	if kind == "circle":
		draw_circle(Vector2.ZERO, radius, tint)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, border, 2.0)
		draw_arc(Vector2.ZERO, radius - 6.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(elapsed / maxf(delay, 0.01), 0.0, 1.0), 40, border, 3.0)
		if number > 0:
			draw_string(preload("res://assets/NotoSansSC.ttf"), Vector2(-7, 7), str(number), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("fff0d1"))
		if not active:
			draw_circle(Vector2(0, -80 * (1.0 - clampf(elapsed / maxf(delay, 0.01), 0.0, 1.0))), 7, Color("e6b17b"))
	elif kind == "donut":
		for i in range(64):
			var a: Vector2 = Vector2.from_angle(float(i) * TAU / 64.0)
			var b: Vector2 = Vector2.from_angle(float(i + 1) * TAU / 64.0)
			draw_colored_polygon(PackedVector2Array([a * inner_radius, a * radius, b * radius, b * inner_radius]), tint)
		draw_arc(Vector2.ZERO, inner_radius, 0.0, TAU, 64, border, 3.0)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, border, 2.0)
	elif kind == "line":
		var side: Vector2 = direction.orthogonal() * width * 0.5
		draw_colored_polygon(PackedVector2Array([side, -side, direction * reach - side, direction * reach + side]), tint)
		draw_line(side, direction * reach + side, border, 2.0)
		draw_line(-side, direction * reach - side, border, 2.0)
	else:
		var points = PackedVector2Array([Vector2.ZERO])
		for i in range(37): points.append(direction.rotated(-arc * 0.5 + arc * float(i) / 36.0) * reach)
		draw_colored_polygon(points, tint)
		draw_arc(Vector2.ZERO, reach, direction.angle() - arc * 0.5, direction.angle() + arc * 0.5, 36, border, 2.0)
