extends RefCounted

const SnapticBase := preload("res://gdpatch/mods/snapticbase/mod.gd")
const MOD := "multiplayer"
const DIRECTORY := "assets/sound/"
const VOLUME := 0.1
const AUDIBLE := 0.01

static var _streams := {}


static func stream(kind: String) -> AudioStream:
	if _streams.has(kind):
		return _streams[kind]

	var path: String = SnapticBase.get_mod(MOD).dir + DIRECTORY + kind + ".ogg"
	var bytes := FileAccess.get_file_as_bytes(path)
	var loaded: AudioStream = AudioStreamOggVorbis.load_from_buffer(bytes) if not bytes.is_empty() else null

	if loaded == null:
		push_warning("[multiplayer] missing chat sound " + path)

	_streams[kind] = loaded

	return loaded


static func play(parent: Node, kind: String, at: Vector3, gain: float) -> void:
	var sound := stream(kind)

	if sound == null or gain <= AUDIBLE:
		return

	var player := AudioStreamPlayer3D.new()

	player.stream = sound
	player.bus = AudioManager.SFX_BUS
	player.volume_db = linear_to_db(VOLUME * gain)
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.max_distance = 100.0
	player.finished.connect(player.queue_free)

	parent.add_child(player)
	player.global_position = at
	player.play()
