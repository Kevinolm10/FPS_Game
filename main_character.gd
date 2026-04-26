extends CharacterBody3D

# === Variables ===
var id: int = 0
var HEALTH := 100

enum PlayerState {
	LOBBY,
	IN_GAME,
	SPECTATING,
}

const WALK_SPEED := 0.5
const RUN_SPEED := 0.8
const JUMP_VELOCITY := 1.5

var speed := WALK_SPEED
var frozen := false
var can_shoot := false
var is_running := false
var is_dead := false
var is_paused := false
var current_state: PlayerState = PlayerState.LOBBY

@export var sensitivity: float = 0.003

const BULLET_SCENE := preload("res://bullet.tscn")
var active_animation := ""
var animation_sync_timer := 0.0
const ANIMATION_RESYNC_INTERVAL := 0.5
@export var default_animation_speed := 1.0
@export var animation_speed_overrides: Dictionary = {
	"idle_unarmed": 0.3,
}
@export var weapon_group_animation_map: Dictionary = {
	"pistol": "Mplayer/pistol_anim",
	"rifle": "Mplayer/rifle_armed",
}
@export var weapon_group_priority: Array[String] = ["rifle", "pistol"]
@export var weapon_group_fire_rate_map: Dictionary = {
	"pistol": 300.0,
	"rifle": 600.0,
}
@export var weapon_group_damage_map: Dictionary = {
	"pistol": 35,
	"rifle": 50,
}
@export var bullet_max_distance := 1000.0

#@onready var gun = $Camera3D/ak_47
# @onready var gun_script = $Camera3D/ak_47
# @onready var anim = $Camera3D/ak_47/AK/AnimationPlayer
@onready var camera = $Camera3D
@onready var p_anim: AnimationPlayer = _resolve_animation_player()
@onready var r_hand = $Armature/Skeleton3D/r_right

# === Network smoothing ===
var target_position: Vector3
var target_rotation: Vector3

func _dbg(message: String):
	var role := "AUTH" if is_multiplayer_authority() else "REMOTE"
	print("[Player id=", id, " ", role, " dead=", is_dead, " hp=", HEALTH, "] ", message)

func _player_state_name(state: PlayerState) -> String:
	match state:
		PlayerState.LOBBY:
			return "LOBBY"
		PlayerState.IN_GAME:
			return "IN_GAME"
		PlayerState.SPECTATING:
			return "SPECTATING"
		_:
			return "UNKNOWN"

func _apply_player_state(state: PlayerState) -> void:
	current_state = state
	match current_state:
		PlayerState.LOBBY:
			can_shoot = true
		PlayerState.IN_GAME:
			can_shoot = true
		PlayerState.SPECTATING:
			can_shoot = false
	_dbg("Player state set to " + _player_state_name(current_state) + " can_shoot=" + str(can_shoot))

func set_lobby_state() -> void:
	_apply_player_state(PlayerState.LOBBY)

func set_game_state() -> void:
	_apply_player_state(PlayerState.IN_GAME)

func set_spectate_state() -> void:
	_apply_player_state(PlayerState.SPECTATING)

func _is_game_state() -> bool:
	return current_state == PlayerState.IN_GAME

func _resolve_animation_player() -> AnimationPlayer:
	var model := get_node_or_null("Mplayer")
	if model != null:
		var model_anim_players := model.find_children("*", "AnimationPlayer", true, false)
		if model_anim_players.size() > 0:
			return model_anim_players[0] as AnimationPlayer

	var any_anim_players := find_children("*", "AnimationPlayer", true, false)
	if any_anim_players.size() > 0:
		return any_anim_players[0] as AnimationPlayer

	return null

func _play_network_animation(anim_name: String) -> void:
	if not is_multiplayer_authority():
		return
	if active_animation == anim_name:
		return
	active_animation = anim_name
	var anim_speed := _get_animation_speed(anim_name)
	sync_animation.rpc(anim_name, anim_speed)

func _stop_network_animation() -> void:
	if not is_multiplayer_authority():
		return
	if active_animation == "":
		return
	active_animation = ""
	stop_animation.rpc()

func _ensure_idle_animation_loops() -> void:
	if p_anim == null:
		return
	if not p_anim.has_animation("idle_unarmed"):
		return
	var idle_anim := p_anim.get_animation("idle_unarmed")
	if idle_anim != null:
		idle_anim.loop_mode = Animation.LOOP_LINEAR

