extends RefCounted

signal host_requested(options: Dictionary)
signal join_requested(server: Dictionary, password: String)
signal opened

const SnapticBase := preload("res://gdpatch/mods/snapticbase/mod.gd")
const ServerList := preload("server_list.gd")
const HostDialog := preload("host_dialog.gd")
const PasswordDialog := preload("password_dialog.gd")

var _lan
var _host
var _prompt := PasswordDialog.new()
var _asking := {}
var _panel
var _list
var _steam
var _friends

func _init(lan, session, steam = null) -> void:
	_lan = lan
	_host = HostDialog.new(session, steam)
	_host.confirmed.connect(host_requested.emit)
	_prompt.confirmed.connect(func(password: String) -> void: join_requested.emit(_asking, password))
	_lan.changed.connect(_show)
	if steam:
		_steam = steam
		_steam.changed.connect(_show)


func _build() -> void:
	_panel = SnapticBase.create_panel("Servers", Vector2(840, 600))
	_list = _add_list(_panel.content)
	_friends = _add_list(_panel.add_tab("Friends"))
	_friends.empty_text = "no friends are hosting right now"

	_panel.add_back()
	_panel.add_action("Refresh", _refresh).tooltip_text = "reload the server list"
	_panel.add_action("Host", _host.open.bind(_panel)).tooltip_text = "start your own server"
	_panel.closed.connect(func() -> void:
		_lan.stop_listening()
		if _steam:
			_steam.stop_listening())


func _add_list(tab: Control):
	var list = ServerList.new()

	list.style_button = _panel.style_button
	list.join_requested.connect(_join)
	tab.add_child(list)

	return list

func style_button(button: Button) -> Button:
	if _panel == null:
		_build()

	return _panel.style_button(button)


func open() -> void:
	if _panel == null:
		_build()

	_panel.open()
	opened.emit()
	_lan.listen()
	if _steam:
		_steam.listen()
	_show()


func dismiss() -> void:
	_lan.stop_listening()
	if _steam:
		_steam.stop_listening()
	_panel.dismiss()


func _join(server: Dictionary) -> void:
	if not server.private:
		join_requested.emit(server, "")
		return

	_asking = server
	_prompt.open(_panel)


func _refresh() -> void:
	_lan.refresh()
	if _steam:
		_steam.refresh()
	_show()


func _show() -> void:
	if _list:
		var all: Array = _lan.servers()
		if _steam:
			all += _steam.servers()
		_list.set_servers(all)
	if _friends and _steam:
		_friends.set_servers(_steam.servers(true))
