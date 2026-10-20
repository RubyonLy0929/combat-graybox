extends Node2D
var source_actor
var direction:=Vector2.RIGHT
var remaining:=390.0
var damage:=23.0
var strength:=10.0
var fraction:=.1
var from_player:=true
var shared_hits: Dictionary={}
var attack_data: Dictionary = {}
var pierced: int = 0
var excluded: Array[RID] = []
const SPEED:=680.0
func _ready() -> void: add_to_group("arrows")
func _physics_process(delta: float) -> void:
	if get_parent().get("combat_frozen") == true or get_parent().get("mechanism_moving") == true: return
	if get_parent().combat_over:
		queue_free()
		return
	var travel:=minf(SPEED*delta,remaining)
	var next:=position+direction*travel
	var query:=PhysicsRayQueryParameters2D.create(position,next,8 | (4 if from_player else 2))
	query.exclude = excluded
	query.hit_from_inside=true
	var hit:=get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var obj=hit.collider
		if obj.has_method("take_hit") and not shared_hits.has(obj.get_instance_id()):
			shared_hits[obj.get_instance_id()]=true
			if obj is CharacterBody2D:
				if is_instance_valid(source_actor) and source_actor.health > 0.0:
					source_actor.deal_hit(obj, attack_data, direction)
				else:
					obj.take_hit(damage, strength, direction, fraction, {"kind": "secondary"})
				pierced += 1
				if attack_data.get("context", {}).get("piercing", false) and pierced < 2:
					excluded.append(obj.get_rid())
					position = hit.position + direction * 0.1
					remaining -= travel
					queue_redraw()
					return
			else: obj.take_hit(damage,strength,direction)
		queue_free()
		return
	position=next
	remaining-=travel
	if remaining<=0: queue_free()
func _draw() -> void:
	draw_line(-direction*17,direction*3,Color("e6e4c9"),2)
	draw_line(direction*3,-direction*4+direction.orthogonal()*4,Color("e6e4c9"),2)
	draw_line(direction*3,-direction*4-direction.orthogonal()*4,Color("e6e4c9"),2)
