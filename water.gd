extends StaticBody3D

@onready var water = $Area3D

func _ready() -> void:
	water.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D):
	# Only the server (or the player's own machine) should trigger death,
	# and only if the body is the multiplayer authority on this machine.
	# Death replication is driven by NetworkManager.eliminate_player.
	if body is CharacterBody3D and body.has_method("die"):
		if not body.is_dead and body.is_multiplayer_authority():
			body.die()
			print("player dead: ", body.name)
