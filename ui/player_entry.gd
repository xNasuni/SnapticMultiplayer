extends PanelContainer

const Utils := preload("./shared/utils.gd")

signal open_profile_requested(player: Dictionary)
signal kick_requested(player: Dictionary)
signal ban_requested(player: Dictionary)

var _style: Callable

func setup(host: bool, player: Dictionary, style: Callable) -> void:
	var card := StyleBoxFlat.new()

	_style = style
	card.bg_color = Color(0.06, 0.06, 0.14, 0.55)
	card.border_color = Color(0.5882353, 0.5882353, 1, 0.35)
	card.set_border_width_all(2)
	card.set_content_margin_all(12)
	add_theme_stylebox_override("panel", card)

	var container = VBoxContainer.new()
	add_child(container)

	var text := Utils.rich("%s%s" % [player.prefix, player.name], 18)
	container.add_child(text)

	var buttons := HBoxContainer.new()
	container.add_child(buttons)

	if player.id:
		_add_button(buttons, "Open Profile", func(): open_profile_requested.emit(player))

	if host and player.peer != MultiplayerPeer.TARGET_PEER_SERVER:
		_add_button(buttons, "Kick", func(): kick_requested.emit(player))

		if player.id:
			_add_button(buttons, "Ban", func(): ban_requested.emit(player))

func _add_button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(callback)
	parent.add_child(_style.call(button) if _style.is_valid() else button)
