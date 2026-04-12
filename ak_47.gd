extends Node3D

var mag_ammo = 10
var max_ammo = 200
var fire_rate = 600
var is_reloading = false

@onready var anim = $AK/AnimationPlayer

func reload():
	if is_reloading or max_ammo <= 0:
		return
	is_reloading = true
	sync_reload.rpc(true)
	await anim.animation_finished  # wait for full reload animation
	var ammo_needed = 30 - mag_ammo
	var ammo_to_add = min(ammo_needed, max_ammo)
	mag_ammo += ammo_to_add
	max_ammo -= ammo_to_add
	print("mag: ", mag_ammo, " reserve: ", max_ammo)
	is_reloading = false
	sync_reload.rpc(false)

@rpc("call_local", "reliable")
func sync_reload(reloading: bool):
	if reloading:
		anim.play("reload_004")
	else:
		anim.stop()  # just stop instead of playing RESET
