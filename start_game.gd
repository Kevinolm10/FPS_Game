extends Node3D

# Variables
var is_game_started = false

# On ready variables
@onready var interactable_area = $Area3D
@onready var startUI = $StartGameUi

# Functions
func _on_body_entered(body: Node3D):
	startUI.visible = true

func _on_body_exited(body: Node3D):
	startUI.visible = false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and startUI.visible:
		start_game()

func start_game() -> void:
	if not multiplayer.is_server():
		return
	print("starting game...")
	NetworkManager.change_scene.rpc("res://game_area.tscn")

@rpc("authority", "call_local", "reliable")
func change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

func _ready() -> void:
	startUI.visible = false
	interactable_area.body_entered.connect(_on_body_entered)
	interactable_area.body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	pass
