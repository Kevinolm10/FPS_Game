extends Node
class_name HealthComponent

signal damaged(amount: int, new_health: int)
signal died

@export var max_health: int = 100
var health: int = 100

func _ready() -> void:
	health = max_health

func reset() -> void:
	health = max_health

@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int = 50) -> void:
	if not get_parent().is_multiplayer_authority():
		return
	if health <= 0:
		return

	health -= amount
	damaged.emit(amount, health)

	if health <= 0:
		died.emit()

func is_dead() -> bool:
	return health <= 0
