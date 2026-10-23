extends CanvasLayer

const History := preload("chat_history.gd")
const Utils := preload("shared/utils.gd")
const Bubble := preload("../world/chat_bubble.gd")
const Connection := preload("../networking/connection.gd")

const EYE_ON := "res://game/debug/assets/gui_visibility_visible.svg"
const EYE_OFF := "res://game/debug/assets/gui_visibility_hidden.svg"

const WIDTH := 480.0
const MAX_HEIGHT := 360.0
const BOTTOM := 48.0
const INPUT_HEIGHT := 32.0
const PADDING := 8.0
const ROW_PADDING := 3.0
const FONT_SIZE := 18
const MAX_LINES := 200
const NEVER := -1000000
const OPEN_FADE := 0.1

const WHITE := Color(1, 1, 1)
const GRAY := Color(0.55, 0.55, 0.62)
const BACKGROUND := Color(0, 0, 0, 0.55)
const INPUT_BACKGROUND := Color(0, 0, 0, 0.35)

var _net
var _players
var _active := false
var _claimed := false
var _last_typing := NEVER
var _panel: Panel
var _scroll: ScrollContainer
var _column: VBoxContainer
var _input_bar: Panel
var _rows: Array[Dictionary] = []
var _open := false
var _hovered: Dictionary = {}
var _open_t := 0.0
var _peeking := false
var _store: RefCounted
var _popups := true
var _popup_t := 1.0
var _eye: Button
var _roster := {}
var _synced := false
var _peek_t := 0.0
var _follow := true
var _line: LineEdit
var _history := History.new()


func _init(net, players) -> void:
	_net = net
	_players = players
	layer = 90


func _ready() -> void:
	_net.message_received.connect(_on_message)
	_net.typing_received.connect(_on_typing)

	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override(&"panel", _box(Color.TRANSPARENT))

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override(&"separation", 0)
	_column.add_child(spacer)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.anchor_right = 1.0
	_scroll.anchor_bottom = 1.0
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.offset_bottom = -INPUT_HEIGHT
	_scroll.add_child(_column)

	var bar := _scroll.get_v_scroll_bar()
	bar.changed.connect(_stick)
	bar.value_changed.connect(func(value: float) -> void:
		_follow = value + bar.page >= bar.max_value - 2.0)

	_input_bar = Panel.new()
	var input := _input_bar
	input.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input.anchor_top = 1.0
	input.anchor_right = 1.0
	input.anchor_bottom = 1.0
	input.offset_top = -INPUT_HEIGHT
	input.add_theme_stylebox_override(&"panel", _box(INPUT_BACKGROUND))

	_line = LineEdit.new()
	_line.max_length = _net.MAX_MESSAGE
	_line.placeholder_text = "say something..."
	_line.context_menu_enabled = false

	for style in [&"normal", &"focus", &"read_only"]:
		_line.add_theme_stylebox_override(style, StyleBoxEmpty.new())

	_line.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_line.add_theme_color_override(&"font_color", WHITE)
	_line.add_theme_color_override(&"caret_color", WHITE)
	_line.add_theme_color_override(&"font_placeholder_color", GRAY)
	_line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_line.offset_left = PADDING
	_line.offset_right = -48

	_line.text_submitted.connect(_submit)
	_line.text_changed.connect(func(text: String) -> void:
		if _open and not text.is_empty():
			_announce_typing())
	_line.focus_exited.connect(_on_focus_lost)

	_eye = Button.new()
	_eye.flat = true
	_eye.toggle_mode = true
	_eye.focus_mode = Control.FOCUS_NONE
	_eye.tooltip_text = "show the chat when a message arrives"
	_eye.expand_icon = true
	_eye.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eye.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	_eye.custom_minimum_size = Vector2(48, 48)
	_eye.anchor_left = 1.0
	_eye.anchor_top = 1.0
	_eye.anchor_right = 1.0
	_eye.anchor_bottom = 1.0
	_eye.offset_left = -48
	_eye.offset_top = -40
	_eye.offset_bottom = 8
	_eye.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_eye.grow_vertical = Control.GROW_DIRECTION_BEGIN

	for style_name in [&"normal", &"pressed", &"disabled", &"focus"]:
		_eye.add_theme_stylebox_override(style_name, _eye_box(Color.TRANSPARENT))

	for style_name in [&"hover", &"hover_pressed"]:
		_eye.add_theme_stylebox_override(style_name, _eye_box(Color(1, 1, 1, 0.1)))

	_eye.toggled.connect(_on_eye_toggled)

	input.add_child(_line)
	input.add_child(_eye)
	_show_eye(_popups)
	_panel.add_child(_scroll)
	_panel.add_child(input)


func bind(store: RefCounted) -> void:
	_store = store
	_popups = store.get_bool("chat_popups")
	_popup_t = 1.0 if _popups else 0.0


