extends RefCounted

const DEFAULT_MAP := "mirraxis"
const DEFAULT_NAME := "Server"
const DEFAULT_MAX := 32
const MIN_PLAYERS := 2

var maps := {
	"mirraxis": LevelLoader.LevelName.MIRRAXIS,
	"test_room": LevelLoader.LevelName.TEST_ROOM,
	"gym": LevelLoader.LevelName.GYM,
}

var role := "offline"
var map := ""
var server_name := DEFAULT_NAME
var max_players := DEFAULT_MAX
var password := ""
var players := 0


func host(options: Dictionary = {}) -> bool:
	var map_id: String = options.get("map", DEFAULT_MAP)
	var title: String = str(options.get("name", "")).strip_edges()

	if not maps.has(map_id):
		push_error("[multiplayer] unknown map " + map_id)
		return false

	role = "host"
	map = map_id
	server_name = title if not title.is_empty() else DEFAULT_NAME
	max_players = clampi(int(options.get("max_players", DEFAULT_MAX)), MIN_PLAYERS, DEFAULT_MAX)
	password = str(options.get("password", ""))
	players = 1

	return true


func join(map_id: String) -> bool:
	if not maps.has(map_id):
		push_error("[multiplayer] the host is on a map this game doesn't have: " + map_id)
		return false

	role = "client"
	map = map_id

	return true


func leave() -> void:
	role = "offline"
	map = ""
	server_name = DEFAULT_NAME
	max_players = DEFAULT_MAX
	password = ""
	players = 0


func level() -> LevelLoader.LevelName:
	return maps[map]


func announcement() -> Dictionary:
	return {
		"name": server_name,
		"map": map,
		"host": username(),
		"private": not password.is_empty(),
		"players": players,
		"max_players": max_players,
	}


func username() -> String:
	for variable in ["USERNAME", "USER"]:
		var value := OS.get_environment(variable)

		if value != "":
			return value

	return "player"
