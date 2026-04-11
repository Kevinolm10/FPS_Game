extends CharacterBody3D
const SPEED = 0.5
const JUMP_VELOCITY = 1.5
var is_shooting = false
var cam_default_rotation: Vector3
@export var sensitivity: float = 0.003
@export var bullet_scene: PackedScene
@onready var anim = $Gun/AnimationPlayer
@onready var gun = $Gun
@onready var camera = $Camera3D

func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * sensitivity)
		camera.rotate_x(-event.relative.y * sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, -PI/5, PI/5)
		gun.rotation.x = -camera.rotation.x

func shoot():
	if bullet_scene == null:
		print("no bullet scene")
		return
	var bullet_instance = bullet_scene.instantiate() as CharacterBody3D
	if bullet_instance == null:
		print("bullet instance is null")
		return
	get_tree().root.add_child(bullet_instance)
	var shoot_direction = -$Camera3D.global_transform.basis.z
	bullet_instance.launch($Gun.global_position, shoot_direction)
	if anim:
		anim.play("CubeAction")

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	cam_default_rotation = camera.rotation
	print($Camera3D/Gun)

	if Input.is_action_just_pressed("shoot"):
		shoot()
		await get_tree().process_frame
		print("bullets in scene: ", get_tree().get_nodes_in_group("bullets").size())

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("shoot"):
		shoot()
	if not is_on_floor():
		velocity += get_gravity() * delta
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	# These must be outside all the if blocks
	var input_dir := Input.get_vector("left", "right", "forward", "backwards")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		camera.rotation.z = lerp(camera.rotation.z, -input_dir.x * 0.05, delta * 10.0)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		camera.rotation.z = lerp(camera.rotation.z, cam_default_rotation.z, delta * 10.0)
	
	move_and_slide()
	
	if Input.is_action_pressed("Sit"):
		position.y -= -0.035
