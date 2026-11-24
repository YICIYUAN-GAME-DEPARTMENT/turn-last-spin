@tool
extends Control

const Sketch = preload("res://scripts/ui/sketch_ink.gd")

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Sketch.PAPER)
	var random = RandomNumberGenerator.new()
	random.seed = 273
	for i in range(2200):
		var point = Vector2(random.randf() * size.x, random.randf() * size.y)
		draw_line(point, point + Vector2(random.randf_range(0.5, 3.0), 0.5),
			Color(Sketch.MUTED, random.randf_range(0.045, 0.16)), 0.8, true)
	var left = 33.0
	var right = size.x - left
	for y in [99.0, size.y - 84.0]:
		Sketch.edge(self, Vector2(left, y), Vector2(right, y), Color(Sketch.LINE, 0.7), 0.8)
	for x in [left, right]:
		for y in [99.0, size.y - 84.0]:
			draw_line(Vector2(x, y - 5.0), Vector2(x, y + 5.0), Sketch.LINE, 1.1, true)
