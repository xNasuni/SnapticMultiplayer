extends Node

const SnapticBase := preload("res://gdpatch/mods/snapticbase/mod.gd")
const Utils := preload("ui/shared/utils.gd")

const Lan := preload("networking/lan.gd")
const SteamLobby := preload("networking/steam_lobby.gd")
const SteamLibrary := preload("networking/steam_library.gd")
const Players := preload("world/players.gd")
const Session := preload("networking/session.gd")
const ServersScreen := preload("ui/servers_screen.gd")
const PlayerSettings := preload("ui/player_settings.gd")
const PlayerList := preload("ui/player_list.gd")
const LevelTransition := preload("ui/level_transition.gd")
const Connection := preload("networking/connection.gd")
const RemoteResources := preload("networking/remote_resources.gd")
const WelcomeWindow := preload("ui/welcome_window.gd")
const Replication := preload("networking/replication.gd")
const ChatBox := preload("ui/chat_box.gd")
const Maps := preload("networking/maps.gd")
const Log := preload("networking/log.gd")
const MenuPanel := preload("res://gdpatch/mods/snapticbase/menu_panel.gd")

const MENU := "res://ui/menu_screen/menu_screen_ui.tscn"
const PAUSE_MENU := "res://game/pause_menu/pause_menu.tscn"

const STEAM_APP_ID := 5273300
const STEAM_MAX_PLAYERS := 24
const LOBBY_TIMEOUT := 10.0
const JOIN_TIMEOUT := 20.0

# i had problems with the um enums from godotsteam so idk
const CFG_P2P_ICE_ENABLE := 104
const CFG_SCOPE_GLOBAL := 1
const CFG_TYPE_INT32 := 1

var _steam_ok := false
var steam_api: Object = null
var _steam_lobby := SteamLobby.new()
var _use_steam := false
var _pending_host := false
var _entering := false
var _join_attempt := 0
var _behind := false
var _host_attempt := 0

var _lan := Lan.new()
var _session := Session.new()
var _settings := PlayerSettings.new()
var _conn := Connection.new()
var _resources := RemoteResources.new()
var _welcome := WelcomeWindow.new()
var _net := Replication.new()
var _players := Players.new(_net)
var _chat := ChatBox.new(_net, _players)
var _screen := ServersScreen.new(_lan, _session, _steam_lobby)
var _store: RefCounted

var _notice := ""
var _notice_title := "Connection"
var _popup
var _popup_label: Label

var _player_list

func _ready() -> void:
	var mod := SnapticBase.register("multiplayer", get_script().resource_path.get_base_dir())
	var id: String = mod.id

	process_mode = Node.PROCESS_MODE_ALWAYS
	LevelLoader.scene_loaded.connect(_on_level_loaded)

	_store = SnapticBase.settings(id)
	_store.define("player_color", Color.WHITE)
	_store.define("seen_first_time_popup", false)
	SnapticBase.add_settings_page(id, _settings.build)

	_conn.name = "Connection"
	_net.name = "Replication"
	_chat.name = "Chat"

	add_child(_conn)
	add_child(_net)
	add_child(_chat)
	add_child(_lan)
	add_child(_players)
	add_child(_resources)

	_resources.is_mod_outdated(mod.version, func(outdated: bool, new_ver: String) -> void:
		#there shouldn't be an incentive to stay on a lower version so a warning on startup should be ok
		if outdated:
			Log.say("multiplayer mod is not up to date")
			_notice_title = "Multiplayer"
			_notice = "A new version is available. (+v%s)" % [new_ver]
			_show_notice(SnapticBase.menu)
		else:
			Log.say("multiplayer mod is up to date"))

	_net.local_pose = _players.local_pose

	_conn.players_changed.connect(_on_players_changed)
	_conn.roster_changed.connect(_players.set_roster)
	_conn.roster_changed.connect(_net.set_roster)
	_conn.roster_changed.connect(func(_roster: Dictionary) -> void: _refresh_player_list())
	_resources.changed.connect(_conn.refresh_tags)
	_conn.accepted.connect(_on_accepted)
	_conn.map_changed.connect(_on_map_changed)
	_conn.kicked.connect(_net.explode)
	LevelLoader.queue_emptied.connect(_catch_up)
	_conn.refused.connect(_on_refused)
	_conn.left.connect(_kicked.bind("Server closed"))
	_net.timed_out.connect(_kicked.bind("Connection timed out"))

	_screen.host_requested.connect(_host)
	_screen.join_requested.connect(_join)
	_screen.cancelled.connect(_cancel_join)

	_players.pause_texture = SnapticBase.load_asset(mod.dir + "assets/textures/paused.png")

	SnapticBase.on_scene(MENU, _show_notice)
	SnapticBase.on_scene(PAUSE_MENU, _on_pause_menu)
	SnapticBase.add_menu_button("Servers", _screen.open)

	_init_steam()


