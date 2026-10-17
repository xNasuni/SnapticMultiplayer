extends RefCounted

const DAMP := 10.0
const SILENT_DB := -80.0
const QUIET := 0.002
const MAX_ACTIVE := 3

static var _active := 0

var _sfx: SFX.Name
var _level := 0.0
var _counted := false
var _instance: SoundEffectInstance


func _init(sfx: SFX.Name) -> void:
	_sfx = sfx


func update(target: float, at: Vector3, pitch: float, delta: float) -> void:
	_level = Helpers.damp(_level, target, DAMP, delta)

	if _level < QUIET and target <= 0.0:
		stop()
		return

	if not _running() and not _start(at):
		return

	_instance.set_position(at)
	_instance.pitch_scale = pitch
	_instance.volume_db = maxf(linear_to_db(_level), SILENT_DB)


func stop() -> void:
	if _instance:
		_instance.stop()
		_instance = null

	_release()


func _running() -> bool:
	if _instance and _instance.is_valid():
		return true

	_instance = null
	_release()

	return false


func _start(at: Vector3) -> bool:
	if _active >= MAX_ACTIVE:
		return false

	var instance := AudioManager.play_sound_effect_at_location_3d(_sfx, at, SILENT_DB)

	if not instance.is_valid():
		return false

	_instance = instance
	_counted = true
	_active += 1

	return true


func _release() -> void:
	if _counted:
		_counted = false
		_active -= 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		stop()
