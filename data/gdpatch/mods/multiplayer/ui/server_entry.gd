extends PanelContainer

const Utils := preload("./shared/utils.gd")
const Connection := preload("../networking/connection.gd")

signal join_requested(server: Dictionary)

const HEIGHT := 104
const WHITE := Color(1, 1, 1)
const LAN := Color(0.97, 0.88, 0.55)
const STEAM := Color(0.55, 0.78, 0.97)
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
	var mismatch := Connection.mismatch(server.get("identity", ""))
	var tag := "Public"
	var tag_color := PUBLIC

	if server.get("kind", "") == "lan":
		tag = "Lan"
		tag_color = LAN
	elif server.get("kind", "") == "steam":
		tag = "Private" if server.private else "Public"
		tag_color = PRIVATE if server.private else STEAM
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

	var title := Utils.rich("%s %s %s" % [
		Utils.color("[lb]%s[rb]" % tag, tag_color),
		Utils.color("(%s)" % Utils.escape(server.map), GRAY),
		Utils.color(Utils.escape(server.name), WHITE),
	], 18)

	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 2)
	top.add_child(texts)
	texts.add_child(title)
	texts.add_child(Utils.rich(Utils.color("Host: @%s" % Utils.escape(server.host), GRAY), 14))

	join.text = "Mismatch" if mismatch != "" else "Full" if full else "Join"
	join.disabled = mismatch != "" or full
	join.tooltip_text = mismatch if mismatch != "" else "this server is full" if full else "join this server"
	join.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	join.pressed.connect(join_requested.emit.bind(server))
	top.add_child(style.call(join) if style.is_valid() else join)

	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(gap)

	body.add_child(bottom)
	bottom.add_child(Utils.rich("%s %s%s%s" % [
		Utils.color("players", GRAY),
		Utils.color(str(server.players), LIGHT),
		Utils.color("/", GRAY),
		Utils.color(str(server.max_players), LIGHT),
	], 16))
