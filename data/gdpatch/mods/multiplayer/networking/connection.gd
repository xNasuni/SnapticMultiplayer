extends Node

signal left
signal accepted(map: String)
signal refused(reason: String)
signal players_changed(count: int)
signal roster_changed(players: Dictionary)
signal lobby_created(lobby_id: int)
signal host_failed(reason: String)

const SnapticBase := preload("res://gdpatch/mods/snapticbase/mod.gd")
const Snapshot := preload("snapshot.gd")
const Log := preload("log.gd")
const Utils := preload("../ui/shared/utils.gd")

const PROTOCOL := 1
const PORT := 27556
const TIMEOUT_LIMIT := 64
const TIMEOUT_MIN := 30000
const TIMEOUT_MAX := 60000
# ripped straight from the docs cause i had issues with enums
const LOBBY_PUBLIC := 2  # k_ELobbyTypePublic
const NAME_LENGTH := 32
const ENTER_SUCCESS := 1  # k_EChatRoomEnterResponseSuccess
const TURN_AWAY_DELAY := 1.0
const HELLO_TIMEOUT := 5.0
const BANNED := "You are banned"
const HOST_TAG = {"name": "Host", "color": Color.LIGHT_GREEN}

var _map := ""
var _color := Color.WHITE
var _lock := ""
var _key := ""
var _bound := false
var _lobby_id := 0
var _hosting_lobby := false
var _joining_lobby := 0
var steam_api: Object = null
var local_name := ""  # set by main before hosting or joining

var _players := {}
var _banned := {}

static func _make_player(player_name: String, color: Color, steam_id := 0) -> Dictionary:
	return {"name": _tidy(player_name), "color": color, "id": steam_id}

static func _restring(peer_id: int, player: Dictionary) -> void:
	var local_tags := [HOST_TAG] if peer_id == MultiplayerPeer.TARGET_PEER_SERVER else []

	player.name_string = Utils.player_name_tostring(player)
	player.tags_string = Utils.player_tags_tostring(player, local_tags)

func _restring_all() -> void:
	for id in _players:
		_restring(id, _players[id])

func _steam_id() -> int:
	return steam_api.getSteamID() if steam_api != null else 0


# only the host calls this. the id comes from steam's own connection, never from what a client sends
func _steam_id_of(peer_id: int) -> int:
	var peer := multiplayer.multiplayer_peer

	if peer == null or not peer.is_class("SteamMultiplayerPeer"):
		return 0

	if peer.has_method("get_steam_id_for_peer_id"): # this is the one that exists I think but the docs are so badddddddd
		return peer.get_steam_id_for_peer_id(peer_id)

	OS.crash("the get_steam_id_for_peer_id method doesn't exist for you (the host)")
	return 0


func refresh_tags() -> void:
	if _players.is_empty():
		return

	_restring_all()
	roster_changed.emit(get_roster())

func player_of(id: int) -> Dictionary:
	return _players.get(id, {})

func host(map: String, max_players: int, color: Color, password := "", use_steam := false) -> Error:
	_map = map
	_color = color
	_lock = _digest(password)
	_players = {1: _make_player(local_name, color, _steam_id() if use_steam else 0)}
	_restring_all()
	_banned.clear()

	if use_steam:
		if steam_api == null or not ClassDB.class_exists("SteamMultiplayerPeer"):
			return ERR_UNAVAILABLE

		_hosting_lobby = true
		steam_api.createLobby(LOBBY_PUBLIC, max_players)
		Log.say("creating steam lobby for %s (%d players)" % [map, max_players])

		return OK

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, max_players - 1)

	if err != OK:
		Log.warn("can't host on port %d (%s)" % [PORT, error_string(err)])
		return err

	_bind()
	multiplayer.multiplayer_peer = peer
	roster_changed.emit(get_roster())

	Log.say("hosting %s on port %d for %d players%s" % [map, PORT, max_players, " (password)" if _lock != "" else ""])

	return OK


func attach_steam(api: Object) -> void:
	steam_api = api
	steam_api.lobby_created.connect(_on_steam_lobby_created)
	steam_api.lobby_joined.connect(_on_steam_lobby_joined)


func _on_steam_lobby_created(result: int, lobby_id: int) -> void:
	if not _hosting_lobby:
		return

	_hosting_lobby = false

	if result != 1:
		host_failed.emit("steam could not create the lobby (code %d)" % result)
		return

	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: Error = peer.create_host(0)

	if err != OK:
		steam_api.leaveLobby(lobby_id)
		host_failed.emit("steam peer failed (%s)" % error_string(err))
		return

	peer.set("server_relay", true)

	_lobby_id = lobby_id
	_bind()
	multiplayer.multiplayer_peer = peer
	roster_changed.emit(get_roster())

	Log.say("hosting %s via steam lobby %d%s" % [_map, lobby_id, " (password)" if _lock != "" else ""])
	lobby_created.emit(lobby_id)


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


func join_steam(lobby_id: int, color: Color, password := "") -> Error:
	if steam_api == null or not ClassDB.class_exists("SteamMultiplayerPeer"):
		return ERR_UNAVAILABLE

	_color = color
	_key = _digest(password)
	_joining_lobby = lobby_id

	steam_api.joinLobby(lobby_id)
	Log.say("joining steam lobby %d%s" % [lobby_id, " (password)" if _key != "" else ""])

	return OK


