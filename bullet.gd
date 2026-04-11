extends CharacterBody3D

var bullet_speed = 10
var direction: Vector3 = Vector3.ZERO
var active = false


func launch(from: Vector3, to_direction: Vector3):
	global_position = from
	direction = to_direction.normalized()
	active = true
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING

func _physics_process(delta):
	if not active:
		return
	
	velocity = direction * bullet_speed
	var collision = move_and_collide(velocity * delta)
	
	if collision:
		print("Hit: ", collision.get_collider().name)
		queue_free()
