# bullet.gd
extends Node3D
var speed = 50.0
var target: Vector3
var traveling = false

func launch(from: Vector3, to_direction: Vector3):
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, from + to_direction.normalized() * 1000)
	var result = space_state.intersect_ray(query)
	
	target = result.position if result else from + to_direction.normalized() * 1000
	global_position = from
	traveling = true
	look_at(target)
	
	if result:
		if result.collider.is_in_group("dummy"):
			result.collider.take_damage.rpc(10)

func _process(delta):
	if not traveling:
		return
	look_at(target)
	global_position = global_position.move_toward(target, speed * delta)
	if global_position.is_equal_approx(target):
		queue_free()