func _ensure_weapon_anims_do_not_loop() -> void:
	if p_anim == null:
		return
	var seen: Dictionary = {}
	for mapped_animation in weapon_group_animation_map.values():
		var animation_name := str(mapped_animation)
		if animation_name == "" or seen.has(animation_name):
			continue
		seen[animation_name] = true
		if not p_anim.has_animation(animation_name):
			continue
		var hold_anim := p_anim.get_animation(animation_name)
		if hold_anim != null:
			hold_anim.loop_mode = Animation.LOOP_NONE

# === Setup ===
func _ready():
	await get_tree().process_frame
	if id <= 0:
		id = int(name)

	# Ensure a freshly spawned player starts in a clean, controllable state.
	is_dead = false
	frozen = false
	is_paused = false
	HEALTH = 100
	set_physics_process(true)
	set_process_input(true)

	var scene_path := ""
	if get_tree().current_scene != null:
		scene_path = get_tree().current_scene.scene_file_path
	if scene_path == "res://game_area.tscn":
		set_game_state()
	else:
		set_lobby_state()

	target_position = global_position
	target_rotation = rotation
	animation_sync_timer = 0.0
	p_anim = _resolve_animation_player()
	if p_anim == null:
		_dbg("No AnimationPlayer found in this character scene")
	else:
		_ensure_idle_animation_loops()
		_ensure_weapon_anims_do_not_loop()

	if is_multiplayer_authority():
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_dbg("Ready as authority")
	else:
		camera.current = false
		_dbg("Ready as remote replica")

# === Input ===
func _input(event):
	if not is_multiplayer_authority():
		return

	if event.is_action_pressed("ui_close_dialog"):
		is_paused = !is_paused
		frozen = is_paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_paused else Input.MOUSE_MODE_CAPTURED
		return

	if frozen or is_dead:
		return

	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * sensitivity)
		camera.rotate_x(-event.relative.y * sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, -PI / 3, PI / 3)

# === Movement ===
func _physics_process(delta):
	if is_dead:
		return
	if not multiplayer.has_multiplayer_peer():
		return

	if is_multiplayer_authority():
		if not camera.current:
			camera.current = true
		if not is_paused and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		_handle_movement(delta)
		_sync_animation_heartbeat(delta)

		# Sync transform
		sync_transform.rpc(global_position, rotation, camera.rotation)
	else:
		# Smooth remote players
		global_position = global_position.lerp(target_position, 10 * delta)
		rotation = rotation.lerp(target_rotation, 10 * delta)

func _sync_animation_heartbeat(delta: float) -> void:
	if active_animation == "":
		animation_sync_timer = 0.0
		return
	if _is_weapon_hold_animation(active_animation):
		# Weapon hold poses should not be replayed by heartbeat resync.
		animation_sync_timer = 0.0
		return

	animation_sync_timer += delta
	if animation_sync_timer < ANIMATION_RESYNC_INTERVAL:
		return

	animation_sync_timer = 0.0
	var anim_speed := _get_animation_speed(active_animation)
	sync_animation.rpc(active_animation, anim_speed)

func _get_animation_speed(anim_name: String) -> float:
	if animation_speed_overrides.has(anim_name):
		return float(animation_speed_overrides[anim_name])
	return default_animation_speed

func set_animation_speed(anim_name: String, anim_speed: float) -> void:
	animation_speed_overrides[anim_name] = anim_speed
	if is_multiplayer_authority() and active_animation == anim_name:
		sync_animation.rpc(anim_name, _get_animation_speed(anim_name))

