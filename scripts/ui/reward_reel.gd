extends Control
## 机械凭单滚轮窗口（纯黑手绘墨框 + 象牙底）

const Ink = preload("res://scripts/ui/editorial_ink.gd")

@export var number_size: int = 26
@export var ink: Color = Color("161514")
@export var preview_text: String = "—"

var progress: float = 0.0:
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
	viewport.offset_left = 3.0
	viewport.offset_right = -3.0
	viewport.offset_top = 3.0
	viewport.offset_bottom = -3.0
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
	draw_rect(frame, Ink.PAPER_CARD, true)
	draw_rect(frame, Ink.INK, false, 1.8)
	draw_rect(Rect2(2.0, 2.0, maxf(0.0, size.x - 4.0), 3.0), Color(Ink.INK, 0.12), true)
	draw_rect(Rect2(2.0, size.y - 5.0, maxf(0.0, size.x - 4.0), 3.0), Color(Ink.INK, 0.12), true)

func _draw_tracks() -> void:
	if _tracks.is_empty():
		return
	var width: float = _surface.size.x / float(_tracks.size())
	var font := get_theme_default_font()
	if font == null:
		return
	for i in range(_tracks.size()):
		var track: PackedStringArray = _tracks[i]
		if track.is_empty():
			continue
		var stagger: float = 0.25 * float(i) / float(maxi(1, _tracks.size() - 1))
		var start := stagger * 0.32
		var stop := 1.0 if _tracks.size() == 1 else 0.75 + stagger
		var travel := clampf(inverse_lerp(start, stop, progress), 0.0, 1.0)
		var pos := (1.0 - pow(1.0 - travel, 2.4)) * float(track.size() - 1)
		var index := floori(pos)
		var x := width * (float(i) + 0.5)
		if i > 0:
			_surface.draw_line(Vector2(x - width * 0.5, 1.0), Vector2(x - width * 0.5, _surface.size.y - 1.0),
				Color(Ink.RULE, 0.8), 1.0, true)
		var h := _surface.size.y
		var at := Vector2(x, h * (0.5 - (pos - float(index))))
		_draw_symbol(font, track[index], at, width)
		if index + 1 < track.size():
			_draw_symbol(font, track[index + 1], at + Vector2(0.0, h), width)

func _draw_symbol(font: Font, value: String, at: Vector2, width: float) -> void:
	var pixels := number_size
	var measured := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
	var room := maxf(4.0, width - 6.0)
	if measured > room:
		pixels = maxi(9, floori(float(pixels) * room / measured))
	Ink.draw_centered_text(_surface, font, value, at, pixels, ink)
