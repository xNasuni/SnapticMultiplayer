extends Node3D

const Bubble := preload("chat_bubble.gd")
const Typing := preload("typing_bubble.gd")

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
var _typers := []
var _typing_left := 0.0
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


func set_typing(on: bool, timeout: float) -> void:
	var typer = _current_typer()

	if not on:
		if typer:
			typer.dismiss()

		return

	_typing_left = timeout

	if typer == null:
		typer = Typing.new()
		typer.setup_typing()

		add_child(typer)
		_typers.append(typer)


func _process(delta: float) -> void:
	if _typing_left > 0.0:
		_typing_left -= delta

		if _typing_left <= 0.0:
			set_typing(false, 0.0)

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
	var typer = _current_typer()

	if typer:
		typer.target = offset
		offset += typer.height + GAP

	for i in range(_bubbles.size() - 1, -1, -1):
		var bubble = _bubbles[i]

		bubble.target = offset
		offset += bubble.height + GAP

	_advance(_bubbles, delta)
	_advance(_typers, delta)


func _advance(list: Array, delta: float) -> void:
	for bubble in list.duplicate():
		bubble.view_alpha = _alpha

		if bubble.tick(delta):
			list.erase(bubble)
			bubble.queue_free()


func _current_typer() -> Variant:
	for typer in _typers:
		if not typer.leaving():
			return typer

	return null
