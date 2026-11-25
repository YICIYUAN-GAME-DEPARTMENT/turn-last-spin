extends Control
## 带裁切视窗的机械滚轮。多个轨道可依次停住。

const Sketch = preload("res://scripts/ui/sketch_ink.gd")

@export var number_size := 26
@export var ink := Color("342b23")
@export var preview_text := "—"
var progress := 0.0:
	set(value):
		progress = value
		if is_instance_valid(_surface):
			_surface.queue_redraw()

var _tracks: Array[PackedStringArray] = []
var _surface: Control

func _ready() -> void:
	var viewport := Control.new()
	viewport.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(viewport)
	viewport.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.offset_left = 3
	viewport.offset_right = -3
	viewport.offset_top = 3
	viewport.offset_bottom = -4
	viewport.clip_contents = true
	_surface = Control.new()
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(_surface)
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.draw.connect(_draw_tracks)
	prepare([PackedStringArray([preview_text])])

func prepare(tracks: Array[PackedStringArray]) -> void:
	_tracks = tracks
	progress = 0.0

func _draw() -> void:
	var frame := Rect2(Vector2.ZERO, size)
	draw_rect(frame, Color("6f5944"))
	draw_rect(frame.grow(-1.3), Color("baa17e"))
	draw_rect(frame.grow(-3.0), Color("fff2d9"))
	draw_rect(Rect2(3.0, 3.0, maxf(0.0, size.x - 6.0), 3.0), Color("dcc6a4"))
	draw_rect(Rect2(3.0, size.y - 7.0, maxf(0.0, size.x - 6.0), 3.0), Color("e2ceac"))

func _draw_tracks() -> void:
	if _tracks.is_empty():
		return
	var width: float = _surface.size.x / _tracks.size()
	var font := get_theme_default_font()
	for i in range(_tracks.size()):
		var track := _tracks[i]
		if track.is_empty():
			continue
		var stagger: float = 0.25 * i / maxi(1, _tracks.size() - 1)
		var start := stagger * 0.32
		var stop := 1.0 if _tracks.size() == 1 else 0.75 + stagger
		var travel := clampf(inverse_lerp(start, stop, progress), 0.0, 1.0)
		var position := (1.0 - pow(1.0 - travel, 2.4)) * (track.size() - 1)
		var index := floori(position)
		var x := width * (i + 0.5)
		if i > 0:
			_surface.draw_line(Vector2(x - width * 0.5, 1), Vector2(x - width * 0.5, _surface.size.y - 1),
				Color("c8b18e"), 0.85, true)
		var height := _surface.size.y
		var at := Vector2(x, height * (0.5 - (position - index)))
		_draw_symbol(font, track[index], at, width)
		if index + 1 < track.size():
			_draw_symbol(font, track[index + 1], at + Vector2(0, height), width)

func _draw_symbol(font: Font, value: String, at: Vector2, width: float) -> void:
	var pixels := number_size
	var measured := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
	var room := maxf(3.0, width - 6.0)
	if measured > room:
		pixels = maxi(8, floori(pixels * room / measured))
	Sketch.centered(_surface, font, value, at, pixels, ink)
