extends RefCounted
const MOVE_SPEED := 200.0
const BODY_RADIUS := 18.0
const PUSH_DURATION := .16
static func cardinal(direction: Vector2, previous: Vector2 = Vector2.DOWN) -> Vector2:
	if direction.is_zero_approx(): return previous
	if is_equal_approx(absf(direction.x), absf(direction.y)) and previous.dot(direction) > 0.0: return previous
	if absf(direction.x) > absf(direction.y): return Vector2.RIGHT if direction.x > 0 else Vector2.LEFT
	return Vector2.DOWN if direction.y > 0 else Vector2.UP
static func push_distance(body_width: float, fraction: float, strength: float, damage_ratio: float, weight: float, armor: String) -> float:
	var armor_factor: float = {"cloth":1.15,"light":1.0,"heavy":.65}.get(armor,1.0)
	var impulse := -log(1.0-clampf(fraction,0,.99))
	impulse *= (.7 + .2 * maxf(0,strength)/10.0 + .1 * clampf(damage_ratio,0,3)) * armor_factor / (1.0 + maxf(0,weight)/50.0)
	return body_width * (1.0-exp(-impulse))
