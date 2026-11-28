@tool
extends Button
## 复古冷战扑克牌风格手牌：普通牌象牙纸面+朱红角标，特殊牌纯黑墨底+手绘徽记

const Ink = preload("res://scripts/ui/editorial_ink.gd")

const SPECIAL_NAMES := {"defense": "防御卡", "change": "变化卡", "super": "超级卡"}
const SPECIAL_HINTS := {
	"defense": "出牌阶段使用，保住最后 1 点生命",
	"change": "出牌阶段使用，先选点数，再选加或减",
	"super": "结算阶段使用，追加正向位移"
}

@export var card_id: int = -1
@export var value: int = 1:
	set(number):
		value = number
		_update_face()
@export_enum("play", "defense", "change", "super") var kind: String = "play":
	set(card_kind):
		kind = card_kind
		_update_face()
@export var quantity: int = 1:
	set(amount):
		quantity = amount
		_update_face()
@export var display_font: Font

var show_corner: bool = true:
	set(enabled):
		if show_corner != enabled:
			show_corner = enabled
			queue_redraw()
var is_pinned: bool = false:
	set(enabled):
		if is_pinned != enabled:
			is_pinned = enabled
			queue_redraw()

func _ready() -> void:
	flat = true
	text = ""
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	resized.connect(queue_redraw)
	_update_face()

func _update_face() -> void:
	if SPECIAL_NAMES.has(kind):
		tooltip_text = SPECIAL_HINTS[kind]
		accessibility_name = "%s ×%d" % [SPECIAL_NAMES[kind], quantity]
	else:
		tooltip_text = "数字牌 %d（点击选择加或减）" % value
		accessibility_name = "数字牌 %d" % value
	text = ""
	queue_redraw()

func _draw() -> void:
	if size.x < 24.0 or size.y < 32.0:
		return
	var font := get_theme_default_font()
	var serif := display_font if display_font != null else font
	var rect := Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0))
	var hovered: bool = (is_hovered() or has_focus() or is_pinned) and not disabled
	var is_special: bool = SPECIAL_NAMES.has(kind)
	var alpha: float = 0.52 if disabled else 1.0

	# 1. 版画阴影
	var shadow_off := Vector2(5.0, 6.0) if hovered else Vector2(3.0, 4.0)
	Ink.draw_hatch_shadow(self, rect, shadow_off, Color(Ink.CRIMSON if hovered else Ink.INK, 0.28 * alpha), 4.2)

	# 2. 牌底与手绘双框
	var bg := Color(Ink.INK, alpha) if is_special else Color(Ink.PAPER_CARD, alpha)
	var fg := Color(Ink.PAPER_CARD, alpha) if is_special else Color(Ink.INK, alpha)
	var accent := Color(Ink.CRIMSON, alpha)
	var border_col := accent if hovered else (Color(Ink.INK, alpha) if not is_special else Color(Ink.INK, alpha))
	Ink.draw_pen_rect(self, rect, bg, border_col, 2.4 if hovered else 1.9, (card_id + 13) * 7, 0.75, 1.3, false)

	# 内细框
	var inner := rect.grow(-5.5)
	draw_rect(inner, Color(fg, 0.28), false, 1.0)

	if is_special:
		_draw_special_face(rect, font, serif, fg, accent)
	else:
		_draw_number_face(rect, font, serif, fg, accent, hovered)

func _draw_number_face(rect: Rect2, font: Font, serif: Font, fg: Color, accent: Color, hovered: bool) -> void:
	var val_str := str(value)
	# 左上 & 右下倒置扑克角标（数字 + 朱红方块 ♦）
	if show_corner and font != null:
		var tl := rect.position + Vector2(12.0, 15.0)
		Ink.draw_centered_text(self, serif, val_str, tl, 14, accent if hovered else fg)
		Ink.draw_diamond(self, tl + Vector2(0.0, 12.0), 3.6, 5.2, accent, true)

		var br := rect.end - Vector2(12.0, 15.0)
		draw_set_transform(br, PI, Vector2.ONE)
		Ink.draw_centered_text(self, serif, val_str, Vector2.ZERO, 14, accent if hovered else fg)
		Ink.draw_diamond(self, Vector2(0.0, 12.0), 3.6, 5.2, accent, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 中央复古大数字
	if serif != null:
		var main_size := clampi(roundi(rect.size.x * 0.48), 22, 42)
		Ink.draw_centered_text(self, serif, val_str, rect.get_center(), main_size, accent if hovered else fg)

func _draw_special_face(rect: Rect2, font: Font, _serif: Font, fg: Color, accent: Color) -> void:
	var c := rect.get_center() + Vector2(0.0, -8.0)
	# 右上角数量徽章（朱红底白字）
	if quantity > 1 and font != null:
		var badge := Rect2(Vector2(rect.end.x - 28.0, rect.position.y + 5.0), Vector2(23.0, 18.0))
		draw_rect(badge, accent, true)
		Ink.draw_centered_text(self, font, "×%d" % quantity, badge.get_center(), 11, Ink.PAPER_CARD)

	# 左上角朱红方块标
	Ink.draw_diamond(self, rect.position + Vector2(13.0, 14.0), 4.2, 6.0, accent, true)

	# 手绘钢笔图标（纯黑白 + 朱红）
	match kind:
		"defense":
			# 钢笔盾牌
			var shield := PackedVector2Array([
				c + Vector2(0.0, -18.0),
				c + Vector2(15.0, -12.0),
				c + Vector2(13.0, 4.0),
				c + Vector2(0.0, 18.0),
				c + Vector2(-13.0, 4.0),
				c + Vector2(-15.0, -12.0)
			])
			draw_colored_polygon(shield, fg)
			Ink.draw_diamond(self, c + Vector2(0.0, -1.0), 5.5, 8.0, accent, true)
		"change":
			# 双向变换箭头 + 问号菱形
			draw_arc(c, 14.0, 0.3, PI - 0.3, 16, fg, 2.2, true)
			draw_arc(c, 14.0, PI + 0.3, TAU - 0.3, 16, fg, 2.2, true)
			Ink.draw_diamond(self, c, 6.5, 9.0, accent, true)
			Ink.draw_centered_text(self, font, "±", c, 12, Ink.PAPER_CARD)
		"super":
			# 冷战红星 / 强力推进星芒
			var star := PackedVector2Array()
			for i in range(10):
				var a := -PI * 0.5 + TAU * float(i) / 10.0
				var r := 17.5 if i % 2 == 0 else 7.5
				star.append(c + Vector2.from_angle(a) * r)
			draw_colored_polygon(star, accent)
			draw_circle(c, 4.5, fg)

	# 底部特殊牌名称
	if font != null:
		Ink.draw_centered_text(self, font, SPECIAL_NAMES[kind],
			Vector2(rect.get_center().x, rect.end.y - 19.0), 13, fg)
