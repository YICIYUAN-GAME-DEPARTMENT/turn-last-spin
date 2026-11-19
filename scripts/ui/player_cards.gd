extends RefCounted

static func draw_card(canvas: CanvasItem, rect: Rect2, card: Dictionary, font: Font) -> void:
	var played: bool = card.get("played", false)
	var face_up: bool = card["face_up"]
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f2c7ac") if played else (Color("d4eade") if face_up else Color("182e40"))
	style.border_color = Color("ffb28e") if played else (Color("91e7c2") if face_up else Color("768eb5"))
	style.set_border_width_all(2 if played else 1)
	style.set_corner_radius_all(3)
	canvas.draw_style_box(style, rect)
	if not face_up:
		_draw_back(canvas, rect, int(card.get("quantity", 1)), font)
		return

	var center: Vector2 = rect.get_center()
	var caption: String = card.get("caption", "")
	if not caption.is_empty():
		var points: String = card.get("points", "")
		var caption_size: int = int(rect.size.x * 0.42)
		if points.is_empty():
			_draw_text(canvas, rect, center.y, caption, caption_size, Color("10221e"), font)
		else:
			var face_height: float = rect.size.y - (9.0 if rect.size.x < 28 else 12.0)
			_draw_text(canvas, rect, rect.position.y + face_height * 0.45, caption, caption_size, Color("10221e"), font)
			_draw_text(canvas, rect, rect.position.y + face_height * 0.86, points, caption_size, Color("10221e"), font)
	else:
		var font_size: int = int(rect.size.x * (0.43 if played else 0.50))
		_draw_text(canvas, rect, center.y + (0.0 if played else font_size * 0.28), str(int(card["value"])), font_size, Color("10221e"), font)
	if played:
		var small: bool = rect.size.x < 28
		var badge_height: float = 9.0 if small else 12.0
		var badge := Rect2(rect.position + Vector2(1, rect.size.y - badge_height - 1), Vector2(rect.size.x - 2, badge_height))
		canvas.draw_rect(badge, Color("693d2e"))
		_draw_text(canvas, badge, badge.end.y - 2, "已出", 7 if small else 9, Color("ffe7d7"), font)

static func _draw_back(canvas: CanvasItem, rect: Rect2, quantity: int, font: Font) -> void:
	canvas.draw_rect(rect.grow(-4), Color("44536f"), false, 1.0)
	var center: Vector2 = rect.get_center()
	var half: float = rect.size.x * 0.20
	if quantity > 1:
		center.y -= 3
	canvas.draw_polyline(PackedVector2Array([center + Vector2(0, -half), center + Vector2(half, 0),
		center + Vector2(0, half), center + Vector2(-half, 0), center + Vector2(0, -half)]), Color("9eb2d8"), 1.0, true)
	if quantity > 1:
		var count_label: String = "×%d" % quantity if quantity <= 99 else "99+"
		_draw_text(canvas, rect, rect.end.y - 5, count_label, 8, Color("edf0ff"), font)

static func _draw_text(canvas: CanvasItem, rect: Rect2, baseline: float, value: String, font_size: int, color: Color, font: Font) -> void:
	canvas.draw_string(font, Vector2(rect.position.x, baseline), value, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, color)
