extends RefCounted
const Definition := preload("res://scripts/data/item_definition.gd")
var instance_id: String
var definition: Definition
var quantity: int = 1
var position: Vector2i = Vector2i(-1, -1)
var rotated: bool = false
var locked: bool = false
## Real mass reduction, deliberately separate from burden optimization.
var actual_weight_reduction: float = 0.0
func _init(item: Definition = null, count: int = 1, saved_id: String = "") -> void:
	definition = item
	instance_id = saved_id if not saved_id.is_empty() else str(ResourceUID.create_id())
	quantity = clampi(count, 1, maxi(1, item.max_stack)) if item != null else 1
func actual_weight() -> float:
	if definition == null or definition.weightless: return 0.0
	return maxf(0.0, definition.weight) * quantity * (1.0 - clampf(actual_weight_reduction, 0.0, 1.0))
func footprint() -> Vector2i:
	if definition == null: return Vector2i.ONE
	var size: Vector2i = definition.grid_size.max(Vector2i.ONE)
	return Vector2i(size.y, size.x) if rotated and definition.can_rotate else size
func to_record() -> Dictionary:
	return {"instance_id": instance_id, "definition_id": definition.id, "quantity": quantity,
		"grid_x": position.x, "grid_y": position.y, "rotated": rotated, "locked": locked,
		"actual_weight_reduction": actual_weight_reduction}
