extends Node

const PORT := 7777
const MAX_CLIENTS := 10
const PLAYER_SCENE := preload("res://mplayer.tscn")

var players: Dictionary = {}
var spawn_points: Array = []
var used_spawn_points: Array = []
var ready_clients: Dictionary = {}
var round_transition_in_progress := false
var scene_transition_in_progress := false
var waiting_spectators: Dictionary = {}
var pending_scene_path := ""

func _dbg(message: String):
	var scene_path := "<none>"
	if get_tree().current_scene != null:
		scene_path = get_tree().current_scene.scene_file_path
	var role := "SERVER" if multiplayer.is_server() else "CLIENT"
	print("[NetworkManager][", role, " id=", multiplayer.get_unique_id(), " scene=", scene_path, "] ", message)


	

func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	_dbg("Ready. Connected/disconnected signals bound")

# === Spawn points ===
func register_spawn_points(points: Array):
	spawn_points = points
	_dbg("Registered spawn points count=" + str(points.size()))

func get_spawn_position() -> Vector3:
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

# === Server / Client ===
func server():
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(PORT, MAX_CLIENTS)
	multiplayer.multiplayer_peer = peer
	_dbg("Server started on port=" + str(PORT) + " max_clients=" + str(MAX_CLIENTS))

func client(ip: String):
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, PORT)
	multiplayer.multiplayer_peer = peer
	_dbg("Connecting to host=" + ip + ":" + str(PORT))

# === Connections ===
func _on_player_connected(id: int):
	if not multiplayer.is_server():
		return

	_dbg("Peer connected id=" + str(id) + " peers_now=" + str(multiplayer.get_peers()))

	# Do not spawn players while in lobby/menu scenes.
	var current_scene := get_tree().current_scene
	if current_scene == null:
		_dbg("Skipping immediate spawn for peer " + str(id) + " because current_scene is null")
		return

	# Late joiners during an active round should spectate until the next lobby/round.
	if current_scene.scene_file_path == "res://game_area.tscn":
		waiting_spectators[id] = true
		_dbg("Peer " + str(id) + " joined mid-round. Marked as waiting spectator")
		change_scene.rpc_id(id, "res://game_area.tscn")
		return

	if current_scene.scene_file_path != "res://game_area.tscn" and current_scene.scene_file_path != "res://main.tscn":
		_dbg("Skipping immediate spawn for peer " + str(id) + " because scene is neither lobby nor game_area: " + current_scene.scene_file_path)
		return

	# spawn new player on all
	_spawn_player_on_all(id, get_spawn_position())

	# sync existing players to new client
	for existing_id in players.keys():
		if existing_id == id:
			continue
		var existing_player = players[existing_id]
		if is_instance_valid(existing_player):
			_spawn_player.rpc_id(id, existing_id, existing_player.global_position)
	_dbg("Synced existing players to new peer id=" + str(id) + " existing_count=" + str(players.size()))

@rpc("any_peer", "reliable")
func request_lobby_spawn():
	if not multiplayer.is_server():
		return

	var current_scene := get_tree().current_scene
	if current_scene == null or current_scene.scene_file_path != "res://main.tscn":
		_dbg("request_lobby_spawn ignored because current scene is not lobby")
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		_dbg("request_lobby_spawn ignored because sender_id=0")
		return

	if not players.has(sender_id):
		_dbg("request_lobby_spawn spawning missing lobby player sender_id=" + str(sender_id))
		_spawn_player_on_all(sender_id, get_spawn_position())
	else:
		# During scene transitions, a client can miss its own spawn RPC while
		# current_scene is still null. Re-send explicit self-spawn to recover.
		var sender_player = players[sender_id]
		if is_instance_valid(sender_player):
			_spawn_player.rpc_id(sender_id, sender_id, sender_player.global_position)
			_dbg("request_lobby_spawn re-sent self spawn for sender_id=" + str(sender_id))

	for existing_id in players.keys():
		if existing_id == sender_id:
			continue
		var existing_player = players[existing_id]
		if is_instance_valid(existing_player):
			_spawn_player.rpc_id(sender_id, existing_id, existing_player.global_position)

	_dbg("request_lobby_spawn complete sender_id=" + str(sender_id) + " players=" + str(players.keys()))

