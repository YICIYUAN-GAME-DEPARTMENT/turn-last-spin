extends Control
## 筹码余额滚轮表（高反差纯黑墨数字 + 朱红 r 单位，支持进位滚动）

const Ink = preload("res://scripts/ui/editorial_ink.gd")

@export var show_gain: bool = false
var amount: int = -1
var reading: float = 0.0:
	set(value):
		reading = value
		queue_redraw()
var _roll: Tween

func set_amount(value: int, animate_gain: bool, duration: float = 0.40) -> void:
	if value == amount and animate_gain:
		return
	if _roll != null and _roll.is_valid():
		_roll.kill()
	var gaining := animate_gain and amount >= 0 and value > amount
	amount = value
	if gaining:
		_roll = create_tween()
		_roll.tween_property(self, "reading", float(value), duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		reading = float(value)

func _draw() -> void:
	var font := get_theme_default_font()
	if font == null or size.x < 24.0:
		return
	var whole := floori(reading)
	var digits := maxi(1, str(maxi(whole, amount)).length())
	var step := minf(28.0 if show_gain else 15.0, (size.x - 24.0) / float(digits + int(show_gain)))
	var font_size := mini(40 if show_gain else 22, floori(step * 1.45))
	var baseline := (size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	var x := (size.x + float(digits + 1) * step) * 0.5 if show_gain else 10.0 + float(digits) * step
	var fraction := reading - float(whole)
	for _column in range(digits):
		x -= step
		var digit := whole % 10
		var y := baseline - fraction * size.y
		draw_string(font, Vector2(x, y), str(digit), HORIZONTAL_ALIGNMENT_CENTER, step, font_size, Ink.INK)
		if fraction > 0.0:
			draw_string(font, Vector2(x, y + size.y), str((digit + 1) % 10), HORIZONTAL_ALIGNMENT_CENTER, step, font_size, Ink.INK)
		if digit != 9:
			fraction = 0.0
		@warning_ignore("integer_division")
		whole /= 10
	if show_gain:
		draw_string(font, Vector2(x - step, baseline), "+", HORIZONTAL_ALIGNMENT_CENTER, step, roundi(font_size * 0.72), Ink.CRIMSON)
		return
	draw_string(font, Vector2(x + float(digits) * step + 3.0, baseline), "r", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ink.CRIMSON)