func _handle_movement(delta):
	var on_floor := is_on_floor()

	if not on_floor:
		velocity += get_gravity() * delta

	if frozen:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		move_and_slide()
		return

	if Input.is_action_just_pressed("ui_accept") and on_floor:
		velocity.y = JUMP_VELOCITY
		_play_network_animation("jump_unarmed")
	if Input.is_action_just_pressed("reload"):
		reload_equipped_weapon()

	if Input.is_action_pressed("shoot"):
		shoot()

	var input_dir = _get_move_input()
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if Input.is_action_pressed("run") and not is_running:
		is_running = true
		speed = RUN_SPEED
	elif not Input.is_action_pressed("run") and is_running:
		is_running = false
		speed = WALK_SPEED

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	# Keep weapon hold pose stable whenever an equipped weapon group maps to a hold animation.
	var weapon_hold_animation := _get_equipped_weapon_hold_animation()
	if weapon_hold_animation != "":
		_play_network_animation(weapon_hold_animation)
	# Airborne animation must win over locomotion so jump is not immediately overridden.
	elif not is_on_floor():
		_play_network_animation("jump_unarmed")
	elif direction:
		_play_network_animation("run_unarmed")
	else:
		_play_network_animation("idle_unarmed")

	# Running
	# if Input.is_action_pressed("run") and can_shoot and not gun_script.is_reloading:
	# 	if not is_running:
	# 		is_running = true
	# 		speed = RUN_SPEED
	# 		sync_animation.rpc("run_unarmed")
	# else:
	# 	if is_running:
	# 		is_running = false
	# 		speed = WALK_SPEED
	# 		stop_animation.rpc()

	move_and_slide()

func _get_move_input() -> Vector2:
	# Primary path: project input actions.
	var input_dir := Input.get_vector("left", "right", "forward", "backwards")
	if input_dir != Vector2.ZERO:
		return input_dir

	# Fallback path: physical WASD and ui_* actions.
	# This helps when one debug instance misses custom movement action states.
	var fallback := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		fallback.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		fallback.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		fallback.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		fallback.y += 1.0

	if fallback.length() > 1.0:
		fallback = fallback.normalized()

	return fallback

func _is_weapon_hold_animation(animation_name: String) -> bool:
	for mapped_animation in weapon_group_animation_map.values():
		if str(mapped_animation) == animation_name:
			return true
	return false

func _get_equipped_weapon_hold_animation() -> String:
	var equipped := _get_equipped_weapon_data()
	if equipped.is_empty():
		return ""
	var group_name := str(equipped["group"])
	if weapon_group_animation_map.has(group_name):
		return str(weapon_group_animation_map[group_name])
	return ""

func _get_equipped_weapon_data() -> Dictionary:
	var hand_roots: Array[Node] = []
	if r_hand != null:
		hand_roots.append(r_hand)

	for group_name in weapon_group_priority:
		if not weapon_group_animation_map.has(group_name):
			continue
		for hand_root in hand_roots:
			var found := _find_node_in_group_recursive(hand_root, group_name)
			if found != null:
				return {
					"group": group_name,
					"node": found,
				}

	for mapped_group in weapon_group_animation_map.keys():
		var group_name := str(mapped_group)
		if weapon_group_priority.has(group_name):
			continue
		for hand_root in hand_roots:
			var found := _find_node_in_group_recursive(hand_root, group_name)
			if found != null:
				return {
					"group": group_name,
					"node": found,
				}

	return {}

func _node_has_property(node: Node, property_name: String) -> bool:
	for property_info in node.get_property_list():
		if property_info.get("name", "") == property_name:
			return true
	return false

func _get_weapon_fire_rate(equipped: Dictionary) -> float:
	if equipped.is_empty():
		return 0.0

	var group_name := str(equipped["group"])
	var weapon_node := equipped["node"] as Node

	if weapon_node != null and _node_has_property(weapon_node, "fire_rate"):
		var from_weapon := float(weapon_node.get("fire_rate"))
		if from_weapon > 0.0:
			return from_weapon

	if weapon_group_fire_rate_map.has(group_name):
		return max(1.0, float(weapon_group_fire_rate_map[group_name]))

	return 300.0

func _get_weapon_damage(equipped: Dictionary) -> int:
	if equipped.is_empty():
		return 0

	var group_name := str(equipped["group"])
	if weapon_group_damage_map.has(group_name):
		return max(1, int(weapon_group_damage_map[group_name]))

	return 50

func reload_equipped_weapon() -> void:
	if not is_multiplayer_authority():
		return

	var equipped := _get_equipped_weapon_data()
	if equipped.is_empty():
		return

	var weapon_node := equipped["node"] as Node
	if weapon_node == null:
		return

	if weapon_node.has_method("reload"):
		weapon_node.call("reload")