func _show_eye(shown: bool) -> void:
	_popups = shown
	_eye.set_pressed_no_signal(shown)
	_eye.icon = load(EYE_ON if shown else EYE_OFF)

	# my ocddddd
	_eye.offset_top = -40 if shown else -46
	_eye.offset_bottom = 8 if shown else 2


func _on_eye_toggled(shown: bool) -> void:
	_show_eye(shown)

	if _store:
		_store.set_value("chat_popups", shown)


func _exit_tree() -> void:
	close()
	if _panel != null:
		_panel.queue_free()

func _process(delta: float) -> void:
	_open_t = move_toward(_open_t, 1.0 if _open else 0.0, delta / OPEN_FADE)
	var open_alpha := smoothstep(0.0, 1.0, _open_t)

	if _peeking and (_open or not Input.is_key_pressed(KEY_Z)):
		_peeking = false

	_peek_t = move_toward(_peek_t, 1.0 if _peeking else 0.0, delta / OPEN_FADE)
	var peek_all := smoothstep(0.0, 1.0, _peek_t)

	_popup_t = move_toward(_popup_t, 1.0 if _popups else 0.0, delta / OPEN_FADE)
	var popup_alpha := smoothstep(0.0, 1.0, _popup_t)

	_panel.get_theme_stylebox(&"panel").bg_color = Color(BACKGROUND, BACKGROUND.a * open_alpha)
	_input_bar.modulate.a = open_alpha
	_input_bar.visible = _open or _open_t > 0.0
	_scroll.get_v_scroll_bar().modulate.a = open_alpha
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS if _open else Control.MOUSE_FILTER_IGNORE

	if _open and not _hovered.is_empty():
		_tip(_hovered)

	# backwards
	for i in range(_rows.size() - 1, -1, -1):
		var entry := _rows[i]
		var row: PanelContainer = entry.row

		entry.age += delta

		var peek := minf(entry.age / Bubble.FADE_TIME, minf(1.0, (entry.life - entry.age) / Bubble.FADE_TIME))
		peek = smoothstep(0.0, 1.0, clampf(peek, 0.0, 1.0)) * popup_alpha

		row.visible = _open or (_popup_t > 0.0 and entry.age < entry.life) or _peek_t > 0.0
		row.mouse_filter = Control.MOUSE_FILTER_PASS if _open else Control.MOUSE_FILTER_IGNORE
		row.modulate.a = maxf(maxf(peek, open_alpha), peek_all)
		row.get_theme_stylebox(&"panel").bg_color = Color(BACKGROUND, BACKGROUND.a * (1.0 - open_alpha))


func _tip(entry: Dictionary) -> void:
	entry.row.tooltip_text = "%s (%s)" % [entry.clock, _ago(int(Time.get_unix_time_from_system() - entry.sent))]
static func _ago(seconds: int) -> String:
	if seconds < 5:
		return "just now"
	if seconds < 60:
		return "%ds ago" % seconds
	if seconds < 3600:
		return "%dm ago" % (seconds / 60)
	if seconds < 86400:
		return "%dh ago" % (seconds / 3600)

	return "%dd ago" % (seconds / 86400)


func _stick() -> void:
	if _follow:
		var bar := _scroll.get_v_scroll_bar()
		_scroll.scroll_vertical = int(bar.max_value)


func set_active(active: bool) -> void:
	_active = active

	if not active:
		close()
		_clear()


func _clear() -> void:
	for entry in _rows:
		entry.row.queue_free()

	_rows.clear()
	_hovered = {}
	_roster = {}
	_synced = false
	_peeking = false


func open() -> void:
	var ui := Global.get_ui_world()

	if ui == null:
		return

	if not Cursor.has_claim(Cursor.MouseClaim.DIALOGUE):
		Cursor.claim_pointer(Cursor.MouseClaim.DIALOGUE)
		_claimed = true

	LookInput.set_process_input(false)

	_mount(ui)
	_open = true
	_input_bar.visible = true
	_follow = true
	_stick()
	_history.reset()
	_line.clear()
	_focus_line()

func _mount(ui: Node) -> void:
	var holder := ui.get_parent() as Control
	var window := holder.size if holder != null else ui.get_viewport().get_visible_rect().size
	var scale_factor := ui.get_viewport().get_visible_rect().size.y / window.y
	var height := minf(window.y * 0.5, MAX_HEIGHT)

	if _panel.get_parent() != ui:
		if _panel.get_parent() != null:
			_panel.get_parent().remove_child(_panel)
		ui.add_child(_panel)

	_panel.scale = Vector2.ONE * scale_factor
	_panel.size = Vector2(WIDTH, height)
	_panel.position = Vector2(0.0, ui.get_viewport().get_visible_rect().size.y - (BOTTOM + height) * scale_factor)


