extends Control
## 原生 CanvasItem 绘制的占位轮盘；不依赖贴图和第三方 UI。
var snapshot: Dictionary = {}
var member_names: Dictionary = {}
var local_peer_id: int = 0

const COLORS := [
	Color("#365b83"), Color("#34667b"), Color("#47647f"),
	Color("#4b5e91"), Color("#526a79"), Color("#416987"),
	Color("#645f86"), Color("#4e7c82"), Color("#53618f"),
	Color("#407085"), Color("#6d668c"), Color("#476b78")
]

func present(state: Dictionary, members: Array, peer_id: int) -> void:
	snapshot = state.duplicate(true)
	member_names.clear()
	for member in members:
		member_names[int(member["id"])] = str(member["name"])
	local_peer_id = peer_id
	queue_redraw()

func _draw() -> void:
	var alive: Array = snapshot.get("alive", [])
	var center: Vector2 = size * 0.5
	var font: Font = ThemeDB.fallback_font
	if alive.is_empty():
		draw_string(font, Vector2(12.0, center.y), "TURN / WHEEL PLACEHOLDER", HORIZONTAL_ALIGNMENT_CENTER, size.x - 24.0, 16, Color("#bfc9d5"))
		return
	var n: int = alive.size()
	var radius: float = minf(size.x, size.y) * 0.43
	var initial_index: int = int(snapshot.get("initial_index", 0))
	var target_index: int = int(snapshot.get("target_index", -1))
	var played_cards: Dictionary = snapshot.get("played_cards", {})
	var all_hands: Dictionary = snapshot.get("hands", {})
	for i in range(n):
		var start_angle: float = -PI * 0.5 + TAU * float(i) / float(n)
		var end_angle: float = -PI * 0.5 + TAU * float(i + 1) / float(n)
		var poly := PackedVector2Array()
		poly.append(center)
		for j in range(19):
			var theta: float = lerpf(start_angle, end_angle, float(j) / 18.0)
			poly.append(center + Vector2(cos(theta), sin(theta)) * radius)
		var tint: Color = COLORS[i % COLORS.size()]
		if i == initial_index:
			tint = tint.lightened(0.20)
		if i == target_index:
			tint = tint.lerp(Color("#a34e32"), 0.65)
		draw_colored_polygon(poly, tint)
		var end_vec := Vector2(cos(start_angle), sin(start_angle))
		draw_line(center, center + end_vec * radius, Color("#d9e1eb"), 1.0, true)
		var mid_angle: float = (start_angle + end_angle) * 0.5
		var direction := Vector2(cos(mid_angle), sin(mid_angle))
		var peer_id: int = int(alive[i])
		var seat_pos: Vector2 = center + direction * radius * 0.64
		var caption: String = str(member_names.get(peer_id, str(peer_id)))
		if peer_id == local_peer_id:
			caption += " (YOU)"
		var label_y: float = seat_pos.y - 23.0
		draw_string(font, Vector2(seat_pos.x - 65.0, label_y), caption, HORIZONTAL_ALIGNMENT_CENTER, 130.0, 14, Color.WHITE)
		var hp: int = int(snapshot.get("lives", {}).get(peer_id, 1))
		draw_string(font, Vector2(seat_pos.x - 47.0, seat_pos.y - 4.0), "HP %d" % hp, HORIZONTAL_ALIGNMENT_CENTER, 94.0, 13, Color("#fae5b8"))
		var hand: Array = all_hands.get(peer_id, [])
		var visible_cards: int = mini(hand.size(), 4)
		var base_x: float = seat_pos.x - float(visible_cards) * 13.5
		var card_y: float = seat_pos.y + 9.0
		for k in range(visible_cards):
			var card_box := Rect2(Vector2(base_x + float(k) * 27.0, card_y), Vector2(24.0, 24.0))
			draw_rect(card_box, Color("#e8edf5"))
			draw_rect(card_box, Color("#52647a"), false, 1.0)
			draw_string(font, card_box.position + Vector2(1.0, 17.0), str(hand[k]["value"]), HORIZONTAL_ALIGNMENT_CENTER, 22.0, 13, Color("#202e3a"))
			if played_cards.has(hand[k]["id"]):
				draw_string(font, card_box.position + Vector2(0.0, 34.0), "已出", HORIZONTAL_ALIGNMENT_CENTER, 24.0, 11, Color("#ffd9a6"))
		if hand.size() > 4:
			draw_string(font, Vector2(seat_pos.x - 40.0, seat_pos.y + 49.0), "+%d more" % (hand.size() - 4), HORIZONTAL_ALIGNMENT_CENTER, 80.0, 11, Color("#e1e7ee"))
		if i == initial_index:
			var marker: Vector2 = center + direction * (radius + 11.0)
			draw_circle(marker, 6.0, Color("#f0cd81"))
		if i == target_index:
			var tip := center + direction * (radius - 6.0)
			var base := center + direction * (radius + 24.0)
			var side := direction.orthogonal() * 8.0
			draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), Color("#ff824f"))
	draw_arc(center, radius, 0.0, TAU, 96, Color("#e6ecf4"), 2.0, true)
	draw_circle(center, radius * 0.09, Color("#162437"))
	# 轮盘中央按原始需求保持空白。
