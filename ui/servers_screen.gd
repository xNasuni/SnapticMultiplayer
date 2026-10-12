extends RefCounted

signal host_requested(options: Dictionary)
signal join_requested(server: Dictionary, password: String)

const ServerList := preload("server_list.gd")
const HostDialog := preload("host_dialog.gd")
const PasswordDialog := preload("password_dialog.gd")

var _lan
var _host
var _prompt := PasswordDialog.new()
var _asking := {}
var _panel
var _list


func _init(lan, session) -> void:
	_lan = lan
	_host = HostDialog.new(session)
	_host.confirmed.connect(host_requested.emit)
	_prompt.confirmed.connect(func(password: String) -> void: join_requested.emit(_asking, password))
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
	_add_list(_panel.add_tab("Friends")).empty_text = "friends' servers need steam, but it's unimplemented rn"

	_panel.add_back()
	_panel.add_action("Refresh", _refresh).tooltip_text = "reload the server list"
	_panel.add_action("Host", _host.open.bind(_panel)).tooltip_text = "start your own server"
	_panel.closed.connect(_lan.stop_listening)


func _add_list(tab: Control):
	var list = ServerList.new()

	list.style_button = _panel.style_button
	list.join_requested.connect(_join)
	tab.add_child(list)

	return list


func _join(server: Dictionary) -> void:
	if not server.private:
		join_requested.emit(server, "")
		return

	_asking = server
	_prompt.open(_panel)


func _refresh() -> void:
	_lan.refresh()
	_show()


func _show() -> void:
	if _list:
		_list.set_servers(_lan.servers())
