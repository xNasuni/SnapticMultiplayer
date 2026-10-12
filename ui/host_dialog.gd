extends RefCounted

signal confirmed(options: Dictionary)

const FormDialog := preload("form_dialog.gd")

const NAME_LENGTH := 32
const PASSWORD_LENGTH := 32

var _session
var _dialog
var _name: LineEdit
var _map: OptionButton
var _players: SpinBox
var _password: LineEdit
var _maps: Array


func _init(session) -> void:
	_session = session
	_maps = session.maps.keys()


func open(under: Control = null) -> void:
	if _dialog == null:
		_build()

	_reset()
	_dialog.open(under)


func _build() -> void:
	_dialog = FormDialog.new("Host Server", Vector2(560, 360))

	_name = LineEdit.new()
	_name.max_length = NAME_LENGTH

	_map = OptionButton.new()

	for map in _maps:
		_map.add_item(str(map))

	_players = SpinBox.new()
	_players.min_value = _session.MIN_PLAYERS
	_players.max_value = _session.DEFAULT_MAX
	_players.rounded = true

	_password = LineEdit.new()
	_password.max_length = PASSWORD_LENGTH
	_password.secret = true
	_password.placeholder_text = "blank for no password"

	_dialog.add_row("Server name", _name)
	_dialog.add_row("Map", _map)
	_dialog.add_row("Max players", _players)
	_dialog.add_row("Password", _password)
	_dialog.confirmed.connect(_confirm)


func _reset() -> void:
	_name.text = "%s's server" % _session.username()
	_map.select(maxi(_maps.find(_session.DEFAULT_MAP), 0))
	_players.value = _session.DEFAULT_MAX
	_password.text = ""


func _confirm() -> void:
	confirmed.emit({
		"name": _name.text,
		"map": _maps[_map.selected],
		"max_players": int(_players.value),
		"password": _password.text,
	})
