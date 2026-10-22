extends RefCounted

signal changed

const GAME := "snaptic_mp"
const MAX_RESULTS := 50

# i had problems with the um enums from godotsteam so idk
const DISTANCE_WORLDWIDE := 3  # k_ELobbyDistanceFilterWorldwide
const COMPARE_EQUAL := 0  # k_ELobbyComparisonEqual
const FRIEND_IMMEDIATE := 4  # k_EFriendFlagImmediate

var _steam: Object = null
var _info := {}
var _lobby_id := 0
var _found := {}
var loading := false

func setup(steam_api: Object) -> void:
	_steam = steam_api
	_steam.lobby_match_list.connect(_on_match_list)


func available() -> bool:
	return _steam != null


func announce(info: Dictionary) -> void:
	_info = info
	_apply()


func update(info: Dictionary) -> void:
	_info = info
	_apply()


func stop_announcing() -> void:
	_info = {}
	_lobby_id = 0


func on_lobby_created(lobby_id: int) -> void:
	_lobby_id = lobby_id
	_apply()


func _apply() -> void:
	if _steam == null or _lobby_id == 0 or _info.is_empty():
		return

	for key in _info:
		if key == "port":
			continue # it containing port means its lan

		_steam.setLobbyData(_lobby_id, str(key), str(_info[key]))

	_steam.setLobbyData(_lobby_id, "host", _steam.getPersonaName())
	_steam.setLobbyData(_lobby_id, "owner_id", str(_steam.getSteamID()))
	_steam.setLobbyData(_lobby_id, "game", GAME)


func listen() -> void:
	refresh()


func stop_listening() -> void:
	_found.clear()
	loading = false


func refresh() -> void:
	if _steam == null:
		return

	_found.clear()
	loading = true
	_steam.addRequestLobbyListDistanceFilter(DISTANCE_WORLDWIDE)
	_steam.addRequestLobbyListResultCountFilter(MAX_RESULTS)
	_steam.addRequestLobbyListStringFilter("game", GAME, COMPARE_EQUAL)
	_steam.requestLobbyList()


func _on_match_list(lobbies: Array) -> void:
	_found.clear()
	loading = false

	for id in lobbies:
		if id == _lobby_id:
			continue

		var title: String = _steam.getLobbyData(id, "name")

		if title.is_empty():
			continue

		_found[id] = {
			"kind": "steam",
			"id": str(id),
			"lobby_id": id,
			"owner": int(_steam.getLobbyData(id, "owner_id")),
			"address": "",
			"port": 0,
			"name": title,
			"map": _steam.getLobbyData(id, "map"),
			"host": _steam.getLobbyData(id, "host"),
			"identity": _steam.getLobbyData(id, "identity"),
			"private": _steam.getLobbyData(id, "private") == "true",
			"players": int(_steam.getLobbyData(id, "players")),
			"max_players": int(_steam.getLobbyData(id, "max_players")),
		}

	changed.emit()


func servers(friends_only := false) -> Array:
	var list: Array = []

	for entry in _found.values():
		if friends_only and not _steam.hasFriend(entry.owner, FRIEND_IMMEDIATE):
			continue

		list.append(entry)

	list.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)

	return list
