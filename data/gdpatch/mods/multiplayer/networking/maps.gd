extends RefCounted

const BLACKLIST: Array[String] = [
	"MENU_SCREEN_BACKGROUND",
	"LOAD_TEST",
	"GYM",
	"VAPOR_GLADE",
	"MAGNET_PUZZLES",
]

static var _extra := {}
static var _hidden: Array[int] = []

static func register(id: String, level: int) -> void:
	_extra[id] = level

static func blacklist(level: int) -> void:
	if level not in _hidden:
		_hidden.append(level)

static func available() -> Dictionary:
	var maps := {}
	for key: String in LevelLoader.LevelName.keys():
		var level: int = LevelLoader.LevelName[key]
		if key not in BLACKLIST and level not in _hidden:
			maps[key.to_lower()] = level

	maps.merge(_extra, true)
	return maps