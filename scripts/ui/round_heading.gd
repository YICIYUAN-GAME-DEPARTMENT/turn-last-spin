@tool
extends Control

var number := 1
var _progress := 1.0:
	set(value):
		_progress = value
		queue_redraw()
var _tween: Tween

func roll_to(next_number: int, duration: float) -> void:
	set_number(next_number)
	_progress = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "_progress", 1.0, duration)

func set_number(value: int) -> void:
	if _tween:
		_tween.kill()
	number = value
	_progress = 1.0

func _draw() -> void:
	var font := get_theme_default_font()
	var ink := get_theme_color("font_color", "Label")
	var normal := 30
	var label_width := font.get_string_size("turn", HORIZONTAL_ALIGNMENT_LEFT, -1, normal).x
	var number_width := font.get_string_size(str(number), HORIZONTAL_ALIGNMENT_LEFT, -1, normal).x
	var x := (size.x - label_width - 12.0 - number_width) * 0.5
	var baseline := (size.y - font.get_height(normal)) * 0.5 + font.get_ascent(normal)
	draw_string(font, Vector2(x, baseline), "turn", HORIZONTAL_ALIGNMENT_LEFT, -1, normal, ink)
	var center_x := x + label_width + 12.0 + number_width * 0.5
	var slide := smoothstep(0.0, 0.62, _progress)
	if slide < 1.0:
		var old := str(maxi(0, number - 1))
		var width := font.get_string_size(old, HORIZONTAL_ALIGNMENT_LEFT, -1, normal).x
		draw_string(font, Vector2(center_x - width * 0.5, baseline - 24.0 * slide),
			old, HORIZONTAL_ALIGNMENT_LEFT, -1, normal, Color(ink, 1.0 - slide))
	var pulse := sin(PI * _progress)
	var height := roundi(lerpf(23.0, float(normal), slide) + 16.0 * pulse)
	var number_size := font.get_string_size(str(number), HORIZONTAL_ALIGNMENT_LEFT, -1, height)
	var y := (size.y - font.get_height(height)) * 0.5 + font.get_ascent(height) + 25.0 * (1.0 - slide)
	var tint := ink.lerp(Color("91e7c2"), pulse)
	draw_string(font, Vector2(center_x - number_size.x * 0.5, y), str(number),
		HORIZONTAL_ALIGNMENT_LEFT, -1, height, Color(tint, slide))
