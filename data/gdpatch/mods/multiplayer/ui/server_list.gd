extends ScrollContainer

signal join_requested(server: Dictionary)

const DIM := Color(0.5882353, 0.5882353, 1)
const ServerEntry := preload("server_entry.gd")
const LOADER := "res://ui/loading_circle.tscn"

var style_button: Callable

var empty_text := "no servers found":
	set(value):
		empty_text = value

		if _empty:
			_empty.text = value

var loading := false:
	set(value):
		loading = value
		_loader.visible = value
		_empty.visible = _empty.visible and not value

var locked := false:
	set(value):
		locked = value

		for entry in _entries:
			entry.lock(value)

var _list: VBoxContainer
var _empty: Label
var _loader: Control
var _entries: Array = []


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

	var circle := (load(LOADER) as PackedScene).instantiate()

	circle.custom_minimum_size = Vector2(64, 64)
	_loader = CenterContainer.new()
	_loader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loader.visible = false
	_loader.add_child(circle)

func _ready() -> void:
	get_parent().add_child.call_deferred(_loader)

func _exit_tree() -> void:
	_loader.queue_free()


func set_servers(servers: Array) -> void:
	for entry in _entries:
		entry.queue_free()

	_entries.clear()
	_empty.visible = servers.is_empty() and not loading

	for server in servers:
		var entry := ServerEntry.new()

		entry.setup(server, style_button)
		entry.lock(locked)
		entry.join_requested.connect(join_requested.emit)
		_list.add_child(entry)
		_entries.append(entry)