func _on_player_disconnected(id: int):
	_dbg("Peer disconnected id=" + str(id))

	if multiplayer.is_server():
		_remove_player_on_all(id)
		ready_clients.erase(id)
		waiting_spectators.erase(id)
		return

	# Client-side fallback: if the host disconnects, immediately return to lobby.
	if id == 1:
		_dbg("Host disconnected. Returning client to lobby and clearing local match state")
		_clear_players_registry()
		used_spawn_points.clear()
		ready_clients.clear()
		if multiplayer.has_multiplayer_peer():
			multiplayer.multiplayer_peer = null
		if get_tree().current_scene != null and get_tree().current_scene.scene_file_path != "res://main.tscn":
			get_tree().change_scene_to_file("res://main.tscn")

# === Spawn ===
@rpc("authority", "call_local", "reliable")
func _spawn_player(id: int, spawn_position: Vector3):
	if players.has(id):
		_dbg("_spawn_player ignored id=" + str(id) + " because player already exists")
		return
	if get_tree().current_scene == null:
		_dbg("_spawn_player ignored id=" + str(id) + " because current_scene is null")
		return

	var player = PLAYER_SCENE.instantiate()
	player.name = str(id)

	var has_id_property := false
	for property_info in player.get_property_list():
		if property_info.get("name", "") == "id":
			has_id_property = true
			break

	if has_id_property:
		player.set("id", id)
	else:
		player.set_meta("peer_id", id)
		_dbg("Spawned player scene has no 'id' property; stored peer_id metadata for id=" + str(id))

	player.set_multiplayer_authority(id)

	get_tree().current_scene.add_child(player)
	player.global_position = spawn_position

	players[id] = player
	_dbg("Spawned player id=" + str(id) + " at " + str(spawn_position) + " total_players=" + str(players.size()))

func _clear_players_registry():
	_dbg("Clearing players registry count=" + str(players.size()))
	for player_id in players.keys():
		var player = players[player_id]
		if is_instance_valid(player):
			player.queue_free()
	players.clear()

func _spawn_player_on_all(id: int, spawn_position: Vector3):
	_dbg("Spawning player on all id=" + str(id) + " spawn=" + str(spawn_position))
	if multiplayer.is_server():
		_spawn_player(id, spawn_position)
	_spawn_player.rpc(id, spawn_position)

func _remove_player_on_all(id: int):
	_dbg("Removing player on all id=" + str(id))
	if multiplayer.is_server():
		_remove_player(id)
	_remove_player.rpc(id)

# === Remove ===
@rpc("authority", "call_local", "reliable")
func _remove_player(id: int):
	if players.has(id):
		var p = players[id]
		if is_instance_valid(p):
			p.queue_free()
		players.erase(id)
		_dbg("Removed player id=" + str(id) + " remaining_players=" + str(players.size()))

@rpc("any_peer", "reliable")
func eliminate_player(id: int):
	if not multiplayer.is_server():
		_dbg("eliminate_player ignored on client for id=" + str(id))
		return
	if scene_transition_in_progress:
		_dbg("eliminate_player ignored during scene transition for id=" + str(id))
		return

	_dbg("eliminate_player requested id=" + str(id) + " players_before=" + str(players.keys()))

	_remove_player_on_all(id)
	ready_clients.erase(id)
	_dbg("eliminate_player processed id=" + str(id) + " players_after=" + str(players.keys()))

	# End the round when there is one (or zero) players left alive.
	if players.size() <= 1:
		_dbg("Round end reached. alive_count=" + str(players.size()) + " winner_candidates=" + str(players.keys()))
		_return_everyone_to_lobby()
		return

	_dbg("Player id=" + str(id) + " goes to spectate. alive_count=" + str(players.size()))
	_send_player_to_spectate(id)

func _send_player_to_spectate(id: int):
	_dbg("Sending player id=" + str(id) + " to spectate")
	if id == multiplayer.get_unique_id():
		_send_self_to_spectate()
	else:
		_send_self_to_spectate.rpc_id(id)

@rpc("authority", "reliable")
func _send_self_to_spectate():
	_dbg("_send_self_to_spectate called")
	if scene_transition_in_progress:
		_dbg("_send_self_to_spectate ignored during scene transition")
		return

	# Only allow spectate if this peer no longer has its own alive player entry.
	# This avoids stale/late spectate RPCs hijacking camera after a new round starts.
	var local_id := multiplayer.get_unique_id()
	if players.has(local_id):
		_dbg("_send_self_to_spectate ignored because local player still exists id=" + str(local_id))
		return
	var current_scene := get_tree().current_scene
	if current_scene == null:
		_dbg("_send_self_to_spectate aborted: current_scene is null")
		return

	var spectate_camera := current_scene.get_node_or_null("SpectateCamera/Camera3D") as Camera3D
	if spectate_camera == null:
		push_warning("Spectate camera not found at SpectateCamera/Camera3D")
		_dbg("_send_self_to_spectate failed: SpectateCamera/Camera3D missing")
		return

	spectate_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_dbg("Spectate camera activated")

