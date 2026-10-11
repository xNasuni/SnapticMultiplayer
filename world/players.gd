extends Node

const Pose := preload("../networking/pose.gd")
const RemotePlayer := preload("remote_player.gd")
const LocalEffects := preload("local_effects.gd")
const ChatStack := preload("chat_stack.gd")
const ChatSound := preload("chat_sound.gd")
const RemoteAudio := preload("remote_audio.gd")

const HEAD_HEIGHT := 1.75

var _net
var _level: Node
var _effects := LocalEffects.new()
var _active := false
var _color := Color.WHITE
var _roster := {}
var _avatars := {}
var _stacks := {}
var _audio := RemoteAudio.new()


func _init(net) -> void:
	_net = net


func _ready() -> void:
	LevelLoader.scene_loaded.connect(_on_level_loaded)


func begin(color: Color) -> void:
	_active = true
	_color = color
	_tint()


func end() -> void:
	_active = false
	_color = Color.WHITE
	_tint()
	_roster.clear()
	_sync()

	for stack in _stacks.values():
		if is_instance_valid(stack):
			stack.queue_free()

	_stacks.clear()


func say(id: int, text: String) -> void:
	var stack = _stack_for(id, true)

	if stack:
		stack.set_typing(false, 0.0)
		stack.say(text, id == multiplayer.get_unique_id())
		_chime(id)


func _chime(id: int) -> void:
	var local := id == multiplayer.get_unique_id()
	var at = _local_head() if local else _avatar_head(id)

	if at == null:
		return

	_audio.listen(_level.get_viewport().get_camera_3d())
	ChatSound.play(_level, "send" if local else "receive", at, 1.0 if local else _audio.reach(at))


func typing(id: int, on: bool, timeout: float) -> void:
	if id == multiplayer.get_unique_id():
		return

	var stack = _stack_for(id, on)

	if stack:
		stack.set_typing(on, timeout)


func _stack_for(id: int, create: bool) -> Variant:
	if not _active or not is_instance_valid(_level) or not _level.is_inside_tree():
		return null

	if id != multiplayer.get_unique_id() and not _avatars.has(id):
		return null

	var stack = _stacks.get(id)

	if is_instance_valid(stack) or not create:
		return stack if is_instance_valid(stack) else null

	stack = ChatStack.new()
	stack.name = "Chat%d" % id

	_level.add_child(stack)
	_stacks[id] = stack

	return stack


func set_roster(roster: Dictionary) -> void:
	_roster = roster
	_sync()


func local_pose() -> Variant:
	if not _active or not is_instance_valid(_level):
		return null

	var player = Global.get_player()
	var body = player.get("characterbody") if player else null

	if body == null:
		return null

	var pose = Pose.new()
	var forward: Vector3 = -body.global_basis.z
	var up: Vector3 = player.get_control_up()

	pose.position = body.global_position
	pose.yaw = atan2(-forward.x, -forward.z)
	pose.up = up.normalized() if not up.is_zero_approx() else Vector3.UP
	pose.moving = not GameInput.get_move_vector().is_zero_approx()
	pose.grounded = player.is_on_floor()

	_effects.watch(player)
	_effects.fill(pose)

	match player.get("player_mode"):
		1:
			var marble = player.get("marble")

			if marble:
				pose.mode = Pose.Mode.MARBLE
				pose.position = marble.global_position
				pose.spin = marble.global_basis.orthonormalized().get_rotation_quaternion()
		2:
			pose.mode = Pose.Mode.RAGDOLL

	return pose


func _process(delta: float) -> void:
	if _active:
		_effects.poll()

	for id in _avatars:
		var avatar: Node3D = _avatars[id]
		var pose = _net.sample(id, delta)

		if pose != null and is_instance_valid(avatar) and avatar.is_inside_tree():
			avatar.visible = true
			avatar.follow(pose, delta)

	_follow_heads()


func _follow_heads() -> void:
	var me := multiplayer.get_unique_id()

	for id in _stacks.keys():
		var stack = _stacks[id]

		if not is_instance_valid(stack):
			_stacks.erase(id)
			continue

		var head = _local_head() if id == me else _avatar_head(id)

		if head != null:
			stack.global_position = head
			stack.facing = _facing_of(id, me)


func _facing_of(id: int, me: int) -> Vector3:
	var node: Node3D = null

	if id == me:
		var player = Global.get_player()
		node = player.get("characterbody") if player else null
	else:
		node = _avatars.get(id)

	if node == null:
		return Vector3.FORWARD

	var forward := -node.global_basis.z
	forward.y = 0.0

	return forward.normalized() if not forward.is_zero_approx() else Vector3.FORWARD


func _local_head() -> Variant:
	var player = Global.get_player()

	if player == null:
		return null

	var marble = player.get("marble")

	if player.get("player_mode") == 1 and marble:
		return marble.global_position

	var head = player.get_head_position()

	if head is Vector3:
		return head

	var body = player.get("characterbody")

	return body.global_position + Vector3.UP * HEAD_HEIGHT if body else null


func _avatar_head(id: int) -> Variant:
	var avatar = _avatars.get(id)

	if is_instance_valid(avatar) and avatar.visible:
		return avatar.head_position()

	return null


func _on_level_loaded(level: Node) -> void:
	_avatars.clear()
	_stacks.clear()
	_level = null

	if not _active:
		return

	await get_tree().process_frame

	if not is_instance_valid(level) or not level.is_inside_tree():
		return

	_level = level
	_tint()
	_sync()


func _sync() -> void:
	var peer := multiplayer.multiplayer_peer
	var connected := peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	var me := peer.get_unique_id() if connected else 0

	for id in _avatars.keys():
		if not _roster.has(id):
			_avatars[id].queue_free()
			_avatars.erase(id)

			if is_instance_valid(_stacks.get(id)):
				_stacks[id].queue_free()

			_stacks.erase(id)

	if not _active or not is_instance_valid(_level) or not _level.is_inside_tree():
		return

	for node in _level.get_children():
		if node is RemotePlayer and not node in _avatars.values():
			node.queue_free()

	for id in _roster:
		if id == me or _avatars.has(id):
			continue

		var avatar := RemotePlayer.new()

		avatar.name = "RemotePlayer%d" % id
		avatar.setup(_roster[id])
		avatar.visible = false

		_level.add_child(avatar)
		_avatars[id] = avatar


func _tint() -> void:
	var player = Global.get_player()
	var material = player.get("material") if player else null

	if material:
		material.set_shader_parameter("albedo", _color)