func _on_steam_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if lobby_id != _joining_lobby:
		return

	_joining_lobby = 0

	if response != ENTER_SUCCESS:
		Log.warn("couldn't enter lobby %d (response %d)" % [lobby_id, response])
		refused.emit("couldn't enter the steam lobby")
		return

	var owner_id: int = steam_api.getLobbyOwner(lobby_id)
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: Error = peer.create_client(owner_id, 0)

	if err != OK:
		steam_api.leaveLobby(lobby_id)
		Log.warn("can't connect to the host (%s)" % error_string(err))
		refused.emit("could not connect")
		return

	peer.set("server_relay", true)

	_lobby_id = lobby_id
	_bind()
	multiplayer.multiplayer_peer = peer

	Log.say("connecting to the host through steam")


func close() -> void:
	if multiplayer.has_multiplayer_peer():
		Log.say("closing the connection")
		multiplayer.multiplayer_peer.close()

	_hosting_lobby = false
	_joining_lobby = 0

	if _lobby_id != 0 and steam_api != null:
		steam_api.leaveLobby(_lobby_id)

	_lobby_id = 0
	multiplayer.multiplayer_peer = null
	_players.clear()


static func _tidy(raw: String) -> String:
	var clean := raw.replace("\n", " ").strip_edges().left(NAME_LENGTH)

	return clean if not clean.is_empty() else "player"


static func _digest(password: String) -> String:
	return password.sha256_text() if not password.is_empty() else ""


static func _own_version() -> String:
	return str(SnapticBase.get_mod("multiplayer").get("version", ""))

static func _identity() -> Dictionary:
	return {
		"snapticbase": SnapticBase.version_family(SnapticBase.version()),
		"multiplayer": SnapticBase.version_family(_own_version()),
		"protocol": PROTOCOL,
	}

static func identity_tag() -> String:
	return JSON.stringify(_identity(), "", true)

static func compatible(theirs: Dictionary) -> bool:
	return int(theirs.get("protocol", -1)) == PROTOCOL \
		and SnapticBase.version_matches(SnapticBase.version(), str(theirs.get("snapticbase", ""))) \
		and SnapticBase.version_matches(_own_version(), str(theirs.get("multiplayer", "")))


static func describe(identity: Dictionary) -> String:
	return "snapticbase %s, multiplayer %s, protocol %s" % [
		identity.get("snapticbase", "?"), identity.get("multiplayer", "?"), identity.get("protocol", "?")]


static func clash(host: Dictionary, guest: Dictionary) -> String:
	return "different versions, the host has %s, you have %s" % [describe(host), describe(guest)]

static func mismatch(tag: String) -> String:
	var theirs = JSON.parse_string(tag)

	# remove this later
	if not theirs is Dictionary:
		return "the host runs an older version, your identity is " + describe(_identity())

	return "" if compatible(theirs) else clash(theirs, _identity())

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

	if multiplayer.is_server():
		_expect_hello(id)

func _expect_hello(id: int) -> void:
	await get_tree().create_timer(HELLO_TIMEOUT).timeout

	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().has(id) and not _players.has(id):
		Log.warn("dropping peer %d: no handshake in %ds" % [id, int(HELLO_TIMEOUT)])
		multiplayer.multiplayer_peer.disconnect_peer(id)

func _on_connected() -> void:
	Log.say("connected to the host, sending hello (protocol %d)" % PROTOCOL)
	_hello.rpc_id(1, _identity(), _color.to_html(false), _key, local_name)


func _on_failed() -> void:
	Log.warn("could not reach the host")
	refused.emit("could not connect")


func _on_server_gone() -> void:
	Log.warn("the host closed the connection")
	left.emit()


func _on_disconnected(id: int) -> void:
	Log.say("peer %d disconnected" % id)

	if _players.erase(id):
		_publish()


func _publish() -> void:
	players_changed.emit(_players.size())
	roster_changed.emit(get_roster())
	_roster.rpc(_encode(_players))

static func _encode(players: Dictionary) -> Dictionary:
	var wire := {}

	for id in players:
		var p: Dictionary = players[id]
		wire[id] = {
			"name": p.name,
			"id": p.id,
			"color": p.color.to_html(false),
		}

	return wire


static func _decode(wire: Dictionary) -> Dictionary:
	var players := {}

	for id in wire:
		var w: Dictionary = wire[id]

		players[id] = _make_player(str(w.get("name", "")), Utils.color_of(w.get("color")), int(w.get("id", 0)))

	return players

@rpc("any_peer", "call_remote", "reliable")
func _hello(identity: Dictionary, color: String, key: String, player_name: String) -> void:
	if not multiplayer.is_server():
		return

	var id := multiplayer.get_remote_sender_id()
	var mine := _identity()
	var steam_id := _steam_id_of(id)

	if steam_id != 0 and _banned.has(steam_id):
		_turn_away(id, BANNED)
		return

	if not compatible(identity):
		_turn_away(id, clash(mine, identity))
		return

	if key != _lock:
		_turn_away(id, "wrong password")
		return

	_players[id] = _make_player(player_name, Utils.color_of(color), steam_id)
	_restring(id, _players[id])
	Log.say("accepted peer %d (%d players)" % [id, _players.size()])
	_accept.rpc_id(id, _map)
	_publish()


func kick(id: int, ban := false) -> void:
	if not multiplayer.is_server() or id == MultiplayerPeer.TARGET_PEER_SERVER or not _players.has(id):
		return

	if ban:
		_banned[_players[id].id] = true

	_turn_away(id, "You were banned" if ban else "You were kicked")

	_players.erase(id)
	_publish()


func _turn_away(id: int, reason: String) -> void:
	Log.warn("turned away peer %d: %s" % [id, reason])
	_refuse.rpc_id(id, reason)
	await get_tree().create_timer(TURN_AWAY_DELAY).timeout

	if multiplayer.get_peers().has(id):
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
	_players = _decode(wire)
	_restring_all()
	roster_changed.emit(get_roster())

func get_roster() -> Dictionary:
	return _players.duplicate(true)
