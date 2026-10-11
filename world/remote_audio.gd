extends RefCounted

const Loop := preload("audio_loop.gd")

const NEAR := 8.0
const FAR := 40.0
const ROLL_SPEED := 20.0
const ROLL_PITCH := 20.0
const AUDIBLE := 0.01

var _listener: Camera3D
var _roll := Loop.new(SFX.Name.MARBLE_LOOP)
var _slide := Loop.new(SFX.Name.WALL_SLIDE)


func listen(camera: Camera3D) -> void:
	_listener = camera


func reach(at: Vector3) -> float:
	if not is_instance_valid(_listener):
		return 1.0

	return 1.0 - smoothstep(NEAR, FAR, _listener.global_position.distance_to(at))


func play(sfx: SFX.Name, at: Vector3, adjust := 0.0) -> void:
	var gain := reach(at)

	if gain > AUDIBLE:
		AudioManager.play_sound_effect_at_location_3d(sfx, at, adjust + linear_to_db(gain))


func hit(at: Vector3, impact: float, magnetic: bool) -> void:
	var adjust := minf(remap(impact, 2.0, 20.0, -20.0, 10.0), 50.0)

	play(SFX.Name.MARBLE_MAGNETIZE if magnetic else SFX.Name.MARBLE_HIT, at, adjust)


func roll(at: Vector3, speed: float, touching: bool, delta: float) -> void:
	var level := clampf(speed / ROLL_SPEED, 0.0, 1.0) * reach(at) if touching else 0.0

	_roll.update(level, at, 1.0 + speed / ROLL_PITCH, delta)


func slide(at: Vector3, sliding: bool, delta: float) -> void:
	_slide.update(reach(at) if sliding else 0.0, at, 1.0, delta)


func stop() -> void:
	_roll.stop()
	_slide.stop()
