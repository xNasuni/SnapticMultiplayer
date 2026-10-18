extends CanvasLayer

const Bubble := preload("../world/chat_bubble.gd")

const SIZE := Vector2(480, 48)
const BOTTOM := 48.0
const FONT_SIZE := 22
const NEVER := -1000000

var _net
var _players
var _active := false
var _claimed := false
var _last_typing := NEVER
var _panel: Panel
var _line: LineEdit


func _init(net, players) -> void:
	_net = net
	_players = players
	layer = 90


func _ready() -> void:
	_net.message_received.connect(_on_message)
	_net.typing_received.connect(_on_typing)

	_panel = Bubble.panel("remote")
	_panel.visible = false
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -SIZE.x * 0.5
	_panel.offset_right = SIZE.x * 0.5
	_panel.offset_top = -BOTTOM - SIZE.y
	_panel.offset_bottom = -BOTTOM

	_line = LineEdit.new()
	_line.max_length = _net.MAX_MESSAGE
	_line.placeholder_text = "say something..."
	_line.context_menu_enabled = false
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for style in [&"normal", &"focus", &"read_only"]:
		_line.add_theme_stylebox_override(style, StyleBoxEmpty.new())

	_line.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_line.add_theme_color_override(&"font_color", Bubble.TEXT["remote"])
	_line.add_theme_color_override(&"caret_color", Bubble.TEXT["remote"])
	_line.add_theme_color_override(&"font_placeholder_color", Bubble.TEXT["remote"].lerp(Bubble.BACKGROUNDS["remote"], 0.5))
	_line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_line.offset_left = SIZE.y * 0.5
	_line.offset_right = -SIZE.y * 0.5

	_panel.add_child(_line)

	var root := Control.new()

	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_panel)
	add_child(root)


func _exit_tree() -> void:
	close()


func set_active(active: bool) -> void:
	_active = active

	if not active:
		close()


func open() -> void:
	var root := get_tree().root

	root.move_child(get_parent(), root.get_child_count() - 1)

	if not Cursor.has_claim(Cursor.MouseClaim.DIALOGUE):
		Cursor.claim_pointer(Cursor.MouseClaim.DIALOGUE)
		_claimed = true

	_panel.visible = true
	_line.clear()
	_line.grab_focus()


func close() -> void:
	if _panel == null:
		return

	if _panel.visible and Time.get_ticks_msec() - _last_typing < _net.TYPING_TIMEOUT * 1000.0:
		_net.send_typing(false)

	_last_typing = NEVER
	_panel.visible = false
	_line.release_focus()
	_line.clear()

	if _claimed:
		_claimed = false
		Cursor.release_pointer(Cursor.MouseClaim.DIALOGUE)


func _input(event: InputEvent) -> void:
	if not _active or not _panel.visible or not event is InputEventKey:
		return

	get_viewport().set_input_as_handled()

	if event.pressed:
		_press(event)


func _press(event: InputEventKey) -> void:
	var before := _line.text

	if event.is_action_pressed(&"pause") or event.keycode == KEY_ESCAPE:
		close()
	elif event.is_command_or_control_pressed():
		_shortcut(event.keycode, event.shift_pressed)
	else:
		_edit(event)

	if _panel.visible and _line.text != before:
		_announce_typing()


func _announce_typing() -> void:
	var now := Time.get_ticks_msec()

	if now - _last_typing >= _net.TYPING_INTERVAL * 1000.0:
		_last_typing = now
		_net.send_typing(true)


func _shortcut(keycode: Key, select: bool) -> void:
	match keycode:
		KEY_A:
			_line.select_all()
		KEY_C:
			_copy()
		KEY_X:
			_copy()
			_erase()
		KEY_V:
			_insert(DisplayServer.clipboard_get().replace("\n", " "))
		KEY_LEFT:
			_move(_word_left(), select)
		KEY_RIGHT:
			_move(_word_right(), select)
		KEY_HOME:
			_move(0, select)
		KEY_END:
			_move(_line.text.length(), select)
		KEY_BACKSPACE:
			_erase_to(_word_left())
		KEY_DELETE:
			_erase_to(_word_right())

func _is_word(column: int) -> bool:
	var character := _line.text[column]

	return character.to_lower() != character.to_upper() or character.is_valid_int() or character == "_"

func _word_left() -> int:
	var column := _line.caret_column

	while column > 0 and not _is_word(column - 1):
		column -= 1
	while column > 0 and _is_word(column - 1):
		column -= 1

	return column

func _word_right() -> int:
	var column := _line.caret_column
	var length := _line.text.length()

	while column < length and _is_word(column):
		column += 1
	while column < length and not _is_word(column):
		column += 1

	return column

func _erase_to(column: int) -> void:
	if _erase():
		return

	var caret := _line.caret_column

	_line.delete_text(mini(caret, column), maxi(caret, column))
	_line.caret_column = mini(caret, column)


func _edit(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_submit(_line.text)
		KEY_BACKSPACE:
			if not _erase():
				_line.delete_char_at_caret()
		KEY_DELETE:
			if not _erase():
				_line.delete_text(_line.caret_column, _line.caret_column + 1)
		KEY_LEFT:
			if _line.has_selection() and not event.shift_pressed:
				_move(_line.get_selection_from_column())
			else:
				_move(maxi(_line.caret_column - 1, 0), event.shift_pressed)
		KEY_RIGHT:
			if _line.has_selection() and not event.shift_pressed:
				_move(_line.get_selection_to_column())
			else:
				_move(mini(_line.caret_column + 1, _line.text.length()), event.shift_pressed)
		KEY_HOME:
			_move(0, event.shift_pressed)
		KEY_END:
			_move(_line.text.length(), event.shift_pressed)
		_:
			if event.unicode >= 32 and event.unicode != 127:
				_insert(String.chr(event.unicode))


func _copy() -> void:
	if _line.has_selection():
		DisplayServer.clipboard_set(_line.get_selected_text())


func _erase() -> bool:
	if not _line.has_selection():
		return false

	var from := _line.get_selection_from_column()
	var to := _line.get_selection_to_column()

	_line.deselect()
	_line.delete_text(from, to)
	_line.caret_column = from

	return true


func _insert(text: String) -> void:
	_erase()
	_line.insert_text_at_caret(text)


func _move(column: int, select := false) -> void:
	if not select:
		_line.deselect()
		_line.caret_column = column
		return

	var anchor := _line.caret_column

	if _line.has_selection():
		var from := _line.get_selection_from_column()
		var to := _line.get_selection_to_column()

		anchor = from if _line.caret_column == to else to

	_line.caret_column = column
	_line.select(mini(anchor, column), maxi(anchor, column))
	_line.caret_column = column


func _unhandled_input(event: InputEvent) -> void:
	if not _active or _panel.visible or not _can_open():
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		open()
		get_viewport().set_input_as_handled()


func _can_open() -> bool:
	if LevelLoader.is_loading or Cursor.get_mode() == Cursor.Mode.MENU or GameInput.is_typing():
		return false

	var hovered := get_viewport().gui_get_hovered_control()

	if Cursor.is_pointer_mode() and (hovered is LineEdit or hovered is TextEdit):
		return false

	return not (is_instance_valid(PauseMenu.instance) and PauseMenu.instance.is_paused())


func _submit(text: String) -> void:
	_last_typing = NEVER
	close()

	if not text.strip_edges().is_empty():
		_net.send_message(text)


func _on_message(id: int, text: String) -> void:
	if _active:
		_players.say(id, text)


func _on_typing(id: int, typing: bool) -> void:
	if _active:
		_players.typing(id, typing, _net.TYPING_TIMEOUT)
