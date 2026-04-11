extends Area3D

func _on_body_entered(body: Node3D):
	if body.is_in_group("dummy"):
		body.take_damage(10)
		queue_free()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	body_entered.connect(_on_body_entered)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
