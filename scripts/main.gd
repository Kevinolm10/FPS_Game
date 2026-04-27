extends Node3D

func _ready():
	print("hello world from main.gd")
	var role := "SERVER" if multiplayer.is_server() else "CLIENT"
	print("[Lobby][", role, " id=", multiplayer.get_unique_id(), "] Loaded main.tscn")

	if not multiplayer.has_multiplayer_peer():
		print("[Lobby] No multiplayer peer active. Staying as local scene only")
		return

	var points = $SpawnPoints.get_children()
	NetworkManager.register_spawn_points(points)
	print("[Lobby] Spawn points registered count=", points.size())

	if multiplayer.is_server():
		var host_id := multiplayer.get_unique_id()
		if not NetworkManager.players.has(host_id):
			print("[Lobby][SERVER] Spawning host player id=", host_id)
			NetworkManager._spawn_player_on_all(host_id, NetworkManager.get_spawn_position())

		for peer_id in multiplayer.get_peers():
			if not NetworkManager.players.has(peer_id):
				print("[Lobby][SERVER] Spawning missing connected peer id=", peer_id)
				NetworkManager._spawn_player_on_all(peer_id, NetworkManager.get_spawn_position())
	else:
		print("[Lobby][CLIENT] Requesting lobby spawn from server")
		NetworkManager.request_lobby_spawn.rpc_id(1)