func close() -> void:
	if _panel == null:
		return

	if _open:
		LookInput.set_process_input(true)

		if Time.get_ticks_msec() - _last_typing < _net.TYPING_TIMEOUT * 1000.0:
			_net.send_typing(false)

	_last_typing = NEVER
	_open = false
	_peeking = false
	_follow = true
	if _line.is_inside_tree():
		_line.release_focus()

	_line.clear()

	if _claimed:
		_claimed = false
		Cursor.release_pointer(Cursor.MouseClaim.DIALOGUE)


func _input(event: InputEvent) -> void:
	if not _open or not _line.has_focus() or not event is InputEventKey or not event.pressed:
		return

	if event.is_action_pressed(&"pause") or event.keycode == KEY_ESCAPE:
		close()
	elif event.keycode == KEY_UP:
		_recall(_history.older(_line.text))
	elif event.keycode == KEY_DOWN:
		_recall(_history.newer(_line.text))
	else:
		return

	get_viewport().set_input_as_handled()


func _announce_typing() -> void:
	var now := Time.get_ticks_msec()

	if now - _last_typing >= _net.TYPING_INTERVAL * 1000.0:
		_last_typing = now
		_net.send_typing(true)



func _focus_line() -> void:
	await get_tree().process_frame

	if _open:
		_line.grab_focus()
		_line.edit()


func _on_focus_lost() -> void:
	if _open:
		close()


func _recall(text: String) -> void:
	_line.deselect()
	_line.text = text
	_line.caret_column = text.length()


func _unhandled_input(event: InputEvent) -> void:
	if not _active or _open or not _can_open():
		return

	if not event is InputEventKey or not event.pressed:
		return

	if event.keycode in [KEY_T, KEY_ENTER] and not event.echo:
		open()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_Z:
		peek()
		get_viewport().set_input_as_handled()


func peek() -> void:
	var ui := Global.get_ui_world()
	if ui != null:
		_mount(ui)

	_peeking = true


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
		_history.add(text)
		_net.send_message(text)


func _on_message(id: int, text: String) -> void:
	if not _active:
		return

	_players.say(id, text)
	_append(id, text)


func on_roster(roster: Dictionary) -> void:
	if _active and _synced:
		for id in roster:
			if not _roster.has(id):
				_announce(roster[id], Utils.color("joined the server", Connection.HOST_TAG.color))
		for id in _roster:
			if not roster.has(id):
				_announce(_roster[id], Utils.color("left the server", GRAY))
	_roster = roster.duplicate()
	_synced = true

func _announce(player: Dictionary, status: String) -> void:
	_add_row("%s%s %s" % [player.tags_string, player.name_string, status], false)


func _append(id: int, text: String) -> void:
	var player: Dictionary = _players._players.get(id, {})
	var name_string: String = player.get("name_string", Utils.color("@?", GRAY))
	var body := "%s%s%s %s" % [player.get("tags_string", ""), name_string, Utils.color(":", GRAY), Utils.color(Utils.escape(text), WHITE)]
	_add_row(body, text.length() > Bubble.LONG_LENGTH)

func _add_row(body: String, long: bool) -> void:
	var ui := Global.get_ui_world()
	if ui != null:
		_mount(ui)

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"normal_font_size", FONT_SIZE)
	label.add_theme_constant_override(&"line_separation", 0)
	label.add_theme_color_override(&"default_color", WHITE)

	for style_name in [&"normal", &"focus"]:
		label.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())

	label.text = body

	var style := _box(Color.TRANSPARENT)
	style.content_margin_left = ROW_PADDING
	style.content_margin_right = ROW_PADDING

	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.modulate.a = 0.0
	row.add_theme_stylebox_override(&"panel", style)
	row.add_child(label)

	_column.add_child(row)

	var now := Time.get_datetime_dict_from_system()
	var clock := "%d:%02d:%02d %s" % [(now.hour + 11) % 12 + 1, now.minute, now.second, "PM" if now.hour >= 12 else "AM"]
	var entry := {"row": row, "clock": clock, "sent": Time.get_unix_time_from_system(), "age": 0.0, "life": Bubble.LONG_LIFETIME if long else Bubble.LIFETIME}

	row.mouse_entered.connect(func() -> void: _hovered = entry)
	row.mouse_exited.connect(func() -> void:
		if is_same(_hovered, entry):
			_hovered = {})
	_tip(entry)
	_rows.append(entry)

	if _rows.size() > MAX_LINES:
		var old: Dictionary = _rows.pop_front()
		if is_same(_hovered, old):
			_hovered = {}

		old.row.queue_free()
	if not _open:
		_follow = true


static func _eye_box(color: Color) -> StyleBoxFlat:
	var style := _box(color)
	style.set_content_margin_all(6.0)

	return style


static func _box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color

	return style


func _on_typing(id: int, typing: bool) -> void:
	if _active:
		_players.typing(id, typing, _net.TYPING_TIMEOUT)
