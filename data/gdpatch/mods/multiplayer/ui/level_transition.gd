extends RefCounted

const Maps := preload("../networking/maps.gd")

static func start(menu: Node, level: int) -> void:
	var duration: float = menu.get("tween_duration")
	var tween: Tween = Helpers.fade_control(menu.get("everything_else"), menu.get("fade_tween"), false, duration)

	menu.set("fade_tween", tween)
	tween.parallel()
	tween.tween_property(menu.get("wind_loop_player"), "volume_linear", 0.0, duration)

	await AudioManager.play_sound_effect(SFX.Name.MENU_START).finished

	Maps.open(level)
