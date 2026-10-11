extends ScrollContainer

signal join_requested(server: Dictionary)

const DIM := Color(0.5882353, 0.5882353, 1)
const ServerEntry := preload("server_entry.gd")

var style_button: Callable

var empty_text := "no servers found":
	set(value):
		empty_text = value

		if _empty:
			_empty.text = value

var _list: VBoxContainer
var _empty: Label


func _init() -> void:
	horizontal_scroll_mode = SCROLL_MODE_DISABLED

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	add_child(_list)

	_empty = Label.new()
	_empty.text = empty_text
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.add_theme_color_override("font_color", DIM)
	_list.add_child(_empty)


func set_servers(servers: Array) -> void:
	for child in _list.get_children():
		if child != _empty:
			child.queue_free()

	_empty.visible = servers.is_empty()

	for server in servers:
		var entry := ServerEntry.new()

		entry.setup(server, style_button)
		entry.join_requested.connect(join_requested.emit)
		_list.add_child(entry)
