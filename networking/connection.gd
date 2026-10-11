extends Node

signal left
signal accepted(map: String)
signal refused(reason: String)
signal players_changed(count: int)
signal roster_changed(roster: Dictionary)

const Snapshot := preload("snapshot.gd")

const PORT := 27556

var _map := ""
var _color := Color.WHITE
var _colors := {}
var _bound := false


func host(map: String, max_players: int, color: Color) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, max_players - 1)

	if err != OK:
		return err

	_map = map
	_color = color
	_colors = {1: color}

	_bind()
	multiplayer.multiplayer_peer = peer
	roster_changed.emit(_colors.duplicate())

	return OK


func join(address: String, port: int, color: Color) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)

	if err != OK:
		return err

	_color = color

	_bind()
	multiplayer.multiplayer_peer = peer

	return OK


func close() -> void:
	multiplayer.multiplayer_peer = null
	_colors.clear()


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

	multiplayer.connected_to_server.connect(func() -> void: _hello.rpc_id(1, _identity(), _color.to_html(false)))
	multiplayer.connection_failed.connect(func() -> void: refused.emit("could not connect"))
	multiplayer.server_disconnected.connect(func() -> void: left.emit())
	multiplayer.peer_disconnected.connect(_on_disconnected)


func _on_disconnected(id: int) -> void:
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
func _hello(identity: Dictionary, color: String) -> void:
	if not multiplayer.is_server():
		return

	var id := multiplayer.get_remote_sender_id()
	var mine := _identity()

	if identity != mine:
		_refuse.rpc_id(id, "different versions, the host has " + str(mine))
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return

	_colors[id] = Color.html(color) if Color.html_is_valid(color) else Color.WHITE
	_accept.rpc_id(id, _map)
	_publish()


@rpc("authority", "call_remote", "reliable")
func _accept(map: String) -> void:
	accepted.emit(map)


@rpc("authority", "call_remote", "reliable")
func _refuse(reason: String) -> void:
	refused.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _roster(wire: Dictionary) -> void:
	var roster := {}

	for id in wire:
		roster[id] = Color.html(wire[id]) if Color.html_is_valid(wire[id]) else Color.WHITE

	roster_changed.emit(roster)
