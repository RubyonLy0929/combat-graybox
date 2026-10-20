extends Node2D
const FONT := preload("res://assets/NotoSansSC.ttf")
var item
var gold: int = 0
var auto_disabled := false
var claimed := false
var show_label := false
var age := 0.0
var notified := false
func _ready() -> void:
	add_to_group("ground_loot")
	z_index = 1
func title() -> String:
	if gold > 0: return "%d 金币" % gold
	if item == null: return "空"
	return item.definition.display_name + (" ×%d" % item.quantity if item.quantity > 1 else "")
func _process(delta: float) -> void:
	age += delta
	queue_redraw()
func _draw() -> void:
	if claimed: return
	var bob := sin(age * 3.0) * 1.5
	var color := Color("eac778") if gold > 0 else Color("a2bbc1")
	if item != null:
		color = {"weapon": Color("9ad0df"), "armor": Color("b0cf93"), "backpack": Color("cfb68c"), "accessory": Color("d0ade4"), "material": Color("c1c7cc")}.get(item.definition.item_type, color)
	draw_set_transform(Vector2(0, 5), 0, Vector2(1, 0.4))
	draw_circle(Vector2.ZERO, 10, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2(0, bob))
	if gold > 0:
		draw_circle(Vector2.ZERO, 5, color)
		draw_circle(Vector2(5, -3), 4, color.lightened(0.2))
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(0,-9),Vector2(8,0),Vector2(0,9),Vector2(-8,0)]), color.darkened(0.5))
		draw_polyline(PackedVector2Array([Vector2(0,-9),Vector2(8,0),Vector2(0,9),Vector2(-8,0),Vector2(0,-9)]), color, 1.5)
	draw_set_transform(Vector2.ZERO)
	if show_label:
		var label := title()
		var width := FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_rect(Rect2(-width/2 - 4, -34, width + 8, 20), Color(0.04,0.08,0.10,0.9))
		draw_string(FONT, Vector2(-width/2, -19), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
