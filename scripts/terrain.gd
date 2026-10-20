extends StaticBody2D
# Three independent map properties. ZERO means a solid obstacle.
@export var destructible := false
@export var ranged_pass := false
@export var pass_direction := Vector2.ZERO
@export var max_health := 70.0
var health := 70.0
var rect := Rect2()
var title := "STONE"
var destroyed := false
var reveals_secret := false
var move_body: StaticBody2D

func configure(data: Dictionary) -> void:
	rect = data.rect
	position = rect.get_center()
	destructible = data.get("destructible", false)
	ranged_pass = data.get("ranged_pass", false)
	pass_direction = data.get("pass_direction", Vector2.ZERO)
	title = data.get("title", "STONE")
	reveals_secret = data.get("reveals_secret", false)
	health = max_health

func _ready() -> void:
	# Separate movement and attack colliders: one-way affects bodies only.
	collision_layer = 16 | (0 if ranged_pass else 8)
	collision_mask = 0
	var attack_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = rect.size
	attack_shape.shape = rectangle
	add_child(attack_shape)
	move_body = StaticBody2D.new()
	move_body.collision_layer = 1
	move_body.collision_mask = 0
	var movement_shape := CollisionShape2D.new()
	var movement_rect := RectangleShape2D.new()
	movement_rect.size = rect.size
	movement_shape.shape = movement_rect
	if not pass_direction.is_zero_approx():
		# Godot's default one-way normal points UP; passage is UP.
		movement_shape.one_way_collision = true
		movement_shape.one_way_collision_margin = 4.0
		movement_shape.rotation = Vector2.UP.angle_to(pass_direction)
		if absf(pass_direction.x) > 0.5:
			movement_rect.size = Vector2(rect.size.y, rect.size.x)
	move_body.add_child(movement_shape)
	add_child(move_body)

func take_hit(damage: float, _strength: float = 0.0, _direction: Vector2 = Vector2.ZERO) -> void:
	if not destructible or destroyed:
		return
	health = maxf(0.0, health - damage)
	if health <= 0.0:
		destroyed = true
		set_deferred("collision_layer", 0)
		move_body.set_deferred("collision_layer", 0)
		get_parent().terrain_destroyed(self)
	queue_redraw()

func _draw() -> void:
	var local_rect := Rect2(-rect.size / 2.0, rect.size)
	if destroyed:
		# Floor remains traversable; small chips only, no collision.
		for i in range(4):
			draw_rect(Rect2(-rect.size / 3.0 + Vector2(i * 9, i % 2 * 14), Vector2(5, 4)), Color("746351"))
		return
	var color := Color("4b6070")
	if destructible:
		color = Color("9c704d")
	elif ranged_pass:
		color = Color("377f89")
	if not pass_direction.is_zero_approx():
		color = Color("9583c8")
	draw_rect(local_rect, color)
	draw_rect(local_rect, color.lightened(0.3), false, 2.0)
	if destructible:
		draw_line(local_rect.position, local_rect.end, Color("d7ab7b"), 2.0)
		draw_rect(Rect2(-rect.size.x / 2.0, -rect.size.y / 2.0 - 8, rect.size.x * health / max_health, 4), Color("edc996"))
	if not pass_direction.is_zero_approx():
		for x in [-30, 0, 30]:
			var at := Vector2(x, 0)
			draw_line(at - pass_direction * 8, at + pass_direction * 8, Color.WHITE, 2.0)
			draw_line(at + pass_direction * 8, at + pass_direction.rotated(2.4) * 6, Color.WHITE, 2.0)
			draw_line(at + pass_direction * 8, at + pass_direction.rotated(-2.4) * 6, Color.WHITE, 2.0)
	if rect.size.x >= 70:
		draw_string(ThemeDB.fallback_font, Vector2(-rect.size.x / 2 + 5, 4), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e6eaf0"))
