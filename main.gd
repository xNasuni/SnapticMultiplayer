extends Node

const Lan := preload("networking/lan.gd")
const Players := preload("world/players.gd")
const Session := preload("networking/session.gd")
const ServersScreen := preload("ui/servers_screen.gd")
const PlayerSettings := preload("ui/player_settings.gd")
const LevelTransition := preload("ui/level_transition.gd")
const Connection := preload("networking/connection.gd")
const Replication := preload("networking/replication.gd")
const ChatBox := preload("ui/chat_box.gd")
const Log := preload("networking/log.gd")

const MENU := "res://ui/menu_screen/menu_screen_ui.tscn"

var _lan := Lan.new()
var _session := Session.new()
var _settings := PlayerSettings.new()
var _conn := Connection.new()
var _net := Replication.new()
var _players := Players.new(_net)
var _chat := ChatBox.new(_net, _players)
var _screen := ServersScreen.new(_lan, _session)
var _store: RefCounted

var _notice := ""
var _popup
var _popup_label: Label


func _ready() -> void:
	var id: String = get_meta("mod").id

	process_mode = Node.PROCESS_MODE_ALWAYS
	LevelLoader.scene_loaded.connect(_on_level_loaded)

	_store = SnapticBase.settings(id)
	_store.define("player_color", Color.WHITE)
	SnapticBase.add_settings_page(id, _settings.build)

	_conn.name = "Connection"
	_net.name = "Replication"
	_chat.name = "Chat"

	add_child(_conn)
	add_child(_net)
	add_child(_chat)
	add_child(_lan)
	add_child(_players)

	_net.local_pose = _players.local_pose

	_conn.players_changed.connect(_on_players_changed)
	_conn.roster_changed.connect(_players.set_roster)
	_conn.accepted.connect(_on_accepted)
	_conn.refused.connect(_on_refused)
	_conn.left.connect(_kicked.bind("Server closed"))
	_net.timed_out.connect(_kicked.bind("Connection timed out"))

	_screen.host_requested.connect(_host)
	_screen.join_requested.connect(_join)

	SnapticBase.on_scene(MENU, _show_notice)
	SnapticBase.add_menu_button("Servers", _screen.open)


func _host(options: Dictionary) -> void:
	if not _can_leave() or not _session.host(options):
		return

	var err := _conn.host(_session.map, _session.max_players, _color(), _session.password)

	if err != OK:
		push_error("[multiplayer] can't host: %s" % error_string(err))
		return

	_lan.announce(_announcement())
	_enter()


func _join(server: Dictionary, password: String) -> void:
	var err := _conn.join(server.address, server.port, _color(), password)

	if err != OK:
		push_error("[multiplayer] can't join: %s" % error_string(err))


func _on_refused(reason: String) -> void:
	_conn.close()
	_notice = "can't join: " + reason
	_show_notice(SnapticBase.menu)


func _on_accepted(map: String) -> void:
	if not _can_leave() or not _session.join(map):
		_conn.close()
		return

	_enter()


func _on_level_loaded(_level: Node) -> void:
	if _session.role != "offline" and LevelLoader.current_level == LevelLoader.LevelName.MENU_SCREEN_BACKGROUND:
		Log.say("leaving the session: back at the main menu")
		_leave()


func _on_players_changed(count: int) -> void:
	_session.players = count
	_lan.update(_announcement())


func _leave() -> void:
	_net.stop()
	_chat.set_active(false)
	_players.end()
	_lan.stop_announcing()
	_conn.close()
	_session.leave()


func _kicked(message: String) -> void:
	if _session.role == "offline":
		return

	Log.say("leaving the session: %s" % message.to_lower())
	_leave()
	_notice = message

	if LevelLoader.current_level == LevelLoader.LevelName.MENU_SCREEN_BACKGROUND:
		_show_notice(SnapticBase.menu)
		return

	Cursor.claim_pointer(Cursor.MouseClaim.LOADING)

	if is_instance_valid(PauseMenu.instance) and PauseMenu.instance.is_paused():
		PauseMenu.instance.resume()

	LevelLoader.load_level(LevelLoader.LevelName.MENU_SCREEN_BACKGROUND)


func _show_notice(_menu: Node) -> void:
	if _notice == "" or not is_instance_valid(SnapticBase.menu):
		return

	if _popup == null:
		_popup = SnapticBase.create_panel("Connection", Vector2(380, 130))
		_popup_label = Label.new()
		_popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_popup_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_popup_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		_popup.content.add_child(_popup_label)
		_popup.add_back("OK")

	_popup_label.text = _notice
	_notice = ""
	_popup.open()


func _announcement() -> Dictionary:
	var info := _session.announcement()

	info["port"] = Connection.PORT

	return info


func _color() -> Color:
	return _store.get_color("player_color")


func _can_leave() -> bool:
	if is_instance_valid(SnapticBase.menu):
		return true

	push_error("[multiplayer] no main menu to start from")

	return false


func _enter() -> void:
	_net.start()
	_chat.set_active(true)
	_players.begin(_color())
	_screen.dismiss()
	LevelTransition.start(SnapticBase.menu, _session.level())
