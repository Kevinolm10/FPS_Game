extends Node3D

# Variables
var is_game_started = false

# On ready variables
@onready var interactable_area = $Area3D
@onready var startUI = $StartGameUi
# @onready var player = $mplayer

func _dbg(message: String):
	var role := "SERVER" if multiplayer.is_server() else "CLIENT"
	print("[StartGame][", role, " id=", multiplayer.get_unique_id(), "] ", message)

func _session_player_count() -> int:
	# Host is included in the session count.
	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_peers().size() + 1
	return 1

func _can_host_start() -> bool:
	if not multiplayer.is_server():
		return false
	return _session_player_count() >= 1

func _set_start_ui_visible_for_body(body: Node3D, visible: bool):
	if not body.is_in_group("player"):
		return
	if not body.is_multiplayer_authority():
		return

	# Only host should get the start prompt in lobby.
	if not _can_host_start():
		startUI.visible = false
		_dbg("UI hidden. Not enough players to start. session_player_count=" + str(_session_player_count()))
		return

	startUI.visible = visible
	_dbg("Local host body " + ("entered" if visible else "exited") + " start zone body=" + body.name + " startUI.visible=" + str(startUI.visible))

# Functions
func _on_body_entered(body: Node3D):
	_set_start_ui_visible_for_body(body, true)

func _on_body_exited(body: Node3D):
	_set_start_ui_visible_for_body(body, false)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and startUI.visible:
		_dbg("Interact pressed while startUI visible. Attempting start_game")
		start_game()
		


func start_game() -> void:
	if not _can_host_start():
		_dbg("start_game ignored. host_required=true enough_players=false session_player_count=" + str(_session_player_count()))
		return
	_dbg("starting game via NetworkManager.start_match_from_lobby")
	NetworkManager.start_match_from_lobby()

@rpc("authority", "call_local", "reliable")
func change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

func _ready() -> void:
	startUI.visible = false
	_dbg("Ready. startUI hidden and area signals connected")
	interactable_area.body_entered.connect(_on_body_entered)
	interactable_area.body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	pass
