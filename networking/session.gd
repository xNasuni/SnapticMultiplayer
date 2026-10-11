extends RefCounted

const DEFAULT_MAP := "test_room"
const DEFAULT_NAME := "Server"
const DEFAULT_MAX := 32

var maps := {
	"test_room": LevelLoader.LevelName.TEST_ROOM,
	"mirraxis": LevelLoader.LevelName.MIRRAXIS,
}

var role := "offline"
var map := ""
var server_name := DEFAULT_NAME
var max_players := DEFAULT_MAX
var players := 0


func host(map_id: String = DEFAULT_MAP) -> bool:
	if not maps.has(map_id):
		push_error("[multiplayer] unknown map " + map_id)
		return false

	role = "host"
	map = map_id
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
	players = 0


func level() -> LevelLoader.LevelName:
	return maps[map]


func announcement() -> Dictionary:
	return {
		"name": server_name,
		"map": map,
		"host": username(),
		"private": false,
		"players": players,
		"max_players": max_players,
	}


func username() -> String:
	for variable in ["USERNAME", "USER"]:
		var value := OS.get_environment(variable)

		if value != "":
			return value

	return "player"
