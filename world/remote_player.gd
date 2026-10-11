extends Node3D

const Pose := preload("../networking/pose.gd")
const RemoteAudio := preload("remote_audio.gd")

const RIG := "res://actors/player/art/anon_rig.blend"
const PLAYER := "res://actors/player/player.tscn"
const MATERIAL := "res://actors/player/art/anon_matcap_material.tres"
const GHOSTS := "res://features/vfx/rig_afterimage/rig_afterimage_vfx.tscn"

const FEET := "HeadFollower/HeadFollowerNoRotation/TorsoFollower/"
const JUMP_DUST := FEET + "JumpingDustVFX"
const TRAIL := FEET + "SpeedTrail"
const LAND_DUST := FEET + "FloorRayCast/FloorMarker/LandingDustVFX"
const RUN_DUST := FEET + "FloorRayCast/FloorMarker/RunningDustVFX"
const SHADOW := FEET + "FloorRayCast/FloorMarker/DropShadow"
const SPARKS := "HeadFollower/MultiSparksVFX"
const BHOP := "Characterbody/BHopWind"
const TWIRL := "HeadFollower/HeadShaker/CyclicSmearVFX"
const SKID := "HeadFollower/HeadFollowerNoRotation/SkidSparksVFX"
const MAGNET := "MarbleRigidbody/MagnetArea3D/MagneticFieldVFX"
const WALL := "anon_rig/Anon/Skeleton3D/RightHandAttachment/WallSlideVFX"
const MARBLE_TRAIL := "HeadFollower/HeadShaker/MarbleAfterimageVFX"

const HEAD_BONE := "Head_2"
const ARM_BONE := "Forearm.R"
const TORSO_BONE := "TorsoLower"
const HEAD_OFFSET := Vector3(0, 0.206, 0)
const RIG_OFFSET := Vector3(0, 0, 0.11427677)
const HEAD_HEIGHT := 1.813
const HEAD_LAYER := 2

const TWIRL_FROM := 30.0
const TWIRL_SCALE := 50.0
const TWIRL_WIND := 20.0
const MARBLE_RADIUS := 0.205
const SHADOW_BODY := 1.0
const SHADOW_MARBLE := 0.45
const SHADOW_REACH := 16.0
const FLOOR_MASK := 1

const SMOOTHING := 30.0
const AIR_TIME := 0.05
const RUN_TIME := 0.2

var _effects := true
var _material: ShaderMaterial
var _rig: Node3D
var _body: MeshInstance3D
var _head: MeshInstance3D
var _head_bone: Node3D
var _skeleton: Skeleton3D
var _tree: AnimationTree
var _floor: Node3D
var _anchor: Node3D

var _shadow: Node3D
var _jump_dust: Node
var _land_dust: Node
var _run_dust: Node
var _wall: Node
var _bhop: Node
var _magnet: Node
var _skid: Node
var _skid_material: ParticleProcessMaterial
var _sparks: Node
var _trail: Node
var _twirl: Node3D
var _twirl_material: ShaderMaterial
var _ghosts: Node
var _marble_trail: Node
var _trailing := false

var _mode: int = Pose.Mode.BODY
var _spin := Quaternion.IDENTITY
var _up := Vector3.UP
var _velocity := Vector3.ZERO
var _placed := false
var _airborne := false
var _air_blend := 0.0
var _run_blend := 0.0

var _counted := false
var _jumps := 0
var _landings := 0
var _hits := 0
var _trails := 0
var _bumps := 0
var _magnets := 0
var _clangs := 0

var _audio: RemoteAudio


