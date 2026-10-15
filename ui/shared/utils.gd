static var remote_tags := {}

static func rich(bbcode: String, size: int) -> RichTextLabel:
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


static func color(text: String, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), text]


static func escape(text: String) -> String:
	return text.replace("[", "[lb]")


static func color_of(html: Variant) -> Color:
	var s := str(html)

	return Color.html(s) if Color.html_is_valid(s) else Color.WHITE


static func player_name_tostring(player: Dictionary) -> String:
	return color("@" + escape(player.name), player.color)

static func player_tags_tostring(player: Dictionary, local_tags: Array = []) -> String:
	var result := ""
	var tags: Array = local_tags + remote_tags.get(player.id, [])

	for tag: Dictionary in tags:
		result += color("[lb]%s[rb] " % escape(tag.name), tag.color)

	return result
