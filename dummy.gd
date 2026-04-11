extends CharacterBody3D

var health = 100
var is_dead = false
var spawn_point: Vector3

@onready var player = get_tree().get_first_node_in_group("player")

func take_damage(amount: int):
	health -= amount
	print("Dummy health: ", health)
	if health <= 0:
		is_dead = true
		print("Dummy dead!")
		respawn()

func respawn():
	health = 100
	is_dead = false
	visible = false
	$CollisionShape3D.disabled = true
	await get_tree().create_timer(5.0).timeout
	global_position = spawn_point
	visible = true
	$CollisionShape3D.disabled = false
	print("Dummy respawned!")

func _ready():
	spawn_point = global_position
