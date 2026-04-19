extends Node3D

func _ready():
	var points = $SpawnPoints.get_children()
	NetworkManager.register_spawn_points(points)

	if not multiplayer.has_multiplayer_peer():
		return

	if multiplayer.is_server():
		pass # server handles spawning
	else:
		await multiplayer.connected_to_server


func _process(delta: float) -> void:
		var local_player = NetworkManager.players.get(multiplayer.get_unique_id())
