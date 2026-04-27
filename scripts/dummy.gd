extends CharacterBody3D
var health = 100
var max_health = 100
var is_dead = false
var spawn_point: Vector3

func take_damage(amount: int):
	if is_dead:
		return
	health -= amount
	print("Dummy health: ", health)
	if health <= 0:
		die()

func die():
	is_dead = true
	print("Dummy dead!")
	visible = false
	$CollisionShape3D.disabled = true
	await get_tree().create_timer(5.0).timeout
	respawn()

func respawn():
	health = max_health
	is_dead = false
	global_position = spawn_point
	visible = true
	$CollisionShape3D.disabled = false
	print("Dummy respawned!")

func _ready():
	spawn_point = global_position
