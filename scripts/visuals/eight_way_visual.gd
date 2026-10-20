extends AnimatedSprite2D
## Generated placeholder SpriteFrames. Replace these animations with authored art later.
## e,se,s,sw,w,nw,n,ne; hit tests keep their continuous world-space direction.
const DIRECTIONS := ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const FRAME_COUNTS := {"idle": 2, "walk": 6, "windup": 3, "attack": 4, "recovery": 3, "hit": 2, "death": 1}
static var cached: SpriteFrames
var pose_name := "idle_e"
func _ready() -> void:
	if cached == null: cached = build_frames()
	sprite_frames = cached
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	play("idle_e")
func set_pose(actor) -> void:
	if sprite_frames == null: return
	var direction: Vector2 = actor.facing if actor.phase == "idle" else actor.attack_facing
	var octant := posmod(int(round(direction.angle() / (PI / 4.0))), 8)
	var state := "idle"
	if actor.health <= 0.0: state = "death"
	elif actor.stagger > 0.0: state = "hit"
	elif actor.phase == "transition": state = "walk" if actor.velocity.length() > 1.0 else "idle"
	elif actor.phase != "idle": state = "attack" if actor.phase == "active" else actor.phase
	elif actor.velocity.length() > 1.0: state = "walk"
	pose_name = state + "_" + DIRECTIONS[octant]
	if animation != StringName(pose_name): play(pose_name)
	if state in ["windup", "attack", "recovery"]:
		var phase_key: String = "active" if state == "attack" else state
		var duration: float = maxf(0.001, float(actor.attack_data.get(phase_key, 0.1)))
		var progress := clampf(1.0 - actor.phase_remaining / duration, 0.0, 1.0)
		pause()
		frame = mini(int(progress * int(FRAME_COUNTS[state])), int(FRAME_COUNTS[state]) - 1)
	elif state == "death":
		pause()
		frame = 0
	else:
		if not is_playing(): play(pose_name)
		speed_scale = clampf(actor.velocity.length() / 180.0, 0.5, 1.8) if state == "walk" else 1.0
	var tint := Color("63d9ca") if actor.is_player else Color("dc8471")
	if actor.ranged_enemy: tint = Color("b49aca")
	if actor.rank > 0: tint = Color("dfb374")
	if actor.dummy: tint = Color("a2a7a2")
	modulate = Color.WHITE if actor.flash > 0.0 else tint
	scale = Vector2.ONE * (1.18 if actor.rank == 2 else 1.0)
static func build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for state in FRAME_COUNTS:
		for octant in range(8):
			var name: String = state + "_" + DIRECTIONS[octant]
			frames.add_animation(name)
			frames.set_animation_loop(name, state in ["walk", "idle", "hit"])
			frames.set_animation_speed(name, 10.0 if state == "walk" else 6.0)
			for index in range(int(FRAME_COUNTS[state])):
				frames.add_frame(name, ImageTexture.create_from_image(make_image(state, octant, index)))
	return frames
static func make_image(state: String, octant: int, index: int) -> Image:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var forward := Vector2.from_angle(octant * PI / 4.0)
	var side := forward.orthogonal()
	var centre := Vector2(32, 34)
	if state == "death":
		ellipse(image, centre + Vector2(0, 7), Vector2(15, 6), Color("535e65"))
		ellipse(image, centre + Vector2(12, 4), Vector2(6, 5), Color("8f979b"))
		return image
	var walk := sin(float(index) / 6.0 * TAU) * 4.0 if state == "walk" else 0.0
	var bob := absf(walk) * 0.25 if state == "walk" else float(index % 2) * 0.5
	var lunge := Vector2.ZERO
	if state == "windup": lunge = -forward * float(index)
	if state == "attack": lunge = forward * (3.0 + sin(float(index) / 3.0 * PI) * 3.0)
	if state == "recovery": lunge = forward * float(2 - index)
	if state == "hit": lunge = -forward * 3.0
	centre += lunge + Vector2(0, -bob)
	var foot_a := centre + side * 7.0 + forward * walk + Vector2(0, 12)
	var foot_b := centre - side * 7.0 - forward * walk + Vector2(0, 12)
	capsule(image, centre + side * 5.0 + Vector2(0, 6), foot_a, 4.0, Color("35414b"))
	capsule(image, centre - side * 5.0 + Vector2(0, 6), foot_b, 4.0, Color("35414b"))
	ellipse(image, foot_a, Vector2(5, 3), Color("26323b"))
	ellipse(image, foot_b, Vector2(5, 3), Color("26323b"))
	ellipse(image, centre, Vector2(13, 11), Color("a3adb6"))
	ellipse(image, centre - forward * 3.0, Vector2(10, 8), Color("727f8c"))
	var reach := 0.0
	if state == "attack": reach = 8.0
	if state == "windup": reach = -3.0
	var shoulder_a := centre + side * 10.0
	var shoulder_b := centre - side * 10.0
	capsule(image, shoulder_a, shoulder_a + forward * (7.0 + reach), 3.0, Color("dae0df"))
	capsule(image, shoulder_b, shoulder_b + forward * 5.0, 3.0, Color("c4cdce"))
	var head := centre + Vector2(0, -15)
	ellipse(image, head, Vector2(8, 8), Color("e8e0d0"))
	ellipse(image, head - forward * 3.0 + Vector2(0, -2), Vector2(8, 5), Color("455260"))
	# Explicit side/back/front variants; the eye and nose follow the eight-way bearing.
	if forward.y > -0.4:
		ellipse(image, head + forward * 5.0 + side * 2.5, Vector2(1, 1.5), Color("18242d"))
		if absf(forward.x) < 0.9: ellipse(image, head + forward * 5.0 - side * 2.5, Vector2(1, 1.5), Color("18242d"))
		ellipse(image, head + forward * 8.0, Vector2(2, 2), Color("c1bbae"))
	else:
		capsule(image, head + Vector2(-5, 2), head + Vector2(5, 2), 2.0, Color("313e4a"))
	return image
static func ellipse(image: Image, centre: Vector2, radius: Vector2, color: Color) -> void:
	for y in range(maxi(0, int(floor(centre.y - radius.y))), mini(64, int(ceil(centre.y + radius.y)) + 1)):
		for x in range(maxi(0, int(floor(centre.x - radius.x))), mini(64, int(ceil(centre.x + radius.x)) + 1)):
			var offset := (Vector2(x, y) - centre) / radius
			if offset.length_squared() <= 1.0: image.set_pixel(x, y, color)
static func capsule(image: Image, from: Vector2, to: Vector2, width: float, color: Color) -> void:
	var distance := from.distance_to(to)
	for i in range(maxi(1, int(distance) + 1)):
		ellipse(image, from.lerp(to, float(i) / maxf(1.0, distance)), Vector2.ONE * width, color)
