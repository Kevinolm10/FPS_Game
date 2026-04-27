extends StaticBody3D

@export var weapon_resource: WeaponResource

@onready var detection_area: Area3D = $DetectionArea

var _picked_up := false

func _ready() -> void:
	if weapon_resource == null:
		push_warning("[WeaponSpawn] No weapon_resource assigned")
		return
	detection_area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _picked_up:
		return
	if not body.is_in_group("player"):
		return

	# Only the player who owns this body should pick it up
	if not body.is_multiplayer_authority():
		return

	var wc := body.get_node_or_null("WeaponComponent") as WeaponComponent
	if wc == null:
		push_warning("[WeaponSpawn] Player has no WeaponComponent")
		return

	_picked_up = true
	detection_area.set_deferred("monitoring", false)

	wc.add_weapon(weapon_resource)
	wc.equip(weapon_resource)
	print("[WeaponSpawn] Player picked up: %s" % weapon_resource.weapon_name)