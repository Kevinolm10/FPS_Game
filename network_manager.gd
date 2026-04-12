extends Node

const PORT = 7777
const MAX_CLIENTS = 10
var players = {}
var spawn_points = []
var used_spawn_points = []

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)

func register_spawn_points(points: Array):
	spawn_points = points

func get_spawn_position(id: int) -> Vector3:
	if spawn_points.is_empty():
		print("No spawn points registered, spawning at default position")
		return Vector3(0, 2, 0)
	var available = spawn_points.filter(func(p): return not used_spawn_points.has(p))
	if available.is_empty():
		used_spawn_points.clear()
		available = spawn_points
	var point = available[randi() % available.size()]
	used_spawn_points.append(point)
	print("Player ", id, " spawned at: ", point.name, " position: ", point.global_position)
	return point.global_position

func server():
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(PORT, MAX_CLIENTS)
	multiplayer.multiplayer_peer = peer
	print("Server started, ID: ", multiplayer.get_unique_id())

func _spawn_host():
	spawn_player.rpc(multiplayer.get_unique_id())

func client(ip: String = "127.0.0.1"):
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, PORT)
	multiplayer.multiplayer_peer = peer
	print("Connecting to: ", ip)

func _on_player_connected(id):
	print("Player connected: ", id)
	spawn_player.rpc(id)

func _on_player_disconnected(id):
	print("Player disconnected: ", id)
	if players.has(id):
		players[id].queue_free()
		players.erase(id)

@rpc("call_local", "reliable")
func spawn_player(id):
	if players.has(id):
		return
	var player = preload("res://main_character.tscn").instantiate()
	player.name = str(id)
	player.set_multiplayer_authority(id)
	player.scale = Vector3(0.065, 0.065, 0.065)
	add_child(player)
	player.global_position = get_spawn_position(id)
	players[id] = player
	print("Spawned player: ", id)
	print("Total players: ", players.size())
