extends RefCounted

const SOURCE := "res://addons/godotsteam/win64/"
const PLUGIN := "res://addons/godotsteam/plugin.cfg"
const ROOT := "user://godotsteam/"
const MANIFEST := "godotsteam.gdextension"
const DEBUG_LIBRARY := "libgodotsteam.windows.template_debug.x86_64.dll"
const RELEASE_LIBRARY := "libgodotsteam.windows.template_release.x86_64.dll"
const API_LIBRARY := "steam_api64.dll"

static func folder() -> String:
	var config := ConfigFile.new()

	config.load(PLUGIN)
	return "%s%s/" % [ROOT, config.get_value("plugin", "version", "unknown")]

static func load_extension() -> bool:
	var target := folder()
	if DirAccess.make_dir_recursive_absolute(target) != OK:
		return false

	for library in [DEBUG_LIBRARY, RELEASE_LIBRARY, API_LIBRARY]:
		if not _extract(library, target):
			return false
	var absolute := ProjectSettings.globalize_path(target)
	var manifest := FileAccess.open(target + MANIFEST, FileAccess.WRITE)
	if manifest == null:
		return false

	manifest.store_string("""[configuration]
entry_symbol = "godotsteam_init"
compatibility_minimum = "4.4"

[libraries]
windows.debug.x86_64 = "%s%s"
windows.release.x86_64 = "%s%s"
""" % [absolute, DEBUG_LIBRARY, absolute, RELEASE_LIBRARY])
	manifest.close()

	var status := GDExtensionManager.load_extension(target + MANIFEST)

	if status != GDExtensionManager.LOAD_STATUS_OK and status != GDExtensionManager.LOAD_STATUS_ALREADY_LOADED:
		return false

	_prune(target)
	return true

static func _prune(keep: String) -> void:
	for version in DirAccess.get_directories_at(ROOT):
		var old := ROOT + version + "/"
		if old == keep:
			continue

		for file in DirAccess.get_files_at(old):
			DirAccess.remove_absolute(old + file)

		DirAccess.remove_absolute(old)

static func _extract(library: String, folder: String) -> bool:
	var source := FileAccess.open(SOURCE + library, FileAccess.READ)
	if source == null:
		return false

	var target := folder + library
	if FileAccess.file_exists(target) and FileAccess.get_size(target) == source.get_length():
		return true
	var copy := FileAccess.open(target, FileAccess.WRITE)
	if copy == null:
		return FileAccess.file_exists(target)

	copy.store_buffer(source.get_buffer(source.get_length()))
	return true