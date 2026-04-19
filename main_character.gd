extends CharacterBody3D

# === Variables ===
var id: int = 0
var HEALTH = 100
var SPEED = 0.5
const JUMP_VELOCITY = 1.5
var frozen = false
var can_shoot = true
var is_running = false
var is_dead = false
var is_paused = false

@export var sensitivity: float = 0.003

var bullet_scene = preload("res://bullet.tscn")

@onready var gun = $Camera3D/ak_47
@onready var gun_script = $Camera3D/ak_47
@onready var anim = $Camera3D/ak_47/AK/AnimationPlayer
@onready var camera = $Camera3D

# === Setup ===
func activate():
	if is_multiplayer_authority():
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _ready():
	if is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		camera.current = true
	else:
		camera.current = false
		set_physics_process(false)
		# Do NOT call set_process_input(false) — we still need _input for pause

# === Input Handling ===
func _input(event):
	# Pause only for local player
	if is_multiplayer_authority():
		if event.is_action_pressed("ui_close_dialog"):
			is_paused = !is_paused
			frozen = is_paused
			Input.mouse_mode = (
				Input.MOUSE_MODE_VISIBLE
				if is_paused
				else Input.MOUSE_MODE_CAPTURED
			)
			return

		if frozen or is_dead:
			return

		# Mouse look
		if event is InputEventMouseMotion:
			rotate_y(-event.relative.x * sensitivity)
			camera.rotate_x(-event.relative.y * sensitivity)
			camera.rotation.x = clamp(camera.rotation.x, -PI / 5, PI / 5)
			sync_camera_rotation.rpc(camera.rotation)

# Camera rotation sync — any_peer because each client is authority over their own camera
@rpc("any_peer", "unreliable")
func sync_camera_rotation(rot: Vector3):
	if not is_multiplayer_authority():
		camera.rotation = rot

# === Movement ===
func _physics_process(delta):
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

	if Input.is_action_just_pressed("reload") and not gun_script.is_reloading:
		gun_script.reload()

	if Input.is_action_pressed("shoot"):
		shoot()

	var input_dir = Input.get_vector("left", "right", "forward", "backwards")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	if Input.is_action_pressed("run") and can_shoot and not gun_script.is_reloading:
		if not is_running:
			is_running = true
			SPEED = 0.8
			sync_animation.rpc("sprint")
	elif is_running:
		is_running = false
		SPEED = 0.5
		stop_animation.rpc()

	move_and_slide()

# === Shooting ===
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

# === Networking ===
@rpc("any_peer", "call_local", "reliable")
func spawn_bullet(from: Vector3, direction: Vector3):
	if bullet_scene == null:
		return
	var bullet_instance = bullet_scene.instantiate()
	get_tree().root.add_child(bullet_instance)
	bullet_instance.launch(from, direction)

@rpc("any_peer", "call_local", "reliable")
func take_damage():
	if not is_multiplayer_authority() or is_dead:
		return
	HEALTH -= 50
	print("Player ", id, " health: ", HEALTH)
	if HEALTH <= 0:
		is_dead = true
		die.rpc()

# === Animation ===
@rpc("any_peer", "call_local")
func sync_animation(anim_name: String):
	if anim:
		anim.play(anim_name)

@rpc("any_peer", "call_local")
func stop_animation():
	if anim:
		anim.stop()

# === Death / Respawn ===
@rpc("any_peer", "call_local", "reliable")
func die():
	if is_dead and frozen:
		return
	is_dead = true
	frozen = true

	if is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await get_tree().create_timer(1.5).timeout
		if multiplayer.is_server():
			NetworkManager.request_respawn(id)
		else:
			NetworkManager.request_respawn.rpc_id(1, id)
		# Wait longer so respawn handshake finishes before node is freed
		await get_tree().create_timer(2.0).timeout
	else:
		# Non-authority waits for the new spawn to arrive before freeing
		await get_tree().create_timer(3.5).timeout

	if is_instance_valid(self):
		queue_free()
