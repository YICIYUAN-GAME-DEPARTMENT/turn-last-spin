@tool
extends Control
## 顶部居中高可读指挥条：回合号 + 大号冷战末日倒计时表盘 + 阶段与锁定进度

const Ink = preload("res://scripts/ui/editorial_ink.gd")

@export var display_font: Font
@export var mono_font: Font

var number: int = 1
var countdown_seconds: int = -1:
	set(value):
		if countdown_seconds != value:
			countdown_seconds = value
			queue_redraw()
var countdown_ratio: float = 0.0:
	set(value):
		if not is_equal_approx(countdown_ratio, value):
			countdown_ratio = value
			queue_redraw()
var phase_caption: String = "准备发牌":
	set(value):
		if phase_caption != value:
			phase_caption = value
			queue_redraw()
var phase_urgent: bool = false:
	set(value):
		if phase_urgent != value:
			phase_urgent = value
			queue_redraw()
var locked_text: String = "":
	set(value):
		if locked_text != value:
			locked_text = value
			queue_redraw()

var _pulse: float = 0.0

func set_number(value: int) -> void:
	number = value
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if countdown_seconds >= 0 and countdown_seconds <= 5:
		_pulse += delta * 6.0
		queue_redraw()
	elif _pulse != 0.0:
		_pulse = 0.0
		queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	if font == null or size.x < 240.0 or size.y < 44.0:
		return
	var serif := display_font if display_font != null else font
	var mono := mono_font if mono_font != null else font

	var bar_rect := Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 8.0))
	Ink.draw_hatch_shadow(self, bar_rect, Vector2(5.0, 5.0), Color(Ink.INK, 0.20), 4.8)
	Ink.draw_pen_rect(self, bar_rect, Ink.PAPER_CARD, Ink.INK, 2.0, 177, 0.7, 1.5, false)

	var mid_x := bar_rect.get_center().x
	var mid_y := bar_rect.get_center().y

	# 中央：超大高反差倒计时盒（一眼锁定剩余秒数！）
	var clock_w := 124.0
	var clock_h := bar_rect.size.y - 6.0
	var clock_rect := Rect2(Vector2(mid_x - clock_w * 0.5, bar_rect.position.y + 3.0), Vector2(clock_w, clock_h))
	var active_timer := countdown_seconds >= 0
	var urgent := active_timer and countdown_seconds <= 5
	var clock_bg := Ink.CRIMSON if urgent else (Ink.INK if active_timer else Ink.PAPER_TINT)
	var clock_fg := Ink.PAPER_CARD if active_timer else Ink.INK_SOFT

	if urgent:
		var shake := sin(_pulse * 3.0) * 1.4
		clock_rect.position.x += shake

	draw_rect(clock_rect, clock_bg, true)
	draw_rect(clock_rect, Ink.INK, false, 1.6)

	var sec_str := "%02d" % countdown_seconds if active_timer else "—"
	Ink.draw_centered_text(self, serif, sec_str, clock_rect.get_center() + Vector2(-8.0, -3.0), 34 if active_timer else 24, clock_fg)
	if active_timer:
		draw_string(mono, Vector2(clock_rect.get_center().x + 22.0, clock_rect.get_center().y + 6.0),
			"s", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(clock_fg, 0.85))
		# 倒计时条（底部紧贴）
		var bar_w := (clock_rect.size.x - 10.0) * clampf(countdown_ratio, 0.0, 1.0)
		var bar_y := clock_rect.end.y - 5.5
		draw_rect(Rect2(clock_rect.position.x + 5.0, bar_y, clock_rect.size.x - 10.0, 3.0), Color(clock_fg, 0.25), true)
		draw_rect(Rect2(clock_rect.position.x + 5.0, bar_y, bar_w, 3.0),
			Ink.PAPER_CARD if urgent else Ink.CRIMSON, true)

	# 左侧翼：回合号（TURN 01）
	var left_center_x := (bar_rect.position.x + clock_rect.position.x) * 0.5
	Ink.draw_centered_text(self, mono, "TURN", Vector2(left_center_x - 24.0, mid_y - 2.0), 12, Ink.INK_SOFT)
	Ink.draw_centered_text(self, serif, "%02d" % maxi(0, number), Vector2(left_center_x + 22.0, mid_y - 1.0), 26, Ink.INK)

	# 右侧翼：阶段与锁定人数
	var right_center_x := (clock_rect.end.x + bar_rect.end.x) * 0.5
	var cap_col := Ink.CRIMSON if (phase_urgent or urgent) else Ink.INK
	if locked_text.is_empty():
		Ink.draw_centered_text(self, font, phase_caption, Vector2(right_center_x, mid_y), 14, cap_col)
	else:
		Ink.draw_centered_text(self, font, phase_caption, Vector2(right_center_x, mid_y - 9.0), 13, cap_col)
		Ink.draw_centered_text(self, mono, locked_text, Vector2(right_center_x, mid_y + 11.0), 11, Ink.INK_SOFT)
