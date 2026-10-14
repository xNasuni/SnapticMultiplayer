extends Node

signal timed_out
signal message_received(id: int, text: String)
signal typing_received(id: int, typing: bool)

const Snapshot := preload("snapshot.gd")
const Log := preload("log.gd")
const Interpolator := preload("interpolator.gd")

const MAX_MESSAGE := 120
const TYPING_INTERVAL := 2.0
const TYPING_TIMEOUT := 3.0

const RATE := 0.05
const BEAT := 1.0
const TIMEOUT := 20.0
const CHANNEL := 1

var local_pose: Callable

var _running := false
var _watching := false
var _dirty := false
var _settle := false

var _send_time := 0.0
var _beat_time := 0.0
var _heard_time := 0.0

var _last = null
var _latest := {}
var _heard := {}
var _remote := {}


func start() -> void:
	_running = true
	_dirty = false
	_settle = false

	_send_time = 0.0
	_beat_time = 0.0
	_heard_time = 0.0

	_last = null
	_latest.clear()
	_heard.clear()
	_remote.clear()

	if _watching:
		return

	_watching = true
	multiplayer.peer_connected.connect(func(id: int) -> void: _heard[id] = Time.get_ticks_msec())
	multiplayer.peer_disconnected.connect(_forget)


func stop() -> void:
	_running = false

	_latest.clear()
	_heard.clear()
	_remote.clear()


func send_message(text: String) -> void:
	if not _connected():
		return

	if multiplayer.is_server():
		_relay_message(1, text)
	else:
		_message.rpc_id(1, text)


func send_typing(typing: bool) -> void:
	if not _connected():
		return

	if multiplayer.is_server():
		_relay_typing(1, typing)
	else:
		_typing.rpc_id(1, typing)


func sample(id: int, delta: float) -> Variant:
	var stream = _remote.get(id)

	return stream.sample(delta) if stream else null


func _process(delta: float) -> void:
	if not _running or not _connected():
		return

	_send_time += delta
	_beat_time += delta

	_check_timeouts(delta)

	if _send_time >= RATE:
		_send_time -= RATE
		_send()


func _connected() -> bool:
	var peer := multiplayer.multiplayer_peer

	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _check_timeouts(delta: float) -> void:
	if multiplayer.is_server():
		var now := Time.get_ticks_msec()

		for id in _heard.keys():
			if now - _heard[id] > TIMEOUT * 1000.0:
				Log.warn("dropping peer %d: no packets for %ds" % [id, int(TIMEOUT)])
				_heard.erase(id)
				multiplayer.multiplayer_peer.disconnect_peer(id)

		return

	_heard_time += delta

	if _heard_time > TIMEOUT:
		_running = false
		Log.warn("no packets from the host for %ds" % int(TIMEOUT))
		timed_out.emit()


func _send() -> void:
	var pose = local_pose.call() if local_pose.is_valid() else null
	var beat := _beat_time >= BEAT
	var now := Time.get_ticks_msec()

	if beat:
		_beat_time = 0.0

	if multiplayer.is_server():
		if pose != null:
			_note(1, now, pose)

		_broadcast(beat)
		return

	if pose != null and (beat or _settle or _moved(pose, _last)):
		_settle = _moved(pose, _last)
		_last = pose
		_state.rpc_id(1, Snapshot.pack_state(now, pose))
	elif beat:
		_state.rpc_id(1, PackedByteArray([0]))


static func _moved(pose, previous) -> bool:
	return previous == null or pose.differs(previous)


func _note(id: int, time: int, pose) -> void:
	if not _latest.has(id) or _moved(pose, _latest[id].pose):
		_dirty = true

	_latest[id] = {"time": time, "pose": pose}


func _forget(id: int) -> void:
	_heard.erase(id)
	_latest.erase(id)
	_remote.erase(id)
	_dirty = true


func _broadcast(beat: bool) -> void:
	if multiplayer.get_peers().is_empty():
		return

	var settle := _settle and not _dirty

	if not (_dirty or beat or settle):
		return

	_settle = _dirty
	_dirty = false
	_world.rpc(Snapshot.pack_world(_latest))


func _follow(id: int, time: int, pose) -> void:
	if not _remote.has(id):
		_remote[id] = Interpolator.new()

	_remote[id].push(time / 1000.0, pose)


@rpc("any_peer", "call_remote", "unreliable_ordered", CHANNEL)
func _state(bytes: PackedByteArray) -> void:
	if not multiplayer.is_server():
		return

	var id := multiplayer.get_remote_sender_id()
	var state := Snapshot.unpack_state(bytes)

	_heard[id] = Time.get_ticks_msec()

	if state.is_empty():
		return

	_note(id, state.time, state.pose)
	_follow(id, state.time, state.pose)


@rpc("authority", "call_remote", "unreliable_ordered", CHANNEL)
func _world(bytes: PackedByteArray) -> void:
	var states := Snapshot.unpack_world(bytes)
	var me := multiplayer.get_unique_id()

	_heard_time = 0.0

	for id in states:
		if id != me:
			_follow(id, states[id].time, states[id].pose)


func _relay_message(id: int, text: String) -> void:
	text = _clean(text)

	if text.is_empty():
		return

	_announce_message.rpc(id, text)
	message_received.emit(id, text)


func _relay_typing(id: int, typing: bool) -> void:
	_announce_typing.rpc(id, typing)
	typing_received.emit(id, typing)


static func _clean(text: String) -> String:
	return text.replace("\n", " ").strip_edges().left(MAX_MESSAGE)


@rpc("any_peer", "call_remote", "reliable")
func _message(text: String) -> void:
	if multiplayer.is_server():
		_relay_message(multiplayer.get_remote_sender_id(), text)

@rpc("authority", "call_remote", "reliable")
func _announce_message(id: int, text: String) -> void:
	message_received.emit(id, _clean(text))


@rpc("any_peer", "call_remote", "reliable")
func _typing(typing: bool) -> void:
	if multiplayer.is_server():
		_relay_typing(multiplayer.get_remote_sender_id(), typing)


@rpc("authority", "call_remote", "reliable")
func _announce_typing(id: int, typing: bool) -> void:
	typing_received.emit(id, typing)
