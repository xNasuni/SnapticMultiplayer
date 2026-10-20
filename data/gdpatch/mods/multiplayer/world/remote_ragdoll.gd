extends RefCounted

const WORLD := 1
const LIMBS := 1 << 19
const SMOOTHING := 30.0
const CARRY := 1.5
const RECOVER := 1.5

var _paused := false
var _simulator: PhysicalBoneSimulator3D
var _torso: RagdollTorso
var _head: PhysicalBone3D
var _bones: Array[PhysicalBone3D] = []
var _head_offset := Transform3D.IDENTITY
var _target := Transform3D.IDENTITY
var _pose := Transform3D.IDENTITY
var _motion := {}
var _hang: Array[Transform3D] = []

func _init(simulator: PhysicalBoneSimulator3D) -> void:
	_simulator = simulator
	_torso = simulator.get_node("Torso") as RagdollTorso 
	_head = simulator.get_node("Head")

	for bone in simulator.get_children():
		if bone is PhysicalBone3D:
			bone.set_disable_scale(true)
			bone.body_offset = Transform3D.IDENTITY
			bone.collision_layer = LIMBS
			bone.collision_mask = WORLD | LIMBS
			_bones.append(bone)

func start(at: Transform3D, rig: Node3D, head_bone: String, velocity: Vector3) -> void:
	var skeleton := _simulator.get_parent() as Skeleton3D
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()

	var torso := skeleton.global_transform * skeleton.get_bone_global_rest(_torso.get_bone_id()) * _torso.body_offset
	rig.global_transform = at * torso.affine_inverse() * rig.global_transform

	_simulator.process_mode = Node.PROCESS_MODE_INHERIT
	_simulator.visible = true
	_simulator.physical_bones_start_simulation()

	var neck := skeleton.find_bone(head_bone)
	if neck >= 0:
		_head_offset = _head.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_rest(neck)

	_target = at
	_pose = at
	_hang.clear()

	for bone in _bones:
		var body := bone.get_rid()
		_hang.append(_torso.global_transform.affine_inverse() * bone.global_transform)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)

	PhysicsServer3D.body_set_mode(_torso.get_rid(), PhysicsServer3D.BODY_MODE_KINEMATIC)

func aim(at: Transform3D) -> void:
	_target = at

func head() -> Transform3D:
	var body: Transform3D = PhysicsServer3D.body_get_state(_head.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)

	return body * _head.body_offset.affine_inverse() * _head_offset

func paused(paused: bool) -> void:
	if paused == _paused:
		return

	_paused = paused

	for bone in _bones:
		if bone == _torso:
			continue

		var body := bone.get_rid()
		if paused:
			_motion[bone] = [
				PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY),
				PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY),
			]
			PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		else:
			PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
			if _motion.has(bone):
				PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, _motion[bone][0])
				PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, _motion[bone][1])
	if not paused:
		_motion.clear()

func steer(delta: float) -> void:
	if _paused:
		return

	var ease := 1.0 - exp(-SMOOTHING * delta)
	var next := Transform3D(
		Basis(Quaternion(_pose.basis.orthonormalized()).slerp(Quaternion(_target.basis.orthonormalized()), ease)),
		_pose.origin.lerp(_target.origin, ease),
	)
	var step := next.origin - _pose.origin

	if step.length() > CARRY:
		_torso.teleport_by(step)

	_pose = next

	PhysicsServer3D.body_set_state(_torso.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, _pose * _torso.body_offset)
	_recover()

func _recover() -> void:
	for i in _bones.size():
		var bone := _bones[i]
		if bone == _torso:
			continue

		var body := bone.get_rid()
		var placed: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)

		if placed.origin.distance_to(_pose.origin) > RECOVER:
			PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, _pose * _hang[i] * bone.body_offset)
			PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
			PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)

func stop() -> void:
	_paused = false
	_motion.clear()
	_simulator.physical_bones_stop_simulation()
	_simulator.process_mode = Node.PROCESS_MODE_DISABLED
	_simulator.visible = false