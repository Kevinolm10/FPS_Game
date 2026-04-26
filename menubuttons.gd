extends Node3D

var main_menu = true

@onready var main_menuUi = $MainMenu
@onready var play = $MainMenu/MainMenuButtons/Play
@onready var settings = $MainMenu/MainMenuButtons/Settings
@onready var quit = $MainMenu/MainMenuButtons/Quit

@onready var playUi = $PlayUI
@onready var host = $PlayUI/PlayUIButtons/Host
@onready var join = $PlayUI/PlayUIButtons/Join
@onready var backB = $PlayUI/PlayUIButtons/Back
@onready var ip_input = $PlayUI/PlayUIButtons/HostIP

func _dbg(message: String):
	var role := "SERVER" if multiplayer.is_server() else "CLIENT"
	print("[MenuButtons][", role, " id=", multiplayer.get_unique_id(), "] ", message)

func _ready():
	hide_buttons()
	_dbg("Ready and UI initialized")

	play.pressed.connect(_on_play_pressed)
	settings.pressed.connect(_on_settings_pressed)
	quit.pressed.connect(_on_quit_pressed)
	backB.pressed.connect(_on_back_pressed)
	host.pressed.connect(_on_host_pressed)
	join.pressed.connect(_on_join_pressed)

func hide_buttons():
	if main_menu:
		playUi.hide()
		main_menuUi.show()
	else:
		main_menuUi.hide()
		playUi.show()

func _on_play_pressed():
	main_menu = false
	hide_buttons()

func _on_host_pressed():
	_dbg("Host pressed")
	NetworkManager.server()
	await get_tree().process_frame
	_dbg("Changing to lobby scene main.tscn after hosting")
	get_tree().change_scene_to_file("res://main.tscn")

func _on_join_pressed():
	var ip = ip_input.text.strip_edges()
	if ip == "":
		_dbg("Join pressed with empty IP")
		return

	_dbg("Join pressed. Connecting to IP=" + ip)
	NetworkManager.client(ip)
	while multiplayer.multiplayer_peer == null:
		await get_tree().process_frame

	while multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		await get_tree().process_frame
		_dbg("Still connecting...")

	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		_dbg("Failed to connect to host")
		return

	_dbg("Connected. Changing to lobby scene main.tscn")
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://main.tscn")

func _on_back_pressed():
	main_menu = true
	hide_buttons()

func _on_settings_pressed():
	pass

func _on_quit_pressed():
	get_tree().quit()
