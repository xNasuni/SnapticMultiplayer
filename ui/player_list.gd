extends ScrollContainer

signal open_profile_requested(player: Dictionary)
signal kick_requested(player: Dictionary)
signal ban_requested(player: Dictionary)

const PlayerEntry := preload("./player_entry.gd")

var _list: VBoxContainer
var _host: bool
var style_button: Callable

func _init() -> void:
	horizontal_scroll_mode = SCROLL_MODE_DISABLED

	custom_minimum_size.x = 260
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	add_child(_list)

func set_host(host: bool) -> void:
	_host = host

func set_players(players: Array) -> void:
	for child in _list.get_children():
		child.queue_free()
	
	for player in players:
		var entry := PlayerEntry.new()

		entry.setup(_host, player, style_button)
		entry.open_profile_requested.connect(open_profile_requested.emit)
		entry.kick_requested.connect(kick_requested.emit)
		entry.ban_requested.connect(ban_requested.emit)
		_list.add_child(entry)