extends RefCounted

const MIN_HIT := 10.0

var jumps := 0
var landings := 0
var hits := 0
var trails := 0
var hit_normal := Vector3.UP
var hit_strength := 0.0

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

	listen(player.get("jump_vfx"), func() -> void: jumps = (jumps + 1) & 0xFF)
	listen(player.get("landing_dust_vfx"), func() -> void: landings = (landings + 1) & 0xFF)
	listen(player.get("impact_trail_vfx"), func() -> void: trails = (trails + 1) & 0xFF)
	listen(player.get("sparks_vfx"), on_sparks)

	var marble = player.get("marble")

	if marble and marble.has_signal("collided"):
		marble.collided.connect(on_collided)


func fill(pose) -> void:
	var skid = _player.get("skid")
	var field = _player.get("magnetic_field_vfx")
	var ghosts = _player.get("rig_afterimage_vfx")

	pose.jumps = jumps
	pose.landings = landings
	pose.hits = hits
	pose.trails = trails
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


func on_collided(impact: Vector3, normal: Vector3, _position: Vector3) -> void:
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
