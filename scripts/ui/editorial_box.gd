@tool
extends PanelContainer
## 钢笔手绘纸面卡片容器（自动绘制手绘墨框与可选排线阴影）

const Ink = preload("res://scripts/ui/editorial_ink.gd")

@export var fill_color: Color = Color("faf8f2")
@export var stroke_color: Color = Color("161514")
@export var stroke_width: float = 2.0
@export var ink_seed: int = 17
@export var double_frame: bool = false
@export var hatch_shadow: bool = true
@export var padding_h: int = 22
@export var padding_v: int = 18

func _ready() -> void:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = padding_h
	empty.content_margin_right = padding_h
	empty.content_margin_top = padding_v
	empty.content_margin_bottom = padding_v
	add_theme_stylebox_override("panel", empty)
	resized.connect(queue_redraw)

func _draw() -> void:
	var rect := Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0))
	if rect.size.x < 10.0 or rect.size.y < 10.0:
		return
	if hatch_shadow:
		Ink.draw_hatch_shadow(self, rect, Vector2(6.0, 6.0), Color(Ink.INK, 0.22), 5.0)
	Ink.draw_pen_rect(self, rect, fill_color, stroke_color, stroke_width, ink_seed, 1.0, 2.0, double_frame)
