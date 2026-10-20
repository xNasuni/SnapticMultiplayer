extends SubViewportContainer

const RemotePlayer := preload("../world/remote_player.gd")
const Pose := preload("../networking/pose.gd")

const SIZE := Vector2(280, 380)
const FOV := 30.0
const EYE := Vector3(0, 1.05, 4.2)
const FOCUS := Vector3(0, 0.95, 0)
const YAW := PI + 0.5

var _avatar
var _pose := Pose.new()


func bind(store, key: String) -> void:
	var viewport := SubViewport.new()
	var camera := Camera3D.new()

	stretch = true
	custom_minimum_size = SIZE

	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X

	camera.fov = FOV
	camera.transform = Transform3D(Basis.IDENTITY, EYE).looking_at(FOCUS)

	_pose.yaw = YAW
	_avatar = RemotePlayer.new()
	_avatar.setup(store.get_color(key), false)

	viewport.add_child(camera)
	viewport.add_child(_avatar)
	add_child(viewport)

	store.changed.connect(_on_changed.bind(key))


func _on_changed(changed: String, value: Variant, key: String) -> void:
	if changed == key:
		_avatar.tint(value)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_avatar.follow(_pose, delta)