func setup(color: Color, effects := true) -> void:
	var material: ShaderMaterial = load(MATERIAL).duplicate()
	var player: PackedScene = load(PLAYER)

	_effects = effects
	_material = material
	process_mode = Node.PROCESS_MODE_ALWAYS
	tint(color)

	_rig = (load(RIG) as PackedScene).instantiate()
	_rig.transform = Transform3D(Basis(Vector3.UP, PI), RIG_OFFSET)
	add_child(_rig)

	_skeleton = _rig.get_node("Anon/Skeleton3D")
	_body = _skeleton.get_node("Body")
	_body.set_surface_override_material(0, material)
	_head_bone = _skeleton.get_node(HEAD_BONE)

	for mesh: MeshInstance3D in _rig.find_children("*", "MeshInstance3D", true, false):
		if mesh != _body:
			mesh.visible = false
			mesh.layers = 0

	_add_head(player, material)
	_add_tree(player)
	_add_effects(player)

	if effects:
		_audio = RemoteAudio.new()


func _ready() -> void:
	if _tree:
		_tree.active = true


func _exit_tree() -> void:
	if _audio:
		_audio.stop()


func follow(pose, delta: float) -> void:
	if not _placed or pose.mode != _mode:
		if _placed and _audio:
			_audio.play(SFX.Name.MARBLE_POP, pose.position)

		_velocity = pose.velocity
		_placed = true
	else:
		_velocity = _velocity.lerp(pose.velocity, 1.0 - exp(-SMOOTHING * delta))

	_mode = pose.mode
	_spin = pose.spin
	_up = pose.up
	_airborne = _mode == Pose.Mode.RAGDOLL or not pose.grounded

	global_position = pose.position
	rotation.y = pose.yaw
	_body.visible = _mode != Pose.Mode.MARBLE

	_animate(Vector2(_velocity.x, _velocity.z).length(), pose.moving, delta)
	_play(pose)
	_sound(pose, delta)
	_place_head()
	_place_floor()


func _sound(pose, delta: float) -> void:
	if _audio == null:
		return

	var rolling: bool = pose.mode == Pose.Mode.MARBLE and pose.grounded

	_audio.listen(get_viewport().get_camera_3d())
	_audio.roll(global_position, _velocity.length(), rolling, delta)
	_audio.slide(global_position, pose.wall_slide > 0.0, delta)


func tint(color: Color) -> void:
	_material.set_shader_parameter("albedo", color)


func head_position() -> Vector3:
	return _anchor.global_position if _head else global_position + Vector3.UP * HEAD_HEIGHT


func _animate(speed: float, moving: bool, delta: float) -> void:
	if not _tree:
		return

	var falling := clampf((-_velocity.y + 2.0) * 10.0 / 50.0, -0.1, 2.0)
	var blend := remap(smoothstep(-0.1, 2.0, falling), 0.0, 1.0, -0.1, 2.0)

	_air_blend = move_toward(_air_blend, 1.0 if _airborne else 0.0, delta / AIR_TIME)
	_run_blend = move_toward(_run_blend, 1.0 if moving else 0.0, delta / RUN_TIME)

	_tree.set("parameters/aerial_grounded_blend/blend_amount", _air_blend)
	_tree.set("parameters/idle_running_blend/blend_amount", _run_blend)
	_tree.set("parameters/running_speed_scale/scale", maxf(1.0, speed / 10.0))
	_tree.set("parameters/rising_falling_blend/blend_amount", blend)


