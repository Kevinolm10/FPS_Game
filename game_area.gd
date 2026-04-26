extends Node3D

func _ready() -> void:
	var role := "SERVER" if multiplayer.is_server() else "CLIENT"
	print("[GameArea][", role, " id=", multiplayer.get_unique_id(), "] Loaded game_area.tscn")

	var spectate_camera := $SpectateCamera/Camera3D as Camera3D
	if spectate_camera != null:
		spectate_camera.current = false
		print("[GameArea] Spectate camera reset to current=false")

	var points = $SpawnPoints.get_children()
	NetworkManager.register_spawn_points(points)
	print("[GameArea] Spawn points registered count=", points.size())

	if multiplayer.is_server():
		# If no clients have connected yet, spawn everyone now
		if multiplayer.get_peers().is_empty():
			print("[GameArea][SERVER] No peers connected. Spawning all players immediately")
			NetworkManager._spawn_all_players()
		# Otherwise wait for all clients to report ready (handled by client_ready_in_scene)
		else:
			print("[GameArea][SERVER] Waiting for clients to report ready: ", multiplayer.get_peers())
	else:
		# Tell the server this client has loaded the scene.
		# The server will call _spawn_all_players once everyone is ready.
		# Do NOT manually spawn here — the server drives all spawning via _spawn_player RPC.
		print("[GameArea][CLIENT] Reporting ready to server")
		NetworkManager.client_ready_in_scene.rpc_id(1)
