# main_character.gd
extends CharacterBody3D

var SPEED = 0.5
const JUMP_VELOCITY = 1.5
var frozen = false
var can_shoot = true
var is_running = false
var cam_default_rotation: Vector3

@export var sensitivity: float = 0.003

var bullet_scene = preload("res://bullet.tscn")

@onready var gun = $Camera3D/ak_47
@onready var gun_script = $Camera3D/ak_47
@onready var anim = $Camera3D/ak_47/AK/AnimationPlayer
@onready var camera = $Camera3D

func _ready():
	if is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		camera.current = true
	else:
		camera.current = false
	cam_default_rotation = camera.rotation

func _input(event):
	if frozen or not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * sensitivity)
		camera.rotate_x(-event.relative.y * sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, -PI/5, PI/5)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	if frozen:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		move_and_slide()
		return

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Reload
	if Input.is_action_just_pressed("reload") and not gun_script.is_reloading:
		gun_script.reload()

	# Shoot
	if Input.is_action_pressed("shoot"):
		shoot()

	# Movement
	var input_dir := Input.get_vector("left", "right", "forward", "backwards")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		camera.rotation.z = lerp(camera.rotation.z, -input_dir.x * 0.1, delta * 10.0)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		camera.rotation.z = lerp(camera.rotation.z, cam_default_rotation.z, delta * 10.0)

	# Run
	if Input.is_action_pressed("run") and can_shoot and not gun_script.is_reloading:
		if not is_running:
			is_running = true
			SPEED = 0.8
			sync_animation.rpc("sprint")
	elif is_running:
		is_running = false
		SPEED = 0.5
		stop_animation.rpc()

	# Lean
	if Input.is_action_pressed("lean_l"):
		camera.rotation.z = lerp(camera.rotation.z, 0.3, delta * 10.0)
	elif Input.is_action_pressed("lean_r"):
		camera.rotation.z = lerp(camera.rotation.z, -0.3, delta * 10.0)

	move_and_slide()

func shoot():
	if not can_shoot or gun_script.is_reloading:
		return
	if gun_script.mag_ammo <= 0:
		gun_script.reload()
		return
	var shoot_direction = -camera.global_transform.basis.z
	spawn_bullet.rpc(gun.global_position, shoot_direction)
	gun_script.mag_ammo -= 1
	can_shoot = false
	sync_animation.rpc("recoil")
	await get_tree().create_timer(60.0 / gun_script.fire_rate).timeout
	can_shoot = true
	stop_animation.rpc()
	if gun_script.mag_ammo <= 0:
		gun_script.reload()

@rpc("authority", "call_local", "reliable")
func spawn_bullet(from: Vector3, direction: Vector3):
	if bullet_scene == null:
		return
	var bullet_instance = bullet_scene.instantiate()
	get_tree().root.add_child(bullet_instance)
	bullet_instance.launch(from, direction)

@rpc("authority", "call_local")
func sync_animation(anim_name: String):
	if anim:
		anim.play(anim_name)

@rpc("authority", "call_local")
func stop_animation():
	if anim:
		anim.stop()
