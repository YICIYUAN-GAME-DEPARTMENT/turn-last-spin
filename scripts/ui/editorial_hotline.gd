@tool
extends Control
## 联机接入页的冷战红线电话小插画（连线/重连时电话线会轻微震颤传讯）

const Ink = preload("res://scripts/ui/editorial_ink.gd")

@export var active_pulse := false:
	set(v):
		active_pulse = v
		queue_redraw()

var _phase := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(280, 68)
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if active_pulse:
		_phase += delta * 4.5
		queue_redraw()
	elif _phase != 0.0:
		_phase = 0.0
		queue_redraw()

func _draw() -> void:
	if size.x < 160.0 or size.y < 44.0:
		return
	var base_y := size.y - 12.0
	var left_x := 42.0
	var right_x := size.x - 42.0

	# 地面极细铅笔线
	Ink.draw_pen_line(self, Vector2(12.0, base_y), Vector2(size.x - 12.0, base_y), Color(Ink.RULE, 0.9), 1.1, 71, 0.5, 0.0)

	# 左侧官僚 + 桌面 + 老式听筒
	_draw_tiny_caller(Vector2(left_x, base_y), 1.0, 10)
	# 右侧官僚 + 桌面 + 老式听筒
	_draw_tiny_caller(Vector2(right_x, base_y), -1.0, 22)

	# 中间盘绕的钢笔电话线（红线在连接中会闪动一颗脉冲墨点）
	var start := Vector2(left_x + 22.0, base_y - 15.0)
	var finish := Vector2(right_x - 22.0, base_y - 15.0)
	var span := finish.x - start.x
	var pts := PackedVector2Array()
	var steps := 44
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var sag := sin(t * PI) * 10.0
		var coil := sin(t * TAU * 4.5 + (_phase if active_pulse else 0.0)) * 3.8 * sin(t * PI)
		var x := lerpf(start.x, finish.x, t) + cos(t * TAU * 4.5) * 1.4 * sin(t * PI)
		var y := start.y + sag + coil
		pts.append(Vector2(x, y))
	draw_polyline(pts, Ink.CRIMSON if active_pulse else Ink.INK, 1.65, true)

	# 居中老式转盘电话机剪影或连接中脉冲
	var mid := Vector2((left_x + right_x) * 0.5, base_y - 12.0)
	if active_pulse and span > 40.0:
		var pulse_t := fmod(_phase * 0.28, 1.0)
		var idx := clampi(int(pulse_t * float(steps)), 0, steps)
		Ink.draw_diamond(self, pts[idx], 4.5, 4.5, Ink.CRIMSON, true)
	else:
		Ink.draw_diamond(self, mid + Vector2(0.0, 4.0), 4.0, 5.5, Ink.CRIMSON, true)

func _draw_tiny_caller(foot: Vector2, facing: float, seed_val: int) -> void:
	# 简笔小桌
	var desk := Rect2(foot + Vector2(facing * 6.0 - (14.0 if facing < 0.0 else 0.0), -18.0), Vector2(14.0, 18.0))
	Ink.draw_pen_rect(self, desk, Ink.PAPER_CARD, Ink.INK, 1.5, seed_val, 0.45, 0.8)
	# 实心黑西装驼背官僚
	var body := PackedVector2Array([
		foot + Vector2(-facing * 12.0, 0.0),
		foot + Vector2(-facing * 10.0, -24.0),
		foot + Vector2(facing * 2.0, -27.0),
		foot + Vector2(facing * 8.0, -16.0),
		foot + Vector2(facing * 3.0, 0.0)
	])
	draw_colored_polygon(body, Ink.INK)
	# 白色小圆头 + 举起的听筒
	var head := foot + Vector2(facing * 1.5, -33.0)
	draw_circle(head, 5.5, Ink.PAPER_CARD)
	draw_arc(head, 5.5, 0.0, TAU, 18, Ink.INK, 1.6, true)
	# 黑色礼帽檐
	draw_line(head + Vector2(-7.5, -3.5), head + Vector2(7.5, -3.5), Ink.INK, 1.8, true)
	draw_rect(Rect2(head + Vector2(-4.2, -8.5), Vector2(8.4, 5.0)), Ink.INK, true)
	# 手持复古听筒（呼应冷战热线）
	var phone_a := head + Vector2(facing * 5.0, -2.0)
	var phone_b := head + Vector2(facing * 7.5, 5.5)
	draw_line(phone_a, phone_b, Ink.CRIMSON, 2.5, true)
	draw_circle(phone_a, 2.3, Ink.INK)
	draw_circle(phone_b, 2.3, Ink.INK)