func _return_everyone_to_lobby():
	if not multiplayer.is_server():
		return

	# Keep the session alive and move everyone together to the lobby.
	_dbg("Returning everyone to lobby")
	_change_scene_for_all("res://main.tscn")

func start_match_from_lobby():
	if not multiplayer.is_server():
		_dbg("start_match_from_lobby ignored: caller is not server")
		return

	_dbg("Starting match from lobby")
	_change_scene_for_all("res://game_area.tscn")

func _change_scene_for_all(path: String):
	if not multiplayer.is_server():
		_dbg("_change_scene_for_all ignored on client path=" + path)
		return
	if round_transition_in_progress:
		_dbg("_change_scene_for_all ignored: transition already in progress path=" + path)
		return

	round_transition_in_progress = true
	_dbg("Scene transition start path=" + path + " peers=" + str(multiplayer.get_peers()))

	# Ensure the host moves immediately.
	change_scene(path)

	# Send explicitly to each connected peer to avoid edge cases where a
	# broadcast RPC is missed during round-end transitions.
	for peer_id in multiplayer.get_peers():
		_dbg("Sending change_scene to peer=" + str(peer_id) + " path=" + path)
		change_scene.rpc_id(peer_id, path)

	round_transition_in_progress = false
	_dbg("Scene transition complete path=" + path)

func _spawn_all_players():
	if not multiplayer.is_server():
		_dbg("_spawn_all_players ignored on client")
		return

	_dbg("_spawn_all_players start peers=" + str(multiplayer.get_peers()))

	used_spawn_points.clear()
	_clear_players_registry()

	var all_ids: Array[int] = [multiplayer.get_unique_id()]
	for peer_id in multiplayer.get_peers():
		all_ids.append(peer_id)
	all_ids.shuffle()

	for peer_id in all_ids:
		_spawn_player_on_all(peer_id, get_spawn_position())

	ready_clients.clear()
	_dbg("_spawn_all_players complete players=" + str(players.keys()))

@rpc("any_peer", "reliable")
func client_ready_in_scene():
	if not multiplayer.is_server():
		_dbg("client_ready_in_scene ignored on client")
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		_dbg("client_ready_in_scene ignored: sender_id=0")
		return

	if waiting_spectators.has(sender_id):
		_dbg("Late join spectator ready sender_id=" + str(sender_id) + ". Syncing active players and sending spectate camera")
		for existing_id in players.keys():
			var existing_player = players[existing_id]
			if is_instance_valid(existing_player):
				_spawn_player.rpc_id(sender_id, existing_id, existing_player.global_position)
		_send_self_to_spectate.rpc_id(sender_id)
		return

	ready_clients[sender_id] = true
	var expected_clients := multiplayer.get_peers().size()
	_dbg("Client ready sender_id=" + str(sender_id) + " ready_count=" + str(ready_clients.size()) + " expected_clients=" + str(expected_clients))

	if ready_clients.size() >= expected_clients:
		_dbg("All expected clients are ready. Spawning all players")
		_spawn_all_players()

# === Scene ===
@rpc("authority", "call_local", "reliable")
func change_scene(path: String):
	if scene_transition_in_progress and pending_scene_path == path:
		_dbg("change_scene ignored duplicate while transition in progress path=" + path)
		return

	pending_scene_path = path
	call_deferred("_apply_pending_scene_change")

func _apply_pending_scene_change():
	if pending_scene_path == "":
		return

	var path := pending_scene_path
	pending_scene_path = ""

	_dbg("change_scene local begin path=" + path)
	scene_transition_in_progress = true
	_clear_players_registry()
	used_spawn_points.clear()
	ready_clients.clear()
	if path == "res://main.tscn":
		waiting_spectators.clear()
		_dbg("Cleared waiting_spectators on lobby return")
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	scene_transition_in_progress = false
	_dbg("change_scene local done path=" + path)

@rpc("authority", "reliable")
func _send_self_to_lobby():
	# Leaving the match peer prevents late in-flight gameplay RPCs
	# from targeting missing nodes after the lobby scene loads.
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null

	get_tree().change_scene_to_file("res://main.tscn")
