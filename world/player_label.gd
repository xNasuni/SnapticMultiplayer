extends Node3D

const Utils := preload("../ui/shared/utils.gd")

const FONT_SIZE := 34
const OUTLINE_ALPHA := 0.5

const WHITE_STROKE := 5
const BLACK_STROKE := 10
const MARGIN := BLACK_STROKE + 2

const SETTLE := 12.0
const GAP := 0.08
const SUPERSAMPLE := 2
const PIXEL_SIZE := 0.004

const MAX_GROW := 4.0
const NEAR := 6.0

var LIFT := 0.25

var _height := 0.0
var _y := 0.0
var _text := ""
var _placed := false
var _viewport: SubViewport
var _sprite: Sprite3D

func _init() -> void:
	top_level = true
	visible = false

func _layer(outline: int, outline_color: Color) -> RichTextLabel:
	var label := Utils.rich(_text, FONT_SIZE)

	label.clip_contents = false
	label.position = Vector2(MARGIN, MARGIN)

	if outline > 0:
		label.add_theme_constant_override("outline_size", outline)
		label.add_theme_color_override("font_outline_color", outline_color)

	return label


func _rebuild() -> void:
	if _viewport:
		_viewport.queue_free()
		_sprite.queue_free()

	var top := _layer(0, Color.WHITE)
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	
	var outline := CanvasGroup.new()
	outline.fit_margin = BLACK_STROKE + 6
	outline.self_modulate.a = OUTLINE_ALPHA
	outline.add_child(_layer(BLACK_STROKE, Color.BLACK))
	outline.add_child(_layer(WHITE_STROKE, Color.WHITE))
	_viewport.add_child(outline)

	_viewport.add_child(top)
	add_child(_viewport)

	var content := Vector2(top.get_content_width(), top.get_content_height())
	var size := Vector2i((content + Vector2(MARGIN, MARGIN) * 2.0).ceil())

	_viewport.size = size * SUPERSAMPLE
	_viewport.size_2d_override = size
	_viewport.size_2d_override_stretch = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	_sprite = Sprite3D.new()
	_sprite.texture = _viewport.get_texture()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.shaded = false
	_sprite.no_depth_test = true
	_sprite.render_priority = 100
	_sprite.pixel_size = PIXEL_SIZE / SUPERSAMPLE
	_sprite.modulate.a = 0.0

	add_child(_sprite)

	_height = size.y * PIXEL_SIZE



func set_info(player: Dictionary) -> void:
	var bbcode: String = player.tags_string + Utils.color("@", player.color) + player.name_string

	if bbcode == _text and _sprite != null:
		return

	_text = bbcode
	_rebuild()


func set_alpha(alpha: float) -> void:
	visible = alpha > 0.001 and _sprite != null

	if _sprite:
		# the transparency property shouldn't be used cause it doesn't look proper
		_sprite.modulate.a = alpha


func place(head: Vector3, camera: Camera3D, delta: float) -> void:
	global_position = head

	if _sprite == null:
		return

	_y = LIFT if not _placed else lerpf(_y, LIFT, 1.0 - exp(-SETTLE * delta))
	_placed = true

	_sprite.position.y = _y + _height * 0.5

	var grow := 1.0

	if camera:
		grow = clampf(camera.global_position.distance_to(head) / NEAR, 1.0, MAX_GROW)

	scale = Vector3.ONE * grow

func footprint() -> float:
	return (_height * scale.y + GAP) - 0.10