func _consume_weapon_ammo_or_reload(equipped: Dictionary) -> bool:
	if equipped.is_empty():
		return false

	var weapon_node := equipped["node"] as Node
	if weapon_node == null:
		return false

	if _node_has_property(weapon_node, "is_reloading") and bool(weapon_node.get("is_reloading")):
		return false

	if _node_has_property(weapon_node, "mag_ammo"):
		var mag_ammo := int(weapon_node.get("mag_ammo"))
		if mag_ammo <= 0:
			if weapon_node.has_method("reload"):
				weapon_node.call("reload")
			return false
		weapon_node.set("mag_ammo", mag_ammo - 1)

	return true

func _get_shot_origin() -> Vector3:
	var equipped := _get_equipped_weapon_data()
	if not equipped.is_empty():
		var weapon_node := equipped["node"] as Node3D
		if weapon_node != null:
			return weapon_node.global_position
	return camera.global_position

func shoot() -> void:
	if not is_multiplayer_authority():
		return
	if not _is_game_state() or not can_shoot or is_dead:
		return

	var equipped := _get_equipped_weapon_data()
	if equipped.is_empty():
		return
	if not _consume_weapon_ammo_or_reload(equipped):
		return

	var fire_rate := _get_weapon_fire_rate(equipped)
	var damage := _get_weapon_damage(equipped)
	var from := _get_shot_origin()
	var dir: Vector3 = -camera.global_transform.basis.z

	if multiplayer.is_server():
		_spawn_bullet(from, dir, damage, bullet_max_distance, id)
	else:
		_spawn_bullet.rpc_id(1, from, dir, damage, bullet_max_distance, id)

	can_shoot = false
	await get_tree().create_timer(60.0 / max(fire_rate, 1.0)).timeout
	if is_inside_tree() and not is_dead:
		can_shoot = true

func _find_node_in_group_recursive(root: Node, group_name: String) -> Node:
	if root.is_in_group(group_name):
		return root
	for child in root.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		var found := _find_node_in_group_recursive(child_node, group_name)
		if found != null:
			return found
	return null
	
# === Shooting ===

# === Networking ===
@rpc("unreliable")
func sync_transform(pos: Vector3, rot: Vector3, cam_rot: Vector3):
	if not is_inside_tree():
		return

	if not is_multiplayer_authority():
		target_position = pos
		target_rotation = rot
		camera.rotation = cam_rot

@rpc("any_peer", "call_local", "reliable")
func _spawn_bullet(from: Vector3, direction: Vector3, damage: int, max_distance: float, shooter_id: int):
	if not multiplayer.is_server():
		return
	if BULLET_SCENE == null:
		return

	var bullet = BULLET_SCENE.instantiate()
	if get_tree().current_scene != null:
		get_tree().current_scene.add_child(bullet)
	else:
		get_tree().root.add_child(bullet)
	bullet.call("launch", from, direction, shooter_id, damage, max_distance)

@rpc("any_peer", "reliable")
func request_damage(amount: int = 50):
	take_damage(amount)

@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int = 50):
	if not is_inside_tree():
		return

	if not is_multiplayer_authority():
		return

	if is_dead:
		return

	HEALTH -= amount
	_dbg("Took damage. New health=" + str(HEALTH))

	if HEALTH <= 0:
		_dbg("Health <= 0. Entering local die()")
		die()

# === Animation ===
@rpc("any_peer", "call_local", "reliable")
func sync_animation(anim_name: String, anim_speed: float = 1.0):
	if p_anim == null:
		return
	if not p_anim.has_animation(anim_name):
		_dbg("Animation missing on this character: " + anim_name)
		return
	p_anim.speed_scale = anim_speed
	p_anim.play(anim_name)

@rpc("any_peer", "call_local", "reliable")
func stop_animation():
	if p_anim:
		p_anim.stop()
		p_anim.speed_scale = 1.0

# === Death ===
func die():
	if is_dead:
		_dbg("die() ignored because already dead")
		return

	is_dead = true
	frozen = true
	can_shoot = false
	set_physics_process(false)
	set_process_input(false)

	if is_multiplayer_authority():
		_dbg("Authority entered die() and will request elimination from server")
		if multiplayer.is_server():
			NetworkManager.eliminate_player(id)
		else:
			NetworkManager.eliminate_player.rpc_id(1, id)

# === No damage in lobby ===
func lobby_entered():
	set_lobby_state()

func lobby_exited():
	set_game_state()
