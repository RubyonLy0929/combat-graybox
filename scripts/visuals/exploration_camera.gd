extends Camera2D
## Small centered dead zone. A one-screen map remains fully visible.
var target_actor: Node2D
var map_bounds: Rect2 = Rect2(0, 0, 1280, 720)
var dead_zone: Vector2 = Vector2(128, 54)

func _ready() -> void:
	position = map_bounds.get_center()
	position_smoothing_enabled = false

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target_actor): return
	var destination: Vector2 = position
	var offset: Vector2 = target_actor.global_position - position
	if absf(offset.x) > dead_zone.x: destination.x += offset.x - signf(offset.x) * dead_zone.x
	if absf(offset.y) > dead_zone.y: destination.y += offset.y - signf(offset.y) * dead_zone.y
	var half: Vector2 = Vector2(640, 360)
	for axis in range(2):
		if map_bounds.size[axis] <= half[axis] * 2.0:
			destination[axis] = map_bounds.get_center()[axis]
		else:
			destination[axis] = clampf(destination[axis], map_bounds.position[axis] + half[axis], map_bounds.end[axis] - half[axis])
	position = position.lerp(destination, 1.0 - exp(-12.0 * delta))
