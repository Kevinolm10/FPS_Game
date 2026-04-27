extends Node
class_name WeaponComponent

signal fired(from: Vector3, direction: Vector3, damage: int, fire_rate: float)

@export var weapons: Array[Resource] = []

var equipped: WeaponResource = null
var mag_ammo: int = 0
var is_reloading: bool = false
var can_fire: bool = true
var weapon_holder: Node3D = null
var _tracked_model: Node3D = null
var _visibility_timer: float = 0.0

func set_weapon_holder(holder: Node3D) -> void:
	print("[WeaponComponent] set_weapon_holder | holder: %s | path: %s" % [str(holder), holder.get_path() if holder else "null"])
	weapon_holder = holder

func add_weapon(wr: WeaponResource) -> void:
	if not weapons.has(wr):
		weapons.append(wr)
		print("[WeaponComponent] add_weapon | added: %s | total: %d" % [wr.weapon_name, weapons.size()])

func equip(weapon: WeaponResource) -> void:
	print("[WeaponComponent] equip called | weapon: %s | holder: %s | children before: %d" % [
		weapon.weapon_name, str(weapon_holder), weapon_holder.get_child_count() if weapon_holder else -1
	])

	if weapon_holder == null:
		push_warning("[WeaponComponent] equip: weapon_holder is null")
		return

	for child in weapon_holder.get_children():
		print("[WeaponComponent] freeing child: %s | visible: %s" % [child.name, str(child.visible)])
		child.free()

	_tracked_model = null
	equipped = weapon
	mag_ammo = weapon.mag_size
	is_reloading = false

	if weapon.model_scene != null:
		var model: Node3D = weapon.model_scene.instantiate()
		weapon_holder.add_child(model)
		model.position = weapon.model_position
		model.rotation = weapon.model_rotation
		model.scale = weapon.model_scale
		_tracked_model = model

		print("[WeaponComponent] model added | name: %s | visible: %s | pos: %s | holder children: %d" % [
			model.name, str(model.visible), str(model.position), weapon_holder.get_child_count()
		])
		print("[WeaponComponent] holder visible: %s | holder global_pos: %s" % [
			str(weapon_holder.visible), str(weapon_holder.global_position)
		])

		model.visibility_changed.connect(func():
			print("[WeaponComponent] !! model visibility changed | visible: %s | model valid: %s" % [
				str(model.visible) if is_instance_valid(model) else "FREED",
				str(is_instance_valid(model))
			])
		)
	else:
		push_warning("[WeaponComponent] model_scene is null on: %s" % weapon.weapon_name)

func _process(_delta: float) -> void:
	if _tracked_model == null or not is_instance_valid(_tracked_model):
		return
	_visibility_timer += _delta
	if _visibility_timer >= 1.0:
		_visibility_timer = 0.0
		print("[WeaponComponent] [tick] model: %s | visible: %s | in_tree: %s | parent: %s | holder children: %d" % [
			_tracked_model.name,
			str(_tracked_model.visible),
			str(_tracked_model.is_inside_tree()),
			str(_tracked_model.get_parent().name) if _tracked_model.get_parent() else "null",
			weapon_holder.get_child_count() if weapon_holder else -1
		])

func shoot(from: Vector3, direction: Vector3) -> void:
	if equipped == null or not can_fire or is_reloading:
		return
	if mag_ammo <= 0:
		reload()
		return
	mag_ammo -= 1
	can_fire = false
	fired.emit(from, direction, equipped.damage, equipped.fire_rate)
	await get_tree().create_timer(60.0 / max(equipped.fire_rate, 1.0)).timeout
	if is_inside_tree():
		can_fire = true

func reload() -> void:
	if equipped == null or is_reloading:
		return
	is_reloading = true
	mag_ammo = equipped.mag_size
	is_reloading = false

func has_weapon() -> bool:
	return equipped != null