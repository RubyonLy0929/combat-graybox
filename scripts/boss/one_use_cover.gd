extends "res://scripts/terrain.gd"
## Cover is consumed by an explicit boss event, never by ordinary player damage.
var pair_index: int = 0
var highlighted: bool = false
var protected_this_cast: bool = false

func take_hit(_damage: float, _strength: float = 0.0, _direction: Vector2 = Vector2.ZERO) -> void:
	pass

func consume() -> void:
	if destroyed: return
	destroyed = true
	highlighted = false
	set_deferred("collision_layer", 0)
	move_body.set_deferred("collision_layer", 0)
	get_parent().terrain_destroyed(self)
	queue_redraw()

func _draw() -> void:
	var box: Rect2 = Rect2(-rect.size * 0.5, rect.size)
	if destroyed:
		for i in range(7):
			draw_rect(Rect2(Vector2(-30 + i * 10, (i % 3) * 4 - 5), Vector2(7, 5)), Color("5b5750"))
		return
	draw_rect(box, Color("69717a"))
	draw_rect(box, Color("d8d4b8") if highlighted else Color("969b97"), false, 3.0)
	for i in range(3):
		draw_line(Vector2(-27 + i * 27, -12), Vector2(-27 + i * 27, 12), Color("384752"), 2.0)
	draw_string(preload("res://assets/NotoSansSC.ttf"), Vector2(-28, 5), "一次掩体", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e8e2c8"))
	if highlighted:
		draw_line(Vector2(-32, 24), Vector2(32, 24), Color("8fdec1"), 3.0)