func _play(pose) -> void:
	run(_run_dust, pose.running)
	run(_wall, pose.wall_slide)

	if _bhop:
		_bhop.amount_ratio = pose.bhop_wind

	if _magnet:
		_magnet.emitting = pose.magnetic

	if _ghosts:
		_ghosts.emitting = pose.afterimage

	if _marble_trail and pose.marble_trail != _trailing:
		_trailing = pose.marble_trail

		if _trailing:
			_marble_trail.emit_vfx()
		else:
			_marble_trail.stop_vfx()

	if _skid:
		var facing := Vector3(-sin(pose.yaw), 0.0, -cos(pose.yaw))

		_skid.emitting = pose.skid > 0.0
		_skid.amount_ratio = pose.skid

		if _skid_material and pose.skid > 0.0:
			_skid_material.direction = Vector3.UP - facing

	if _twirl:
		var spinning: bool = pose.twirl.length() >= TWIRL_FROM

		_twirl.emitting = spinning

		if spinning:
			var axis: Vector3 = pose.twirl
			var side := Vector3.UP if absf(axis.normalized().y) < 0.99 else Vector3.RIGHT
			var size := minf(axis.length() / TWIRL_SCALE, 2.0)

			_twirl.global_basis = Basis.looking_at(axis, side).scaled(Vector3.ONE * size)

			if _twirl_material:
				_twirl_material.set_shader_parameter(&"time_scale", axis.length() / TWIRL_WIND)

	if not _counted:
		_counted = true
		_jumps = pose.jumps
		_landings = pose.landings
		_hits = pose.hits
		_trails = pose.trails
		_bumps = pose.bumps
		_magnets = pose.magnets
		_clangs = pose.clangs
		return

	if _audio and pose.bumps != _bumps:
		if _mode == Pose.Mode.RAGDOLL:
			_audio.play(SFX.Name.D_HIT_LIGHT, global_position)
		else:
			_audio.hit(global_position, pose.bump_strength, false)

	if _audio and pose.magnets != _magnets:
		_audio.hit(global_position, pose.bump_strength, true)

	if _audio and pose.clangs != _clangs:
		_audio.play(SFX.Name.D_HIT, global_position)

	_bumps = pose.bumps
	_magnets = pose.magnets
	_clangs = pose.clangs

	if pose.jumps != _jumps:
		_jumps = pose.jumps
		_jump()

	if pose.landings != _landings:
		_landings = pose.landings
		_land()

	if pose.hits != _hits:
		_hits = pose.hits
		_hit(pose.hit_normal, pose.hit_strength)

	if pose.trails != _trails:
		_trails = pose.trails

		if _trail:
			_trail.emit_vfx()


static func run(effect: Node, ratio: float) -> void:
	if effect == null:
		return

	effect.emitting = ratio > 0.0

	if ratio > 0.0:
		effect.amount_ratio = ratio


func _jump() -> void:
	var rolling := _mode == Pose.Mode.MARBLE
	var feet := global_position - (_up * MARBLE_RADIUS if rolling else Vector3.ZERO)

	if not rolling:
		_fire("jumpsquat")

	if _jump_dust:
		_jump_dust.emit_vfx({&"position": feet, &"normal": _up})

	if _audio:
		_audio.play(SFX.Name.JUMP, global_position)


func _land() -> void:
	_fire("landing")

	if _land_dust:
		_land_dust.emit_vfx()

	if _audio:
		_audio.play(SFX.Name.LAND, global_position)


func _hit(normal: Vector3, strength: float) -> void:
	if not _sparks:
		return

	_sparks.emit_vfx({
		&"global_position": global_position - normal * MARBLE_RADIUS,
		&"global_basis": Helpers.basis_from_up(normal),
		&"amount_ratio": strength,
	})


