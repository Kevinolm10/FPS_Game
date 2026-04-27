extends Resource
class_name WeaponResource

@export var weapon_name: String = ""
@export var group_name: String = ""
@export var hold_animation: String = ""
@export var fire_rate: float = 300.0
@export var damage: int = 50
@export var mag_size: int = 30
@export var model_scene: PackedScene
@export var model_position: Vector3 = Vector3.ZERO
@export var model_rotation: Vector3 = Vector3.ZERO
@export var model_scale: Vector3 = Vector3.ONE
@export var is_on_floor = false
@export var floor_location: Vector3 = Vector3.ZERO
@export var floor_rotation: Vector3 = Vector3.ZERO
@export var is_pickup: bool = false
