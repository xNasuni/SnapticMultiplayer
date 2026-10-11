extends RefCounted

const MIN_HIT := 10.0
const MIN_BUMP := 1.0
const BUMP_GAP := 100
const SAME_FACE := 0.8
const CLANG := 30.0
const MARBLE_MODE := 1
const RAGDOLL_MODE := 2

var jumps := 0
var landings := 0
var hits := 0
var trails := 0
var bumps := 0
var magnets := 0
var clangs := 0
var bump_strength := 0.0
var hit_normal := Vector3.UP
var hit_strength := 0.0

var _magnetized := false
var _impacting := false
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
	jumps = 0
	landings = 0
	hits = 0
	trails = 0
	bumps = 0
	magnets = 0
	clangs = 0

	listen(player.get("jump_vfx"), func() -> void: jumps = (jumps + 1) & 0xFF)
	listen(player.get("landing_dust_vfx"), func() -> void: landings = (landings + 1) & 0xFF)
	listen(player.get("impact_trail_vfx"), func() -> void: trails = (trails + 1) & 0xFF)
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

	pose.marble_trail = particles != null and particles.emitting

	pose.jumps = jumps
	pose.landings = landings
	pose.hits = hits
	pose.trails = trails
	pose.bumps = bumps
	pose.magnets = magnets
	pose.clangs = clangs
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


func listen(effect: Object, callback: Callable) -> void:
	if effect and effect.has_signal("vfx_started"):
		effect.vfx_started.connect(callback)


func level(effect: Object) -> float:
	if effect == null or not effect.emitting:
		return 0.0

	return clampf(ratio(effect), 0.0, 1.0)


func ratio(effect: Object) -> float:
	return effect.amount_ratio if effect and "amount_ratio" in effect else 0.0


func on_sparks() -> void:
	hits = (hits + 1) & 0xFF

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
		magnets = (magnets + 1) & 0xFF
		bump_strength = strength
	elif strength > MIN_BUMP and fresh:
		bumps = (bumps + 1) & 0xFF
		bump_strength = strength


func poll() -> void:
	var impacting: bool = Global.is_impacting

	if impacting and not _impacting:
		clangs = (clangs + 1) & 0xFF

	_impacting = impacting


func on_torso(impact: Vector3, _normal_face: Vector3, _position: Vector3) -> void:
	var strength := impact.length()

	if _player.get("player_mode") == RAGDOLL_MODE and strength >= MIN_BUMP and strength < CLANG:
		bumps = (bumps + 1) & 0xFF
		bump_strength = strength


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
