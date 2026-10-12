extends RefCounted

signal confirmed(password: String)

const FormDialog := preload("form_dialog.gd")

var _dialog
var _password: LineEdit


func open(under: Control = null) -> void:
	if _dialog == null:
		_build()

	_password.text = ""
	_dialog.open(under)
	_password.grab_focus()


func _build() -> void:
	_dialog = FormDialog.new("Password", Vector2(480, 170), "Join")

	_password = LineEdit.new()
	_password.secret = true
	_password.placeholder_text = "server password"

	_dialog.add_row("Password", _password)
	_dialog.confirmed.connect(func() -> void: confirmed.emit(_password.text))
