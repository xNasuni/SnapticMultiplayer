extends RefCounted

const Pose := preload("../networking/pose.gd")

const MIN_HIT := 10.0
const MIN_BUMP := 1.0
const BUMP_GAP := 100
const SAME_FACE := 0.8
const CLANG := 30.0
const HOLD := 120
const MARBLE_MODE := 1
const RAGDOLL_MODE := 2
const COOKED := &"Cooked"

var bump_strength := 0.0
var hit_normal := Vector3.UP
var hit_strength := 0.0

var _until := {}
var _magnetized := false
var _impacting := false
var _cooked := false
var _shockwave := 0
var _last_collision := 0

var _player: Node
var _impact := Vector3.ZERO
var _normal := Vector3.UP
var _frame := -1
var _pending := false


func watch(player: Node) -> void:
	if player == _player:
		return

	_player = player
	_until.clear()
	_cooked = false
	_shockwave = 0

	listen(player.get("jump_vfx"), on_jump)
	listen(player.get("landing_dust_vfx"), raise.bind(Pose.LAND))
	listen(player.get("impact_trail_vfx"), raise.bind(Pose.TRAIL))
	listen(player.get("bounce_vfx"), raise.bind(Pose.BOUNCE))
	listen(player.get("sparks_vfx"), on_sparks)

	var marble = player.get("marble")

	if marble and marble.has_signal("collided"):
		marble.collided.connect(on_collided)

	var torso = player.get("ragdoll_torso")

	if torso and torso.has_signal("collided"):
		torso.collided.connect(on_torso)


func fill(pose) -> void:
	var skid = _player.get("skid")
	var field = _player.get("magnetic_field_vfx")
	var ghosts = _player.get("rig_afterimage_vfx")
	var marble = _player.get("marble")
	var trail = _player.get("marble_afterimage_vfx")
	var particles = trail.get("gpu_particles_3d") if trail else null

	if marble and not marble.is_magnetized():
		_magnetized = false

	pose.events = events()
	pose.hidden = not _player.visible
	pose.marble_trail = particles != null and particles.emitting
	pose.bump_strength = bump_strength
	pose.hit_normal = hit_normal
	pose.hit_strength = hit_strength

	pose.running = level(_player.get("running_dust_vfx"))
	pose.wall_slide = level(_player.get("wall_slide_vfx"))
	pose.bhop_wind = clampf(ratio(_player.get("b_hop_wind")), 0.0, 1.0)

	pose.skid = clampf(skid.skid_intensity, 0.0, 1.0) if skid else 0.0
	pose.twirl = skid.spin if skid else Vector3.ZERO
	pose.magnetic = field != null and field.emitting
	pose.afterimage = ghosts != null and ghosts.emitting
	pose.ramp = ghosts.ramp_index if ghosts else 0
	pose.shockwave = _shockwave


func raise(bit: int) -> void:
	var now := Time.get_ticks_msec()

	if _until.get(bit, 0) <= now:
		_until[bit] = now + HOLD


func events() -> int:
	var now := Time.get_ticks_msec()
	var mask := 0

	for bit in _until:
		if _until[bit] > now:
			mask |= bit

	return mask


func listen(effect: Object, callback: Callable) -> void:
	if effect and effect.has_signal("vfx_started"):
		effect.vfx_started.connect(callback)


func level(effect: Object) -> float:
	if not is_instance_valid(effect) or not effect.emitting:
		return 0.0

	return clampf(ratio(effect), 0.0, 1.0)


func ratio(effect: Object) -> float:
	return effect.amount_ratio if is_instance_valid(effect) and effect is Object and "amount_ratio" in effect else 0.0


func on_jump() -> void:
	var level = _player.get("jump_vfx").get("shockwave_level")

	_shockwave = level if level is int else 0
	raise(Pose.JUMP)


func on_sparks() -> void:
	raise(Pose.HIT)

	if _frame == Engine.get_physics_frames():
		commit()
	else:
		_pending = true


func hear(impact: Vector3, normal: Vector3) -> void:
	var marble = _player.get("marble")
	var now := Time.get_ticks_msec()
	var apart := now - _last_collision >= BUMP_GAP

	_last_collision = now

	if marble == null or _player.get("player_mode") != MARBLE_MODE:
		return

	var strength := impact.length()
	var fresh: bool = apart or marble.get_last_contact_normal().dot(normal) < SAME_FACE

	if not marble.is_magnetized():
		_magnetized = false

	if marble.is_magnetized() and not _magnetized:
		_magnetized = true
		bump_strength = strength
		raise(Pose.MAGNET)
	elif strength > MIN_BUMP and fresh:
		bump_strength = strength
		raise(Pose.BUMP)


func poll() -> void:
	var impacting: bool = Global.is_impacting

	if impacting and not _impacting:
		raise(Pose.CLANG)

	_impacting = impacting

	if is_instance_valid(_player):
		poll_cooked()


func poll_cooked() -> void:
	var machine = _player.get("movement_state_machine")
	var state = machine.current_state if machine else null
	var cooked: bool = state != null and state.name == COOKED

	if cooked and not _cooked:
		raise(Pose.BURST)

	_cooked = cooked


func on_torso(impact: Vector3, _normal_face: Vector3, _position: Vector3) -> void:
	var strength := impact.length()

	if _player.get("player_mode") == RAGDOLL_MODE and strength >= MIN_BUMP and strength < CLANG:
		bump_strength = strength
		raise(Pose.BUMP)


func on_collided(impact: Vector3, normal: Vector3, _position: Vector3) -> void:
	hear(impact, normal)

	if impact.length() <= MIN_HIT:
		return

	_impact = impact
	_normal = normal
	_frame = Engine.get_physics_frames()

	if _pending:
		_pending = false
		commit()


func commit() -> void:
	hit_normal = _normal
	hit_strength = clampf((_impact.length() - MIN_HIT) / 10.0, 0.0, 2.0)
