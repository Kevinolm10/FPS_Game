extends Node

# === Constants ===
const PORT = 7777
const MAX_CLIENTS = 10

# === State ===
var players: Dictionary = {}
var spawn_points: Array = []
var used_spawn_points: Array = []
var clients_ready: Dictionary = {}

func _ready():
	await get_tree().process_frame
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)

func register_spawn_points(points: Array):
	spawn_points = points

func get_spawn_position(_player_id: int) -> Vector3:
	if spawn_points.is_empty():
		return Vector3(0, 2, 0)
	var available = spawn_points.filter(func(p): return not used_spawn_points.has(p))
	if available.is_empty():
		used_spawn_points.clear()
		available = spawn_points.duplicate()
	available.shuffle()
	var point = available[0]
	used_spawn_points.append(point)
	return point.global_position

func server():
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(PORT, MAX_CLIENTS)
	multiplayer.multiplayer_peer = peer
	await get_tree().process_frame
	_spawn_player_for_all(multiplayer.get_unique_id())

func client(ip: String):
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, PORT)
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)

func _on_connected_to_server():
	_request_spawn.rpc_id(1)

func _on_player_connected(player_id: int):
	if not multiplayer.is_server():
		return
	_spawn_player_for_all(player_id)

func _on_player_disconnected(player_id: int):
	if not multiplayer.is_server():
		return
	if players.has(player_id):
		var p = players[player_id]
		if is_instance_valid(p):
			p.queue_free()
		players.erase(player_id)
	clients_ready.erase(player_id)
	_remove_player.rpc(player_id)

@rpc("any_peer", "reliable")
func _request_spawn():
	if not multiplayer.is_server():
		return
	var id = multiplayer.get_remote_sender_id()
	_spawn_player_for_all(id)

# Plain function — never an RPC — server only
func _spawn_player_for_all(player_id: int):
	if not multiplayer.is_server():
		return

	# Spawn the new player on everyone
	_spawn_player.rpc(player_id)

	# Wait for the spawn to complete before syncing existing players
	await get_tree().create_timer(0.5).timeout

	# Now sync existing players to the new player
	for existing_id in players.keys():
		if existing_id != player_id:
			_spawn_player.rpc_id(player_id, existing_id)

@rpc("any_peer", "call_local", "reliable")
func _spawn_player(player_id: int):
	if players.has(player_id):
		return
	await get_tree().process_frame
	var player = preload("res://player.tscn").instantiate()
	player.name = str(player_id)
	player.id = player_id
	player.set_multiplayer_authority(player_id)
	player.scale = Vector3(0.065, 0.065, 0.065)
	get_tree().current_scene.add_child(player)
	players[player_id] = player
	player.global_position = get_spawn_position(player_id)
	await get_tree().process_frame
	if is_instance_valid(player):
		player.activate()

@rpc("any_peer", "reliable")
func _remove_player(player_id: int):
	if players.has(player_id):
		var p = players[player_id]
		if is_instance_valid(p):
			p.queue_free()
		players.erase(player_id)

@rpc("any_peer", "call_local", "reliable")
func request_respawn(player_id: int):
	if not multiplayer.is_server():
		return

	# Clean up old instance
	if players.has(player_id):
		var old = players[player_id]
		if is_instance_valid(old):
			old.queue_free()
		players.erase(player_id)

	await get_tree().create_timer(0.3).timeout

	if not get_tree():
		return

	# If no other clients, just spawn directly
	if multiplayer.get_peers().is_empty():
		_spawn_player_for_all(player_id)
		return

	# Tell all peers to get ready for the respawn
	notify_respawn_ready.rpc(player_id)

@rpc("authority", "call_local", "reliable")
func notify_respawn_ready(player_id: int):
	if multiplayer.is_server():
		# Server marks itself ready immediately
		_handle_respawn_ready(player_id, 1)
	else:
		# Client confirms it's ready for this respawn
		confirm_respawn_ready.rpc_id(1, player_id)

@rpc("any_peer", "reliable")
func confirm_respawn_ready(player_id: int):
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	_handle_respawn_ready(player_id, sender)

var respawn_ready: Dictionary = {}

func _handle_respawn_ready(player_id: int, peer_id: int):
	if not respawn_ready.has(player_id):
		respawn_ready[player_id] = {}
	respawn_ready[player_id][peer_id] = true

	var all_peers = Array(multiplayer.get_peers())
	all_peers.append(1)  # include server

	var all_ready = true
	for peer in all_peers:
		if not respawn_ready[player_id].has(peer):
			all_ready = false
			break

	if all_ready:
		respawn_ready.erase(player_id)
		_spawn_player_for_all(player_id)

@rpc("authority", "call_local", "reliable")
func change_scene(path: String) -> void:
	clients_ready.clear()
	get_tree().change_scene_to_file(path)

@rpc("any_peer", "reliable")
func client_ready_in_scene():
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	clients_ready[sender] = true
	print("Client ready: ", sender, " | Total ready: ", clients_ready.size())
	var all_ready = true
	for peer_id in multiplayer.get_peers():
		if not clients_ready.has(peer_id):
			all_ready = false
			break
	if all_ready:
		print("All clients ready, spawning players...")
		clients_ready.clear()
		_respawn_all_players()

func _respawn_all_players():
	for player_id in players.keys():
		var old = players[player_id]
		if is_instance_valid(old):
			old.queue_free()
	players.clear()
	used_spawn_points.clear()
	await get_tree().process_frame
	var all_players = Array(multiplayer.get_peers())
	all_players.append(multiplayer.get_unique_id())
	for player_id in all_players:
		_spawn_player_for_all(player_id)
