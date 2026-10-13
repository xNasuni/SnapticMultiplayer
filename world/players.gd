extends Node

const Pose := preload("../networking/pose.gd")
const RemotePlayer := preload("remote_player.gd")
const LocalEffects := preload("local_effects.gd")
const ChatStack := preload("chat_stack.gd")
const PlayerLabel := preload("player_label.gd")
const ChatSound := preload("chat_sound.gd")
const RemoteAudio := preload("remote_audio.gd")

const HEAD_HEIGHT := 1.75
const NAME_FADE := 0.2

var _net
var _level: Node
var _effects := LocalEffects.new()
var _active := false
var _color := Color.WHITE
var _players := {}
var _avatars := {}
var _stacks := {}
var _labels := {}
var _name_alpha := 0.0
var _audio := RemoteAudio.new()

func _init(net) -> void:
	_net = net


func _ready() -> void:
	LevelLoader.scene_loaded.connect(_on_level_loaded)


func begin(color: Color) -> void:
	RemotePlayer.warm()

	_active = true
	_color = color
	_tint()


func end() -> void:
	_active = false
	_color = Color.WHITE
	_tint()
	_players.clear()
	_sync()
	_clear_labels()

	for stack in _stacks.values():
		if is_instance_valid(stack):
			stack.queue_free()

	_stacks.clear()


func say(id: int, text: String) -> void:
	var stack = _stack_for(id, true)

	if stack:
		stack.set_typing(false, 0.0)
		stack.say(text, id == _me())
		_chime(id)


func _chime(id: int) -> void:
	var local := id == _me()
	var at = _local_head() if local else _avatar_head(id)

	if at == null:
		return

	_audio.listen(_level.get_viewport().get_camera_3d())
	ChatSound.play(_level, "send" if local else "receive", at, 1.0 if local else _audio.reach(at))


func typing(id: int, on: bool, timeout: float) -> void:
	if id == _me():
		return

	var stack = _stack_for(id, on)

	if stack:
		stack.set_typing(on, timeout)


func _stack_for(id: int, create: bool) -> Variant:
	if not _active or not is_instance_valid(_level) or not _level.is_inside_tree():
		return null

	if id != _me() and not _avatars.has(id):
		return null

	var stack = _stacks.get(id)

	if is_instance_valid(stack) or not create:
		return stack if is_instance_valid(stack) else null

	stack = ChatStack.new()
	stack.name = "Chat%d" % id

	_level.add_child(stack)
	_stacks[id] = stack

	return stack


func set_roster(players: Dictionary) -> void:
	_players = players
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
	_update_labels(delta)


func _me() -> int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0


func _follow_heads() -> void:
	if _stacks.is_empty():
		return

	var me := _me()

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
	_labels.clear()
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
		if not _players.has(id):
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

	for id in _players:
		if id == me or _avatars.has(id):
			continue

		var avatar := RemotePlayer.new()

		avatar.name = "RemotePlayer%d" % id
		avatar.setup(_players[id].color)
		avatar.visible = false

		_level.add_child(avatar)
		_avatars[id] = avatar

	_sync_labels()


func _sync_labels() -> void:
	for id in _labels.keys():
		if not _players.has(id) or not is_instance_valid(_labels[id]):
			if is_instance_valid(_labels[id]):
				_labels[id].queue_free()

			_labels.erase(id)

	for id in _players:
		var label = _labels.get(id)

		if not is_instance_valid(label):
			label = PlayerLabel.new()

			_level.add_child(label)
			_labels[id] = label

		var player: Dictionary = _players[id]
		label.set_info(player)


func _clear_labels() -> void:
	for label in _labels.values():
		if is_instance_valid(label):
			label.queue_free()

	_labels.clear()


func _update_labels(delta: float) -> void:
	var held := _active and Input.is_physical_key_pressed(KEY_TAB)

	_name_alpha = move_toward(_name_alpha, 1.0 if held else 0.0, delta / NAME_FADE)

	if _labels.is_empty():
		return

	var me := _me()
	var camera: Camera3D = get_viewport().get_camera_3d()
	var alpha := smoothstep(0.0, 1.0, _name_alpha)

	for id in _labels.keys():
		var label = _labels[id]

		if not is_instance_valid(label):
			_labels.erase(id)
			continue

		var head = _local_head() if id == me else _avatar_head(id)
		var stack = _stacks.get(id)

		if head == null:
			label.set_alpha(0.0)
			if is_instance_valid(stack):
				stack.base = ChatStack.LIFT
			continue

		label.place(head, camera, delta)
		label.set_alpha(alpha)
		
		if is_instance_valid(stack):
			stack.base = ChatStack.LIFT + label.footprint() * alpha


func _tint() -> void:
	var player = Global.get_player()
	var material = player.get("material") if player else null

	if material:
		material.set_shader_parameter("albedo", _color)
