extends "res://levels/mirraxis/mirraxis.gd"

func _ready() -> void:
	if not multiplayer.has_multiplayer_peer():
		super()
		return

	music = AudioManager.find_child("Mirraxis")
