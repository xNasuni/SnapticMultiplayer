extends Node

signal left
signal accepted(map: String)
signal refused(reason: String)
signal players_changed(count: int)
signal roster_changed(roster: Dictionary)

const Snapshot := preload("snapshot.gd")
const Log := preload("log.gd")

const PORT := 27556
const TIMEOUT_LIMIT := 64
const TIMEOUT_MIN := 30000
const TIMEOUT_MAX := 60000

var _map := ""
var _color := Color.WHITE
var _colors := {}
var _lock := ""
var _key := ""
var _bound := false


func host(map: String, max_players: int, color: Color, password := "") -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, max_players - 1)

	if err != OK:
		Log.warn("can't host on port %d (%s)" % [PORT, error_string(err)])
		return err

	_map = map
	_color = color
	_lock = _digest(password)
	_colors = {1: color}

	_bind()
	multiplayer.multiplayer_peer = peer
	roster_changed.emit(_colors.duplicate())

	Log.say("hosting %s on port %d for %d players%s" % [map, PORT, max_players, " (password)" if _lock != "" else ""])

	return OK


func join(address: String, port: int, color: Color, password := "") -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)

	if err != OK:
		Log.warn("can't connect to %s:%d (%s)" % [address, port, error_string(err)])
		return err

	_color = color
	_key = _digest(password)

	_bind()
	multiplayer.multiplayer_peer = peer

	Log.say("connecting to %s:%d%s" % [address, port, " (password)" if _key != "" else ""])

	return OK


func close() -> void:
	if multiplayer.has_multiplayer_peer():
		Log.say("closing the connection")

	multiplayer.multiplayer_peer = null
	_colors.clear()


static func _digest(password: String) -> String:
	return password.sha256_text() if not password.is_empty() else ""


func _identity() -> Dictionary:
	return {
		"snapticbase": SnapticBase.VERSION,
		"multiplayer": SnapticBase.get_mod("multiplayer").get("version", ""),
		"protocol": Snapshot.PROTOCOL,
	}


func _bind() -> void:
	if _bound:
		return

	_bound = true

	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_disconnected)


func _on_peer_connected(id: int) -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var link := peer.get_peer(id) if peer else null

	if link:
		link.set_timeout(TIMEOUT_LIMIT, TIMEOUT_MIN, TIMEOUT_MAX)

	Log.say("peer %d connected" % id)


func _on_connected() -> void:
	Log.say("connected to the host, sending hello (protocol %d)" % Snapshot.PROTOCOL)
	_hello.rpc_id(1, _identity(), _color.to_html(false), _key)


func _on_failed() -> void:
	Log.warn("could not reach the host")
	refused.emit("could not connect")


func _on_server_gone() -> void:
	Log.warn("the host closed the connection")
	left.emit()


func _on_disconnected(id: int) -> void:
	Log.say("peer %d disconnected" % id)

	if _colors.erase(id):
		_publish()


func _publish() -> void:
	var wire := {}

	for id in _colors:
		wire[id] = _colors[id].to_html(false)

	players_changed.emit(_colors.size())
	roster_changed.emit(_colors.duplicate())
	_roster.rpc(wire)


@rpc("any_peer", "call_remote", "reliable")
func _hello(identity: Dictionary, color: String, key: String) -> void:
	if not multiplayer.is_server():
		return

	var id := multiplayer.get_remote_sender_id()
	var mine := _identity()

	if identity != mine:
		_turn_away(id, "different versions, the host has " + str(mine))
		return

	if key != _lock:
		_turn_away(id, "wrong password")
		return

	_colors[id] = Color.html(color) if Color.html_is_valid(color) else Color.WHITE
	Log.say("accepted peer %d (%d players)" % [id, _colors.size()])
	_accept.rpc_id(id, _map)
	_publish()


func _turn_away(id: int, reason: String) -> void:
	Log.warn("turned away peer %d: %s" % [id, reason])
	_refuse.rpc_id(id, reason)
	multiplayer.multiplayer_peer.disconnect_peer(id)


@rpc("authority", "call_remote", "reliable")
func _accept(map: String) -> void:
	Log.say("joined, the host is on %s" % map)
	accepted.emit(map)


@rpc("authority", "call_remote", "reliable")
func _refuse(reason: String) -> void:
	Log.warn("the host refused us: %s" % reason)
	refused.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _roster(wire: Dictionary) -> void:
	var roster := {}

	for id in wire:
		roster[id] = Color.html(wire[id]) if Color.html_is_valid(wire[id]) else Color.WHITE

	roster_changed.emit(roster)
