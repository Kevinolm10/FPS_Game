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

func _ready():
	hide_buttons()
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
	NetworkManager.server()
	get_tree().change_scene_to_file("res://main.tscn")
	# _spawn_host() is called from main.gd _ready() on the server

func _on_join_pressed():
	var ip = ip_input.text.strip_edges()
	if ip == "":
		print("No IP entered")
		return
	print("Joining: ", ip)
	NetworkManager.client(ip)
	get_tree().change_scene_to_file("res://main.tscn")
	# notify_ready is called from main.gd _ready() on the client

func _on_back_pressed():
	main_menu = true
	hide_buttons()

func _on_settings_pressed():
	pass

func _on_quit_pressed():
	get_tree().quit()