func _add_effects(player: PackedScene) -> void:
	_floor = Node3D.new()
	_floor.top_level = true
	add_child(_floor)

	_anchor = Node3D.new()
	_anchor.top_level = true
	add_child(_anchor)

	if not _effects:
		return

	var source := player.instantiate()
	var ghosts = (load(GHOSTS) as PackedScene).instantiate()

	_jump_dust = _take(source, JUMP_DUST)
	_land_dust = _take(source, LAND_DUST, _floor)
	_run_dust = _take(source, RUN_DUST, _floor)
	_shadow = _take(source, SHADOW, _floor)

	_wall = _take(source, WALL, _bone(ARM_BONE))
	_trail = _take(source, TRAIL, _bone(TORSO_BONE))
	_bhop = _take(source, BHOP)
	_magnet = _take(source, MAGNET)
	_sparks = _take(source, SPARKS)
	_skid = _take(source, SKID, _anchor)
	_twirl = _take(source, TWIRL, _anchor)
	_marble_trail = _take(source, MARBLE_TRAIL, _anchor)

	ghosts.source = _body
	ghosts.head = _head
	ghosts.interval = 0.1
	ghosts.ghost_lifetime = 0.5
	ghosts.ghost_count = 6
	add_child(ghosts)
	_ghosts = ghosts

	if _skid:
		for particles: GPUParticles3D in _skid.find_children("*", "GPUParticles3D", true, false):
			particles.process_material = particles.process_material.duplicate()
			_skid_material = particles.process_material as ParticleProcessMaterial
			break

	if _twirl:
		var wind := _twirl.get_node_or_null("RollingWind") as GPUParticles3D
		var mesh: PrimitiveMesh = (wind.draw_pass_1 as PrimitiveMesh) if wind else null

		if mesh and mesh.material is ShaderMaterial:
			mesh = mesh.duplicate() as PrimitiveMesh
			mesh.material = mesh.material.duplicate()
			wind.draw_pass_1 = mesh
			_twirl_material = mesh.material as ShaderMaterial

	source.free()


func _take(source: Node, path: String, parent: Node = null) -> Node:
	var node := source.get_node_or_null(path)

	if node == null:
		return null

	node.get_parent().remove_child(node)
	(parent if parent else self).add_child(node)

	return node


func _bone(bone: String) -> Node:
	var attachment := BoneAttachment3D.new()

	attachment.bone_name = bone
	_skeleton.add_child(attachment)

	return attachment


func _fire(shot: String) -> void:
	if _tree:
		_tree.set("parameters/%s_one_shot/request" % shot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _place_floor() -> void:
	var from := global_position + _up * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from - _up * SHADOW_REACH, FLOOR_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var width := SHADOW_MARBLE if _mode == Pose.Mode.MARBLE else SHADOW_BODY

	_floor.global_basis = Helpers.basis_from_up(_up)
	_floor.global_position = hit.position if not hit.is_empty() else global_position

	if not _shadow:
		return

	if not is_equal_approx(_shadow.box_size.x, width):
		_shadow.box_size = Vector3(width, _shadow.box_size.y, width)

	_shadow.visible = not hit.is_empty()


func _place_head() -> void:
	if not _head:
		return

	if _mode == Pose.Mode.MARBLE:
		var turned := Basis(_spin)

		_anchor.global_position = global_position
		_head.global_transform = Transform3D(
			turned * Basis(Vector3.UP, PI),
			global_position - turned * Vector3(0, HEAD_HEIGHT, 0),
		)
		return

	var top := _head_bone.global_position + _head_bone.global_basis * HEAD_OFFSET
	var basis := global_basis * Basis(Vector3.UP, PI)

	_anchor.global_position = top
	_head.global_transform = Transform3D(basis, top - Vector3(0, HEAD_HEIGHT, 0))


func _add_head(player: PackedScene, material: Material) -> void:
	var mesh = _property(player, "MarbleMesh", "mesh")

	if not mesh:
		return

	_head = MeshInstance3D.new()
	_head.mesh = mesh
	_head.material_override = material
	_head.layers = HEAD_LAYER
	_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_head.top_level = true
	add_child(_head)


func _add_tree(player: PackedScene) -> void:
	var root = _property(player, "AnimationTree", "tree_root")

	if not root:
		return

	_tree = AnimationTree.new()
	_tree.active = false
	_tree.tree_root = root.duplicate(true)
	_tree.anim_player = NodePath("../AnimationPlayer")
	_rig.add_child(_tree)


static func _property(scene: PackedScene, node: String, property: String) -> Variant:
	var state := scene.get_state()

	for i in state.get_node_count():
		if str(state.get_node_name(i)) != node:
			continue

		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == property:
				return state.get_node_property_value(i, p)

	return null
