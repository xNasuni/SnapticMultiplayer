extends RefCounted

const BLACKLIST: Array[String] = [
	"MENU_SCREEN_BACKGROUND",
	"LOAD_TEST",
	"GYM",
	"VAPOR_GLADE",
	"MAGNET_PUZZLES",
]

static var _extra := {}
static var _scenes := {}
static var _hidden: Array[int] = []

static func register(id: String, scene: String) -> void:
	var key: int = _extra.get(id, LevelLoader.LevelName.size() + _scenes.size())

	_extra[id] = key
	_scenes[key] = scene

static func open(level: int) -> void:
	var scene: String = _scenes.get(level, "")
	if scene.is_empty():
		LevelLoader.load_level(level)
		return

	LevelLoader.drop_scene(LevelLoader.current_status)
	LevelLoader.current_level = level
	LevelLoader.current_status = LevelLoader.queue_scene(scene, null, Global.get_world)

static func blacklist(level: int) -> void:
	if level not in _hidden:
		_hidden.append(level)

static func level_of(id: String) -> int:
	return _extra.get(id, LevelLoader.LevelName.get(id.to_upper(), -1))

static func id_of(level: int) -> String:
	for id in _extra:
		if _extra[id] == level:
			return id
	return String(LevelLoader.LevelName.find_key(level)).to_lower()

static func available() -> Dictionary:
	var maps := {}
	for key: String in LevelLoader.LevelName.keys():
		var level: int = LevelLoader.LevelName[key]
		if key not in BLACKLIST and level not in _hidden:
			maps[key.to_lower()] = level

	maps.merge(_extra, true)
	return maps