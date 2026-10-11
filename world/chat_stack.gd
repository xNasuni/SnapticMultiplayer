extends Node3D

const Bubble := preload("chat_bubble.gd")

const MAX_VISIBLE := 3
const GAP := 0.06
const LIFT := 0.45

const ARC := PI * 45.0 / 180.0
const FADE_FROM := PI * 60.0 / 180.0
const BACK_FROM := PI * 90.0 / 180.0
const BACK_ALPHA := 0.3
const TURN := 10.0
const FADE := 8.0

var facing := Vector3.FORWARD

var _bubbles := []
var _yaw := 0.0
var _alpha := 1.0
var _oriented := false


func _init() -> void:
	top_level = true


func say(text: String, local: bool) -> void:
	var bubble := Bubble.new()

	bubble.setup(text, local)
	add_child(bubble)
	_bubbles.append(bubble)

	var live := _bubbles.filter(func(b) -> bool: return not b.leaving())

	for i in live.size() - MAX_VISIBLE:
		live[i].dismiss()


func _process(delta: float) -> void:
	_orient(delta)
	_layout(delta)


func _orient(delta: float) -> void:
	var front := atan2(facing.x, facing.z)
	var camera := get_viewport().get_camera_3d()
	var rel := 0.0

	if camera:
		var to_camera := camera.global_position - global_position

		rel = wrapf(atan2(to_camera.x, to_camera.z) - front, -PI, PI)

	var side := absf(rel)
	var yaw := front + clampf(rel, -ARC, ARC)

	if side > BACK_FROM:
		yaw = front + PI + clampf(wrapf(rel - PI, -PI, PI), -ARC, ARC)

	var alpha := lerpf(1.0, BACK_ALPHA, smoothstep(FADE_FROM, BACK_FROM, side))

	if not _oriented:
		_oriented = true
		_yaw = yaw
		_alpha = alpha

	_yaw = lerp_angle(_yaw, yaw, 1.0 - exp(-TURN * delta))
	_alpha = lerpf(_alpha, alpha, 1.0 - exp(-FADE * delta))
	rotation.y = _yaw


func _layout(delta: float) -> void:
	var offset := LIFT

	for i in range(_bubbles.size() - 1, -1, -1):
		var bubble = _bubbles[i]

		bubble.target = offset
		offset += bubble.height + GAP

	for bubble in _bubbles.duplicate():
		bubble.view_alpha = _alpha

		if bubble.tick(delta):
			_bubbles.erase(bubble)
			bubble.queue_free()
