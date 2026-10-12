extends RefCounted

signal confirmed

const LABEL_WIDTH := 160
const SPACING := 14

var _panel
var _form: VBoxContainer


func _init(title: String, size: Vector2, confirm := "Confirm") -> void:
	_panel = SnapticBase.create_panel(title, size)

	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", SPACING)
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.content.add_child(_form)

	_panel.add_back("Cancel")
	_panel.add_action(confirm, _confirm)


func add_row(label: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var caption := Label.new()

	caption.text = label
	caption.custom_minimum_size.x = LABEL_WIDTH
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	row.add_child(caption)
	row.add_child(control)
	_form.add_child(row)

	return control


func open(under: Control = null) -> void:
	_panel.open(under)


func close() -> void:
	_panel.close()


func _confirm() -> void:
	_panel.close()
	confirmed.emit()