func _init_steam() -> void:
	if not Engine.has_singleton("Steam") and not SteamLibrary.load_extension():
		Log.warn("couldn't extract or load the bundled steam api (%s), lan only" % ProjectSettings.globalize_path(SteamLibrary.folder()))
		return

	if not Engine.has_singleton("Steam"):
		Log.say("steam not found, lan only")
		return

	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		Log.say("SteamMultiplayerPeer extension missing, lan only")
		return

	var api: Object = Engine.get_singleton("Steam")
	var res: Dictionary = api.steamInitEx(STEAM_APP_ID)

	if res.get("status", -1) != 0:
		Log.say("steam failed to init: %s %s" % [res.get("status"), res.get("verbal", "")])
		return

	steam_api = api
	Log.say("steam initialized, user: " + str(steam_api.getPersonaName()))

	steam_api.initRelayNetworkAccess()
	steam_api.setConfigValue(CFG_P2P_ICE_ENABLE, CFG_SCOPE_GLOBAL, 0, CFG_TYPE_INT32, 0)

	_session.display_name = steam_api.getPersonaName()
	_conn.attach_steam(steam_api)
	_conn.lobby_created.connect(_on_lobby_ready)
	_conn.host_failed.connect(_on_host_failed)
	_steam_lobby.setup(steam_api)
	_steam_ok = true


func _process(_dt: float) -> void:
	if _steam_ok:
		steam_api.run_callbacks()


func _host(options: Dictionary) -> void:
	if not _can_leave():
		return

	if _steam_ok and options.get("kind", "lan") == "steam":
		options["max_players"] = mini(int(options.get("max_players", STEAM_MAX_PLAYERS)), STEAM_MAX_PLAYERS)

	if not _session.host(options):
		return

	_use_steam = _steam_ok and options.get("kind", "lan") == "steam"
	_conn.local_name = _session.username()
	var err := _conn.host(_session.map, _session.max_players, _color(), _session.password, _use_steam)

	if err != OK:
		push_error("[multiplayer] can't host: %s" % error_string(err))
		_use_steam = false
		_session.leave()
		return

	if _use_steam:
		_pending_host = true
		_host_attempt += 1
		get_tree().create_timer(LOBBY_TIMEOUT).timeout.connect(_on_lobby_timeout.bind(_host_attempt))
		return

	_lan.announce(_announcement())
	
	_enter()


func _on_lobby_ready(lobby_id: int) -> void:
	_steam_lobby.announce(_announcement())
	_steam_lobby.on_lobby_created(lobby_id)

	if _pending_host:
		_pending_host = false
		_enter()


func _on_lobby_timeout(attempt: int) -> void:
	if _pending_host and attempt == _host_attempt:
		_on_host_failed("steam lobby creation timed out")


func _on_host_failed(reason: String) -> void:
	if not _pending_host:
		return

	_pending_host = false
	_use_steam = false
	_conn.close()
	_session.leave()
	_notice = "can't host on steam: " + reason
	_notice_title = "Connection"
	_show_notice(SnapticBase.menu)


func _join(server: Dictionary, password: String) -> void:
	var err: Error

	var mismatch := Connection.mismatch(server.get("identity", ""))

	_screen.joining = true
	if mismatch != "":
		_screen.joining = false
		_notice_title = "Connection"
		_notice = "can't join: " + mismatch
		_show_notice(SnapticBase.menu)
		return

	_join_attempt += 1
	get_tree().create_timer(JOIN_TIMEOUT).timeout.connect(_on_join_timeout.bind(_join_attempt))

	_conn.local_name = _session.username()
	if server.kind == "steam":
		err = _conn.join_steam(server.lobby_id, _color(), password)
	else:
		err = _conn.join(server.address, server.port, _color(), password)

	if err != OK:
		_screen.joining = false
		push_error("[multiplayer] can't join: %s" % error_string(err))


func _on_join_timeout(attempt: int) -> void:
	if _screen.joining and attempt == _join_attempt:
		Log.warn("no answer to the join after %ds" % int(JOIN_TIMEOUT))
		_on_refused("the host did not answer")

func _cancel_join() -> void:
	_join_attempt += 1
	_conn.close()
	_screen.joining = false

func _on_refused(reason: String) -> void:
	_screen.joining = false
	_notice_title = "Connection"
	
	if _session.role != "offline":
		_kicked(reason)
		return

	_conn.close()
	_notice = "can't join: " + reason
	_show_notice(SnapticBase.menu)


func _on_accepted(map: String) -> void:
	_screen.joining = false

	if not _can_leave() or not _session.join(map):
		_conn.close()
		return

	_enter()


