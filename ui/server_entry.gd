extends PanelContainer

signal join_requested(server: Dictionary)

const HEIGHT := 104
const WHITE := Color(1, 1, 1)
const LAN := Color(0.97, 0.88, 0.55)
const GRAY := Color(0.55, 0.55, 0.62)
const LIGHT := Color(0.80, 0.80, 0.86)
const PUBLIC := Color(0.66, 0.89, 0.70)
const PRIVATE := Color(0.95, 0.60, 0.60)


func setup(server: Dictionary, style: Callable) -> void:
	var card := StyleBoxFlat.new()
	var body := VBoxContainer.new()
	var top := HBoxContainer.new()
	var texts := VBoxContainer.new()
	var gap := Control.new()
	var bottom := HBoxContainer.new()
	var join := Button.new()
	var full: bool = server.players >= server.max_players
	var tag := "Public"
	var tag_color := PUBLIC

	if server.get("kind", "") == "lan":
		tag = "Lan"
		tag_color = LAN
	elif server.private:
		tag = "Private"
		tag_color = PRIVATE

	custom_minimum_size.y = HEIGHT

	card.bg_color = Color(0.06, 0.06, 0.14, 0.55)
	card.border_color = Color(0.5882353, 0.5882353, 1, 0.35)
	card.set_border_width_all(2)
	card.set_content_margin_all(12)
	add_theme_stylebox_override("panel", card)

	add_child(body)
	body.add_child(top)

	var title := _rich("%s %s %s" % [
		_color("[lb]%s[rb]" % tag, tag_color),
		_color("(%s)" % _escape(server.map), GRAY),
		_color(_escape(server.name), WHITE),
	], 18)

	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 2)
	top.add_child(texts)
	texts.add_child(title)
	texts.add_child(_rich(_color("Host: @%s" % _escape(server.host), GRAY), 14))

	join.text = "Full" if full else "Join"
	join.disabled = full
	join.tooltip_text = "this server is full" if full else "join this server"
	join.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	join.pressed.connect(join_requested.emit.bind(server))
	top.add_child(style.call(join) if style.is_valid() and not full else join)

	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(gap)

	body.add_child(bottom)
	bottom.add_child(_rich("%s %s%s%s" % [
		_color("players", GRAY),
		_color(str(server.players), LIGHT),
		_color("/", GRAY),
		_color(str(server.max_players), LIGHT),
	], 16))


func _rich(bbcode: String, size: int) -> RichTextLabel:
	var label := RichTextLabel.new()

	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_contents = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", size)
	label.text = bbcode

	return label


func _color(text: String, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), text]


func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
