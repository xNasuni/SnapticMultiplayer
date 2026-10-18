extends Node

signal changed

const PORT := 27555
const INTERVAL := 1.0
const EXPIRES := 4000
const MAGIC := "snaptic-multiplayer"
const TARGETS := ["255.255.255.255", "127.0.0.1"]

var _sender: PacketPeerUDP
var _listener: PacketPeerUDP
var _info := {}
var _id := ""
var _timer := INTERVAL
var _found := {}


func _ready() -> void:
	set_process(false)


func announce(info: Dictionary) -> void:
	_info = info
	_id = "%d-%d" % [Time.get_ticks_usec(), randi()]
	_timer = INTERVAL

	_sender = PacketPeerUDP.new()
	_sender.set_broadcast_enabled(true)

	set_process(true)


func update(info: Dictionary) -> void:
	_info = info
	_timer = INTERVAL


func stop_announcing() -> void:
	if _sender:
		_sender.close()
		_sender = null

	set_process(_listener != null)


func listen() -> void:
	if _listener:
		return

	var peer := PacketPeerUDP.new()
	var err := peer.bind(PORT)

	_found.clear()

	if err != OK:
		push_error("[multiplayer] can't listen for lan servers on port %d (%s)" % [PORT, error_string(err)])
		return

	_listener = peer
	set_process(true)


func stop_listening() -> void:
	if _listener:
		_listener.close()
		_listener = null

	_found.clear()
	set_process(_sender != null)


func refresh() -> void:
	stop_listening()
	listen()


func servers() -> Array:
	var list: Array = []

	for entry in _found.values():
		list.append(entry.server)

	list.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)

	return list


func _process(delta: float) -> void:
	if _sender:
		_timer += delta

		if _timer >= INTERVAL:
			_timer = 0.0
			_send()

	if _listener:
		_receive()


func _send() -> void:
	var payload := _info.duplicate()
	var bytes: PackedByteArray

	payload["magic"] = MAGIC
	payload["id"] = _id
	bytes = JSON.stringify(payload).to_utf8_buffer()

	for target in TARGETS:
		_sender.set_dest_address(target, PORT)
		_sender.put_packet(bytes)


func _receive() -> void:
	var dirty := false
	var now := Time.get_ticks_msec()

	while _listener.get_available_packet_count() > 0:
		var data = JSON.parse_string(_listener.get_packet().get_string_from_utf8())
		var address := _listener.get_packet_ip()

		if not data is Dictionary or data.get("magic") != MAGIC:
			continue

		var id := str(data.get("id", ""))

		var server := {
			"kind": "lan",
			"id": id,
			"address": address,
			"name": str(data.get("name", "Server")),
			"map": str(data.get("map", "")),
			"host": str(data.get("host", "")),
			"identity": str(data.get("identity", "")),
			"port": int(data.get("port", 0)),
			"private": bool(data.get("private", false)),
			"players": int(data.get("players", 0)),
			"max_players": int(data.get("max_players", 0)),
		}

		if not _found.has(id) or _found[id].server != server:
			dirty = true

		_found[id] = {"server": server, "seen": now}

	for id in _found.keys():
		if now - _found[id].seen > EXPIRES:
			_found.erase(id)
			dirty = true

	if dirty:
		changed.emit()
