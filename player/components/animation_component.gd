extends Node
class_name AnimationComponent

const IDLE := "Mplayer/idle_unarmed"
const RUN := "Mplayer/run_unarmed"
const JUMP := "Mplayer/jump_unarmed"

var anim_player: AnimationPlayer = null
var active_animation: String = ""
var animation_sync_timer: float = 0.0

const RESYNC_INTERVAL := 0.5

@export var speed_overrides: Dictionary = {
	"Mplayer/idle_unarmed": 0.3,
}

func setup(player_anim: AnimationPlayer) -> void:
	anim_player = player_anim
	_ensure_idle_loops()

func play(anim_name: String) -> void:
	if anim_player == null:
		return
	var resolved := _resolve_animation_name(anim_name)
	if resolved == "":
		push_warning("AnimationComponent: missing animation '%s'" % anim_name)
		return
	if active_animation == resolved:
		return
	active_animation = resolved
	var spd := float(speed_overrides.get(resolved, speed_overrides.get(anim_name, 1.0)))
	_sync_animation.rpc(resolved, spd)

func stop() -> void:
	if anim_player == null:
		return
	active_animation = ""
	_stop_animation.rpc()

func tick_resync(delta: float) -> void:
	if active_animation == "":
		animation_sync_timer = 0.0
		return
	animation_sync_timer += delta
	if animation_sync_timer < RESYNC_INTERVAL:
		return
	animation_sync_timer = 0.0
	var spd := float(speed_overrides.get(active_animation, 1.0))
	_sync_animation.rpc(active_animation, spd)

@rpc("any_peer", "call_local", "reliable")
func _sync_animation(anim_name: String, spd: float = 1.0) -> void:
	if anim_player == null or not anim_player.has_animation(anim_name):
		return
	anim_player.speed_scale = spd
	anim_player.play(anim_name)

@rpc("any_peer", "call_local", "reliable")
func _stop_animation() -> void:
	if anim_player == null:
		return
	anim_player.stop()
	anim_player.speed_scale = 1.0

func _ensure_idle_loops() -> void:
	if anim_player == null or not anim_player.has_animation(IDLE):
		return
	var idle_anim := anim_player.get_animation(IDLE)
	if idle_anim != null:
		idle_anim.loop_mode = Animation.LOOP_LINEAR

func _resolve_animation_name(anim_name: String) -> String:
	if anim_player == null or anim_name == "":
		return ""
	if anim_player.has_animation(anim_name):
		return anim_name

	if not anim_name.contains("/"):
		var prefixed := "Mplayer/%s" % anim_name
		if anim_player.has_animation(prefixed):
			return prefixed
	else:
		var split := anim_name.split("/", false, 1)
		if split.size() == 2 and anim_player.has_animation(split[1]):
			return split[1]

	return ""
