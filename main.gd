extends Node3D

var is_paused = false

func _ready():
	var points = $SpawnPoints.get_children()
	NetworkManager.register_spawn_points(points)
	print("Registered spawn points: ", points.size())
	# if this scene is loaded after hosting, spawn now
	if multiplayer.multiplayer_peer != null:
		NetworkManager.call_deferred("_spawn_host")
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_close_dialog"):
		is_paused = !is_paused
		if is_paused:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var local_player = NetworkManager.players.get(multiplayer.get_unique_id())
		if local_player:
			local_player.frozen = is_paused
