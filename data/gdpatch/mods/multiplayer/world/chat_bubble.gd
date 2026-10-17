extends Node3D

const BACKGROUNDS := {
	"local": Color("08A2FA"),
	"remote": Color("D5D5D5"),
}
const TEXT := {
	"local": Color.WHITE,
	"remote": Color("2B2B2B"),
}

const FONT_SIZE := 40
const MAX_TEXT_WIDTH := 520.0
const PADDING := Vector2(40, 22)
const RADIUS := 4096
const PIXEL_SIZE := 0.004
const SUPERSAMPLE := 2

const LIFETIME := 5.0
const LONG_LIFETIME := 10.0
const LONG_LENGTH := 50
const FADE_TIME := 0.25
const SLIDE := 0.15
const SETTLE := 12.0

var height := 0.0
var target := 0.0
var view_alpha := 1.0

var _age := 0.0
var _lifetime := LIFETIME
var _shown := 0.0
var _y := 0.0
var _sprite: Sprite3D


static func panel(kind: String) -> Panel:
	var style := StyleBoxFlat.new()
	var node := Panel.new()

	style.bg_color = BACKGROUNDS[kind]
	style.set_corner_radius_all(RADIUS)
	style.corner_detail = 16
	style.anti_aliasing = true

	node.add_theme_stylebox_override(&"panel", style)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE

	return node


func setup(text: String, local: bool) -> void:
	var kind := "local" if local else "remote"
	var label := Label.new()

	_lifetime = LONG_LIFETIME if text.length() > LONG_LENGTH else LIFETIME

	var font := label.get_theme_font(&"font")
	var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var measured := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, MAX_TEXT_WIDTH, FONT_SIZE, -1, flags)
	var text_size := measured.ceil() + Vector2(4, 0)

	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.add_theme_color_override(&"font_color", TEXT[kind])
	label.position = PADDING
	label.size = text_size

	var background := panel(kind)

	background.size = text_size + PADDING * 2.0
	background.add_child(label)

	_mount(background, SubViewport.UPDATE_ONCE)


func _mount(background: Control, update: SubViewport.UpdateMode) -> void:
	var viewport := SubViewport.new()

	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	viewport.size = Vector2i(background.size.ceil()) * SUPERSAMPLE
	viewport.size_2d_override = Vector2i(background.size.ceil())
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = update
	viewport.add_child(background)
	add_child(viewport)

	_sprite = Sprite3D.new()
	_sprite.texture = viewport.get_texture()
	_sprite.shaded = false
	_sprite.pixel_size = PIXEL_SIZE / SUPERSAMPLE
	_sprite.modulate.a = 0.0
	add_child(_sprite)

	height = viewport.size_2d_override.y * PIXEL_SIZE


func dismiss() -> void:
	_age = maxf(_age, _lifetime)


func leaving() -> bool:
	return _age >= _lifetime


func tick(delta: float) -> bool:
	_age += delta
	_shown = move_toward(_shown, 0.0 if leaving() else 1.0, delta / FADE_TIME)
	_y = lerpf(_y, target, 1.0 - exp(-SETTLE * delta))

	var eased := smoothstep(0.0, 1.0, _shown)

	_sprite.modulate.a = eased * view_alpha
	_sprite.position.y = _y + height * 0.5 - SLIDE * (1.0 - eased)

	return leaving() and _shown <= 0.0
