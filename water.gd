extends StaticBody3D

@onready var water = $Area3D

func _ready() -> void:
	water.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D):
	if body is CharacterBody3D and body.has_method("die"):
		if not body.is_dead:
			body.die.rpc()
			print("player dead: ", body.name)

func _process(delta: float) -> void:
	pass
