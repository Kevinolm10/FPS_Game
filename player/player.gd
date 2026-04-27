extends CharacterBody3D

const WALK_SPEED := 0.5
const RUN_SPEED := 0.8
const JUMP_VELOCITY := 1.5
const BULLET_SCENE := preload("res://scenes/projectiles/bullet.tscn")

var id: int = 0
var speed := WALK_SPEED
var frozen := false
var is_running := false
var is_paused := false

enum PlayerState { LOBBY, IN_GAME, SPECTATING }
var current_state: PlayerState = PlayerState.LOBBY

@export var sensitivity: float = 0.003
@export var bullet_max_distance := 1000.0

@onready var camera: Camera3D = $Camera3D
@onready var health = $HealthComponent
@onready var anim = $AnimationComponent
@onready var weapon: WeaponComponent = $WeaponComponent
@onready var weapon_holder: Node3D = $Armature/Skeleton3D/r_right/WeaponHolder

var target_position: Vector3
var target_rotation: Vector3

func _ready() -> void:
	print("[Player] weapon_holder path result: %s" % str(weapon_holder))
	weapon.set_weapon_holder(weapon_holder)
	if id <= 0:
		id = int(name)

	health.reset()
	health.died.connect(_on_died)
	weapon.fired.connect(_on_weapon_fired)

	var found_anim := _find_animation_player()
	if found_anim != null:
		anim.setup(found_anim)
	else:
		push_warning("player.gd: No AnimationPlayer found")

	var scene_path := get_tree().current_scene.scene_file_path if get_tree().current_scene != null else ""
	_set_state(PlayerState.IN_GAME if scene_path == "res://scenes/world/game_area.tscn" else PlayerState.LOBBY)

	target_position = global_position
	target_rotation = rotation

	if is_multiplayer_authority():
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		camera.current = false

func _find_animation_player() -> AnimationPlayer:
	var results := find_children("*", "AnimationPlayer", true, false)
	return results[0] as AnimationPlayer if results.size() > 0 else null

func _set_state(state: PlayerState) -> void:
	current_state = state

func set_lobby_state() -> void: _set_state(PlayerState.LOBBY)
func set_game_state() -> void: _set_state(PlayerState.IN_GAME)
func set_spectate_state() -> void: _set_state(PlayerState.SPECTATING)

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event.is_action_pressed("ui_close_dialog"):
		is_paused = not is_paused
		frozen = is_paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_paused else Input.MOUSE_MODE_CAPTURED
		return

	if frozen or health.is_dead():
		return

	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * sensitivity)
		camera.rotate_x(-event.relative.y * sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, -PI / 3.0, PI / 3.0)
		camera.rotation.z = 0.0

func _physics_process(delta: float) -> void:
	if health.is_dead() or not multiplayer.has_multiplayer_peer():
		return

	if is_multiplayer_authority():
		if not camera.current:
			camera.current = true
		if not is_paused and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_handle_movement(delta)
		anim.tick_resync(delta)
		sync_transform.rpc(global_position, rotation, camera.rotation)
	else:
		global_position = global_position.lerp(target_position, 10.0 * delta)
		rotation = rotation.lerp(target_rotation, 10.0 * delta)

func _handle_movement(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if frozen:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		move_and_slide()
		return

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		anim.play("jump_unarmed")

	if Input.is_action_just_pressed("reload"):
		weapon.reload()

	if Input.is_action_pressed("shoot") and current_state != PlayerState.SPECTATING:
		weapon.shoot(camera.global_position, -camera.global_transform.basis.z)

	var input_dir := _get_move_input()
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	is_running = Input.is_action_pressed("run")
	speed = RUN_SPEED if is_running else WALK_SPEED

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	if not is_on_floor():
		anim.play("jump_unarmed")
	elif direction:
		anim.play("run_unarmed")
	else:
		anim.play("idle_unarmed")

	move_and_slide()

func _get_move_input() -> Vector2:
	var input_dir := Input.get_vector("left", "right", "forward", "backwards")
	if input_dir != Vector2.ZERO:
		return input_dir

	var fallback := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A): fallback.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): fallback.x += 1.0
	if Input.is_physical_key_pressed(KEY_W): fallback.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): fallback.y += 1.0
	return fallback.normalized() if fallback.length() > 1.0 else fallback

func _on_died() -> void:
	frozen = true
	set_physics_process(false)
	set_process_input(false)
	if is_multiplayer_authority():
		if multiplayer.is_server():
			NetworkManager.eliminate_player(id)
		else:
			NetworkManager.eliminate_player.rpc_id(1, id)

func _on_weapon_fired(from: Vector3, direction: Vector3, damage: int, _fire_rate: float) -> void:
	if multiplayer.is_server():
		_spawn_bullet(from, direction, damage, bullet_max_distance, id)
	else:
		_spawn_bullet.rpc_id(1, from, direction, damage, bullet_max_distance, id)

@rpc("unreliable")
func sync_transform(pos: Vector3, rot: Vector3, cam_rot: Vector3) -> void:
	if not is_inside_tree() or is_multiplayer_authority():
		return
	target_position = pos
	target_rotation = rot
	camera.rotation = cam_rot

@rpc("any_peer", "call_local", "reliable")
func _spawn_bullet(from: Vector3, direction: Vector3, damage: int, max_distance: float, shooter_id: int) -> void:
	if not multiplayer.is_server() or BULLET_SCENE == null:
		return
	var bullet = BULLET_SCENE.instantiate()
	var scene_root := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	scene_root.add_child(bullet)
	bullet.call("launch", from, direction, shooter_id, damage, max_distance)

@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int = 50) -> void:
	health.take_damage(amount)

func lobby_entered() -> void: set_lobby_state()
func lobby_exited() -> void: set_game_state()
