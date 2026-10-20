extends RefCounted

signal host_requested(options: Dictionary)
signal join_requested(server: Dictionary, password: String)
signal opened
signal cancelled

const SnapticBase := preload("res://gdpatch/mods/snapticbase/mod.gd")
const ServerList := preload("server_list.gd")
const HostDialog := preload("host_dialog.gd")
const PasswordDialog := preload("password_dialog.gd")

var _lan
var _host
var _prompt := PasswordDialog.new()
var _asking := {}
var _lan_only
var _panel
var _list
var _steam
var _friends
var _refresh_button: Button
var _host_button: Button

var joining := false:
	set(value):
		joining = value
		_show()

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
	_refresh_button = _panel.add_action("Refresh", _refresh)
	_refresh_button.tooltip_text = "reload the server list"
	_host_button = _panel.add_action("Host", _host.open.bind(_panel))
	_host_button.tooltip_text = "start your own server"
	_panel.closed.connect(func() -> void:
		if joining:
			cancelled.emit()

		_lan.stop_listening()
		_list.loading = false
		_friends.loading = false
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

	if _steam == null or not _steam.available():
		_warn_lan_only()

	_lan.listen()
	if _steam:
		_steam.listen()
	_show()

func _warn_lan_only() -> void:
	if _lan_only == null:
		var label := Label.new()

		label.text = "You are not connected to Steam\nSession is in lan only"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		_lan_only = SnapticBase.create_panel("Warning", Vector2(380, 130))
		_lan_only.content.add_child(label)
		_lan_only.add_back("OK")

	_lan_only.open(_panel)


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
	if _list == null:
		return

	var steam_loading: bool = _steam != null and _steam.loading
	var scanning: bool = _lan.scanning or steam_loading
	var busy: bool = scanning or joining
	var all: Array = []

	if not scanning:
		all = _lan.servers()
		if _steam:
			all += _steam.servers()

	_list.loading = scanning
	_list.locked = busy
	_list.set_servers(all)
	_refresh_button.disabled = busy
	_host_button.disabled = joining

	if _steam:
		_friends.loading = steam_loading
		_friends.locked = busy
		_friends.set_servers([] if steam_loading else _steam.servers(true))
