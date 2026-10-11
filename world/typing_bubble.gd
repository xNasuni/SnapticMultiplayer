extends "chat_bubble.gd"

const DOT := 18.0
const DOT_GAP := 12.0
const DOTS := 3
const INSET := Vector2(36, 27)
const REST := Color("CBCBCB")
const PEAK := Color("B0B0B0")
const PERIOD := 1.2
const STAGGER := 0.15
const SWELL := 0.5

var _dots: Array[StyleBoxFlat] = []


func _init() -> void:
	_lifetime = INF


func setup_typing() -> void:
	var background := panel("remote")
	var span := DOTS * DOT + (DOTS - 1) * DOT_GAP

	background.size = Vector2(span, DOT) + INSET * 2.0

	for i in DOTS:
		var dot := Panel.new()
		var style := StyleBoxFlat.new()

		style.set_corner_radius_all(RADIUS)
		style.anti_aliasing = true

		dot.add_theme_stylebox_override(&"panel", style)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.position = INSET + Vector2(i * (DOT + DOT_GAP), 0)
		dot.size = Vector2(DOT, DOT)

		background.add_child(dot)
		_dots.append(style)

	_mount(background, SubViewport.UPDATE_ALWAYS)
	_wave()


func _process(_delta: float) -> void:
	_wave()


func _wave() -> void:
	var cycle := Time.get_ticks_msec() / 1000.0 / PERIOD

	for i in _dots.size():
		var phase := fposmod(cycle - i * STAGGER, 1.0)
		var swell := sin(clampf(phase / SWELL, 0.0, 1.0) * PI)

		_dots[i].bg_color = REST.lerp(PEAK, swell)
