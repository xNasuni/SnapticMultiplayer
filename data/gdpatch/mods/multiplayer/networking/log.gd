extends RefCounted


static func say(message: String) -> void:
	print(_tag(), message)


static func warn(message: String) -> void:
	push_warning(_tag() + message)


static func _tag() -> String:
	var now := Time.get_unix_time_from_system()

	return "[multiplayer %s.%03d] " % [Time.get_time_string_from_system(false), int(fmod(now, 1.0) * 1000.0)]
