extends Node3D

# === Variables ===
var speed = 50.0
var target: Vector3
var traveling = false
var shooter_id := 0
var damage := 50

# === Launch ===
func launch(from: Vector3, to_direction: Vector3, owner_id: int = 0, shot_damage: int = 50, max_distance: float = 1000.0):
	shooter_id = owner_id
	damage = max(1, shot_damage)

	var space_state = get_world_3d().direct_space_state
	var to := from + to_direction.normalized() * max_distance
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]

	for player in get_tree().get_nodes_in_group("player"):
		var player_node := player as Node
		if player_node == null:
			continue
		if player_node.get_multiplayer_authority() == shooter_id:
			query.exclude.append(player_node)
			break

	var result = space_state.intersect_ray(query)
	target = result.position if result else to
	global_position = from
	traveling = true
	look_at(target)
	
	# Only server authoritatively deals damage
	if result and result.collider.is_in_group("player") and multiplayer.is_server():
		var victim_id: int = result.collider.get_multiplayer_authority()
		if victim_id > 0 and victim_id != shooter_id:
			result.collider.take_damage.rpc_id(victim_id, damage)

# === Movement ===
func _process(delta):
	if not traveling:
		return

	look_at(target)
	global_position = global_position.move_toward(target, speed * delta)

	if global_position.is_equal_approx(target):
		queue_free()
