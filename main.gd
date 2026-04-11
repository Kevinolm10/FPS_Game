extends Node3D

var is_paused = false

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_close_dialog"):
		is_paused = !is_paused
		if is_paused:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
