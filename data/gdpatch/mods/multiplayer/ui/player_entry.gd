extends PanelContainer

const Utils := preload("./shared/utils.gd")

signal open_profile_requested(player: Dictionary)
signal kick_requested(player: Dictionary)
signal ban_requested(player: Dictionary)

const MAX_WIDTH := 360.0
const CARD_MARGIN := 12.0

var _style: Callable
var _text: RichTextLabel

func setup(host: bool, player: Dictionary, style: Callable) -> void:
	var card := StyleBoxFlat.new()

	_style = style
	card.bg_color = Color(0.06, 0.06, 0.14, 0.55)
	card.border_color = Color(0.5882353, 0.5882353, 1, 0.35)
	card.set_border_width_all(2)
	card.set_content_margin_all(CARD_MARGIN)
	add_theme_stylebox_override("panel", card)

	var container = VBoxContainer.new()
	add_child(container)

	_text = Utils.rich("%s%s" % [player.prefix, player.name], 18)
	container.add_child(_text)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	container.add_child(buttons)

	if host and player.peer != MultiplayerPeer.TARGET_PEER_SERVER:
		_add_button(buttons, "Kick", func(): kick_requested.emit(player))
		if player.id:
			_add_button(buttons, "Ban", func(): ban_requested.emit(player))
	if player.id:
		_add_button(buttons, "Open Profile", func(): open_profile_requested.emit(player))

func _ready() -> void:
	_fit_text.call_deferred()

func _fit_text() -> void:
	var natural := float(_text.get_content_width())
	var limit := MAX_WIDTH - CARD_MARGIN * 2.0

	_text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_text.custom_minimum_size.x = ceilf(minf(natural, limit)) + 1.0

func _add_button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(callback)
	parent.add_child(_style.call(button) if _style.is_valid() else button)