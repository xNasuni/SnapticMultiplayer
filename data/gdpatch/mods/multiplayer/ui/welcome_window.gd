extends RefCounted

const SCENE := "uid://dw1umflcpgo0o"
const PAGE := "ShakeContainer/Panel/MarginContainer/MarginContainer/ScrollContainer/VBoxContainer/"
const BAR := "ShakeContainer/Panel/TopMarginContainer/TopBar/MoveButton/HBoxContainer/"

const TITLE := "Welcome to Multiplayer!"
const HEADING := "Welcome!"
const BODY := "[center][b][rainbow freq=0.2 sat=.8 val=0.8 speed=1.1]You made it in![/rainbow][/b][/center]

Everyone in this server can see you, so [wave amp=20.0 freq=-5.0 connected=1][b]say hi![/b][/wave]

Press [b][color=light_blue]T[/color][/b] to send messages, hold [b][color=light_blue]Tab[/color][/b] to see everyone's names, and open the pause menu to see the playerlist.

You can [b][color=light_blue][i]toggle mouse capture[/i][/color][/b] to click windows like this using [action=pointer_toggle].

Have fun!
-[wave amp=30.0 freq=-3.0 connected=1][b][rainbow freq=0.9 sat=0.6 val=0.9 speed=1.5]@mia/xNasuni[/rainbow][/b][/wave]"

var _window
func open(pause_window: Control) -> void:
	if is_instance_valid(_window):
		_window.visible = true
		return

	var windows := pause_window.get_parent().get_parent()
	_window = (load(SCENE) as PackedScene).instantiate()
	_window.title_text = TITLE
	windows.add_child(_window)
	windows.move_child(_window, pause_window.get_parent().get_index())
	_window.z_index = 0 # please work please work

	var page = _window.get_node(PAGE)
	_window.get_node(BAR + "Title").text = TITLE
	page.get_node("WelcomeLabel").text = HEADING
	page.get_node("BodyLabel").text1 = BODY
	page.get_node("Control").visible = false