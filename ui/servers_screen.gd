extends RefCounted

signal host_requested
signal join_requested(server: Dictionary)

const ServerList := preload("server_list.gd")

var _lan
var _panel
var _list


func _init(lan) -> void:
	_lan = lan
	_lan.changed.connect(_show)


func open() -> void:
	if _panel == null:
		_build()

	_panel.open()
	_lan.listen()
	_show()


func dismiss() -> void:
	_lan.stop_listening()
	_panel.dismiss()


func _build() -> void:
	_panel = SnapticBase.create_panel("Servers", Vector2(840, 600))
	_list = _add_list(_panel.content)
	_add_list(_panel.add_tab("Friends"))

	_panel.add_back()
	_panel.add_action("Refresh", _refresh).tooltip_text = "reload the server list"
	_panel.add_action("Host", host_requested.emit).tooltip_text = "start your own server"
	_panel.closed.connect(_lan.stop_listening)


func _add_list(tab: Control):
	var list = ServerList.new()

	list.style_button = _panel.style_button
	list.join_requested.connect(join_requested.emit)
	tab.add_child(list)

	return list


func _refresh() -> void:
	_lan.refresh()
	_show()


func _show() -> void:
	if _list:
		_list.set_servers(_lan.servers())