func _on_level_loaded(_level: Node) -> void:
	_entering = false

	if _session.role == "offline":
		if _notice != "" and LevelLoader.current_level != LevelLoader.LevelName.MENU_SCREEN_BACKGROUND:
			_return_to_menu()
		return

	if _session.role == "host" and LevelLoader.current_level != LevelLoader.LevelName.MENU_SCREEN_BACKGROUND \
			and LevelLoader.current_level != _session.level():
		_host_moved()

	if LevelLoader.current_level == LevelLoader.LevelName.MENU_SCREEN_BACKGROUND:
		Log.say("leaving the session: back at the main menu")
		_leave()
	elif not _store.get_bool("seen_first_time_popup"):
		_store.set_value("seen_first_time_popup", true)
		Log.say("onpausemenu %s" % [str(PauseMenu.instance)])
		_welcome.open(PauseMenu.instance)


func _on_players_changed(count: int) -> void:
	_session.players = count
	_advertise()

func _advertise() -> void:
	if _use_steam:
		_steam_lobby.update(_announcement())
	else:
		_lan.update(_announcement())

func _host_moved() -> void:
	_session.map = Maps.id_of(LevelLoader.current_level)
	_conn.change_map(_session.map)
	_advertise()

func _on_map_changed(map: String) -> void:
	if _session.role != "client":
		return

	if not _session.move(map):
		_kicked("The host moved to a level you don't have")
		return

	_behind = true

	if not (LevelLoader.is_loading or _entering):
		_catch_up()

func _catch_up() -> void:
	if not _behind or _session.role != "client":
		return

	_behind = false

	if LevelLoader.current_level != _session.level():
		LevelLoader.load_level(_session.level())

func _leave() -> void:
	_pending_host = false
	_behind = false
	_net.stop()
	_chat.set_active(false)
	_players.end()
	_lan.stop_announcing()
	_steam_lobby.stop_announcing()
	_use_steam = false
	_conn.close()
	_session.leave()


func _kicked(message: String) -> void:
	_notice_title = "Connection"

	if _session.role == "offline":
		return

	Log.say("leaving the session: %s" % message.to_lower())
	_leave()
	_notice = message

	if _entering:
		return

	if LevelLoader.current_level == LevelLoader.LevelName.MENU_SCREEN_BACKGROUND:
		_show_notice(SnapticBase.menu)
		return

	_return_to_menu()


func _return_to_menu() -> void:
	Cursor.claim_pointer(Cursor.MouseClaim.LOADING)

	if is_instance_valid(PauseMenu.instance) and PauseMenu.instance.is_paused():
		PauseMenu.instance.resume()

	LevelLoader.load_level(LevelLoader.LevelName.MENU_SCREEN_BACKGROUND)


func _show_notice(_menu: Node) -> void:
	if _notice == "" or not is_instance_valid(SnapticBase.menu):
		return

	if _popup == null:
		_popup = SnapticBase.create_panel(_notice_title, Vector2(380, 130))
		_popup_label = Label.new()
		_popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_popup_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_popup_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		_popup.content.add_child(_popup_label)
		_popup.add_back("OK")

	_popup_label.text = _notice
	_notice = ""
	_popup.open()

func _refresh_player_list() -> void:
	if is_instance_valid(_player_list):
		_player_list.set_host(_session.role == "host")
		_player_list.set_players(_get_players_for_player_list())


func _on_pause_menu(root: Node) -> void:
	var existing := root.find_child("PlayerList", true, false)
	if existing:
		_player_list = existing
		existing.visible = true
		_refresh_player_list()
		return

	_player_list = PlayerList.new()

	_player_list.name = "PlayerList"
	_player_list.theme = load(MenuPanel.THEME)
	root.add_child(_player_list)
	_player_list.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_player_list.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_player_list.offset_left = 0
	_player_list.offset_right = 0
	_player_list.offset_top = 0
	_player_list.offset_bottom = 0
	_player_list.style_button = _screen.style_button
	_player_list.open_profile_requested.connect(func(player: Dictionary) -> void:
		steam_api.activateGameOverlayToUser("steamid", player.id))
	_player_list.kick_requested.connect(func(player: Dictionary) -> void:
		_conn.kick(player.peer))
	_player_list.ban_requested.connect(func(player: Dictionary) -> void:
		_conn.kick(player.peer, true))
	_refresh_player_list()

	root.paused.connect(func() -> void:
		_player_list.visible = true)
	root.resumed.connect(func() -> void:
		_player_list.visible = false)

func _get_players_for_player_list() -> Array:
	var list := []

	for id in _conn._players:
		var p: Dictionary = _conn._players[id]

		list.append({"prefix": p.tags_string, "name": p.name_string, "id": p.id, "peer": id})
	
	return list

func _announcement() -> Dictionary:
	var info := _session.announcement()

	info["port"] = Connection.PORT
	info["identity"] = _conn.identity_tag()

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
	_entering = true
	LevelTransition.start(SnapticBase.menu, _session.level())
