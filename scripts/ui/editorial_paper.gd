@tool
extends Control
## 暖米白棉质卡牌纸底 + 报刊印刷细纹 + 扑克角标

const Ink = preload("res://scripts/ui/editorial_ink.gd")

@export var corner_index := "T"
@export var show_card_corners := true

var _specks: Array[Dictionary] = []
var _last_size := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_rebuild_specks)
	_rebuild_specks()

func _rebuild_specks() -> void:
	if size == _last_size and not _specks.is_empty():
		return
	_last_size = size
	_specks.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1962
	var count := clampi(int(size.x * size.y / 1400.0), 320, 1100)
	for i in range(count):
		_specks.append({
			"p": Vector2(rng.randf() * size.x, rng.randf() * size.y),
			"len": rng.randf_range(0.8, 3.2),
			"ang": rng.randf_range(-0.35, 0.35),
			"a": rng.randf_range(0.035, 0.115),
			"dot": rng.randf() < 0.28
		})
	queue_redraw()

func _draw() -> void:
	if size.x < 40.0 or size.y < 40.0:
		return
	# 1. 复古纸面底色
	draw_rect(Rect2(Vector2.ZERO, size), Ink.PAPER, true)

	# 2. 极轻印刷纸纤维与微小墨点（不浑浊、保持参考图的高留白通透感）
	for s in _specks:
		var p: Vector2 = s.p
		var c := Color(Ink.INK_SOFT, float(s.a))
		if s.dot:
			draw_circle(p, 0.85, c)
		else:
			var d := Vector2.from_angle(float(s.ang)) * float(s.len)
			draw_line(p, p + d, c, 0.8, true)

	# 3. 报刊裁切版框与四角印刷十字标
	var margin := 20.0
	var frame := Rect2(Vector2(margin, margin), size - Vector2(margin * 2.0, margin * 2.0))
	Ink.draw_pen_rect(self, frame, Color(0, 0, 0, 0), Color(Ink.RULE, 0.82), 1.1, 19, 0.65, 4.0)

	# 顶部与底部极细的印刷分隔装饰点
	var mid_x := size.x * 0.5
	Ink.draw_diamond(self, Vector2(mid_x, margin), 4.0, 5.5, Color(Ink.INK, 0.35), false, 1.1)
	Ink.draw_diamond(self, Vector2(mid_x, size.y - margin), 4.0, 5.5, Color(Ink.INK, 0.35), false, 1.1)

	# 4. 扑克牌式左上 / 右下倒置角标（致敬参考图 10♦ 构图）
	if show_card_corners:
		var font := get_theme_default_font()
		_draw_corner_index(font, Vector2(44.0, 46.0), 0.0)
		_draw_corner_index(font, Vector2(size.x - 44.0, size.y - 46.0), PI)

func _draw_corner_index(font: Font, pos: Vector2, rot: float) -> void:
	draw_set_transform(pos, rot, Vector2.ONE)
	if font != null and not corner_index.is_empty():
		Ink.draw_centered_text(self, font, corner_index, Vector2(0.0, -2.0), 22, Ink.CRIMSON)
	Ink.draw_diamond(self, Vector2(0.0, 21.0), 6.5, 9.5, Ink.CRIMSON, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
