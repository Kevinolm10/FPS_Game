extends Node3D

func _ready() -> void:
	var points = $SpawnPoints.get_children()
	NetworkManager.register_spawn_points(points)
	print("Game area spawn points registered: ", points.size())

	if multiplayer.is_server():
		# Server spawns immediately if no clients connected
		if multiplayer.get_peers().is_empty():
			NetworkManager._respawn_all_players()
	else:
		# Tell server this client is ready
		NetworkManager.client_ready_in_scene.rpc_id(1)

		for player_id in NetworkManager.players.keys():
			var old = NetworkManager.players[player_id]
			if is_instance_valid(old):
				old.queue_free()
			NetworkManager.players.erase(player_id)

		await get_tree().process_frame

		var all_players = Array(multiplayer.get_peers())
		all_players.append(multiplayer.get_unique_id())

		for player_id in all_players:
			NetworkManager._spawn_player_for_all(player_id)
