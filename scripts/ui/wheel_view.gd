@tool
extends Control

const Sketch = preload("res://scripts/ui/sketch_ink.gd")
const FELT = Color("f3ead9")
const SECTOR = Color("eee0c9")
const WOOD = Color("ded0b9")
const DECK_SIZE := Vector2(53, 73)
const SEATED_SQUEEZE := 0.33
const DIAL_RADIUS := 63.0
const DIAL_BRASS := Color("dac5a3")
const DIAL_EDGE := Color("806d56")
const DIAL_LINE := Color("a99476")

var seats: Array = []
var local_player_id = 0
var front_index = 0
var start_index = 0
var target_index = -1
var center_caption = "初始指向"
var center_steps = "1"
var countdown_seconds := -1:
	set(value):
		if countdown_seconds != value:
			countdown_seconds = value
			queue_redraw()
var needle_angle = -PI / 2.0:
	set(value):
		needle_angle = value
		queue_redraw()
var view_height = 0.0:
	set(value):
		view_height = value
		queue_redraw()
var deal_progress := 1.0:
	set(value):
		deal_progress = value
		queue_redraw()
var play_progress := 1.0:
	set(value):
		play_progress = value
		queue_redraw()
var number_scale := 1.0
var showing_actions := false
var table_cards: Dictionary = {}:
	set(value):
		table_cards = value
		queue_redraw()
var _placements: Dictionary = {}
var _opponent_deals: Array[Dictionary] = []
var self_deal: Dictionary = {}:
	set(value):
		self_deal = value
		queue_redraw()
var ui_font: Font

@export var dial_number_font: Font

@export_range(2, 12, 1) var preview_players: int = 8:
	set(number):
		preview_players = number
		if Engine.is_editor_hint() and is_node_ready():
			_editor_preview()

func _ready() -> void:
	ui_font = get_theme_default_font()
	resized.connect(queue_redraw)
	if Engine.is_editor_hint():
		_editor_preview()

func _editor_preview() -> void:
	seats.clear()
	for i in range(preview_players):
		seats.append({"id": i, "name": String.chr(96 + i),
			"alive": true, "cards": [{"id": i, "value": (i * 3 + 2) % preview_players + 1,
			"face_up": true, "played": false, "sign": 0}]})
	start_index = 0
	center_steps = "1"
	countdown_seconds = 12
	queue_redraw()

func seat_angle(index: int) -> float:
	return PI / 2.0 + TAU * (index - front_index) / maxi(1, seats.size())

func _draw() -> void:
	if seats.is_empty() or ui_font == null or size.x < 120.0:
		return
	var center := table_center()
	var oval := table_extent()
	var depth = lerpf(23.0, 2.5, view_height)
	_opponent_deals.clear()
	if view_height < 0.92:
		_draw_opponents(center, oval)
	var shadow = _arc(center + Vector2(4, depth + 10.0), oval * Vector2(1.018, 1.016))
	draw_colored_polygon(shadow.slice(0, shadow.size() - 1), Color("ddd0be"))
	var base = _arc(center + Vector2(0, depth), oval)
	draw_colored_polygon(base.slice(0, base.size() - 1), WOOD)
	Sketch.stroke(self, base, Sketch.INK, 1.5)
	var apron = _arc(center + Vector2(0, depth), oval, 0, PI, 80)
	var lip = _arc(center, oval, PI, 0, 80)
	Sketch.hatch(self, apron + lip, Color(Sketch.MUTED, 0.33), 13.0)
	var rim = _arc(center, oval)
	draw_colored_polygon(rim.slice(0, rim.size() - 1), FELT)
	_draw_sectors(center, oval)
	Sketch.stroke(self, rim, Sketch.INK, 2.0)
	Sketch.stroke(self, _arc(center, oval * 0.976), Sketch.LINE, 1.0)
	Sketch.stroke(self, _arc(center, oval * 0.918), Sketch.LINE, 1.0)
	Sketch.stroke(self, _arc(center, oval * 0.893), Sketch.LINE, 0.8)
	_draw_pointer_shadow(center, oval)
	if deal_progress >= 1.0 or showing_actions:
		_draw_table_cards(center, oval)
	_draw_deck(center, oval)
	_draw_pointer(center, oval)
	_draw_deal_flights(center, oval)

func _table_radius() -> float:
	return minf(size.x * 0.389, size.y * 0.54)

func table_extent() -> Vector2:
	var radius := lerpf(_table_radius(), minf(size.x * 0.34, size.y * 0.395), view_height)
	return Vector2(radius, radius * lerpf(SEATED_SQUEEZE, 1.0, view_height))

func table_center() -> Vector2:
	var seated_y := maxf(size.y * 0.585, _table_radius() * SEATED_SQUEEZE + 246.0)
	return Vector2(size.x * 0.509, lerpf(seated_y, size.y * 0.515, view_height))

func _arc(center: Vector2, oval: Vector2, begin: float = 0.0, end: float = TAU, segments: int = 144) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments + 1):
		var angle = lerpf(begin, end, float(i) / segments)
		var jitter = sin(angle * 11.0) * 0.0018 + cos(angle * 19.0) * 0.0009
		points.append(center + Vector2.from_angle(angle) * oval * (1.0 + jitter))
	return points

func _draw_sectors(center: Vector2, oval: Vector2) -> void:
	var step = TAU / seats.size()
	for i in range(seats.size()):
		var mid = seat_angle(i)
		var begin = mid - step / 2.0
		var end = mid + step / 2.0
		var sector = PackedVector2Array([center]) + _arc(center, oval * 0.917, begin, end, 28)
		var fill = FELT if i % 2 == 0 else SECTOR
		var hit = i == target_index
		if hit:
			fill = FELT.lerp(Sketch.WASH, 0.4 + view_height * 0.6)
		elif i == start_index:
			fill = Color("e8d4b8")
		draw_colored_polygon(sector, fill)
		var ray = Vector2.from_angle(begin) * oval
		Sketch.edge(self, center + ray * 0.16, center + ray * 0.917, Color(Sketch.LINE, 0.73), 1.0)
		var mark = Vector2.from_angle(mid) * oval
		var tint = Sketch.ACCENT if i == start_index or hit else Sketch.MUTED
		Sketch.centered(self, ui_font, "%02d" % (i + 1), center + mark * 0.945, 12, tint)
		var seat = seats[i]
		var label = "你" if seat.id == local_player_id else str(seat.name).left(10)
		var label_offset = mark.normalized().orthogonal() * lerpf(12.0, 10.0, view_height)
		var label_opacity := 1.0 - smoothstep(0.16, 0.70, view_height)
		if label_opacity > 0.0:
			Sketch.centered(self, ui_font, label, center + mark * 0.76 + label_offset, 15, Color(tint, label_opacity))
	for i in range(96):
		var ray = Vector2.from_angle(TAU * i / 96.0) * oval
		draw_line(center + ray * 0.982, center + ray * (0.993 if i % 4 else 1.005), Sketch.LINE, 0.9, true)

func _needle_shape(center: Vector2, oval: Vector2) -> PackedVector2Array:
	var ray := Vector2.from_angle(needle_angle) * oval
	var side := ray.normalized().orthogonal() * 5.5
	return PackedVector2Array([center - ray * 0.13, center + ray * 0.63 + side,
		center + ray * 0.867, center + ray * 0.63 - side])

func _draw_pointer_shadow(center: Vector2, oval: Vector2) -> void:
	var shadow := _needle_shape(center + Vector2(6.0, lerpf(5.0, 8.0, view_height)), oval)
	draw_colored_polygon(shadow, Color("554332", 0.20))

func _draw_pointer(center: Vector2, oval: Vector2) -> void:
	var lift := minf(34.0, oval.x * 0.074) * sqrt(maxf(0.0, 1.0 - pow(oval.y / oval.x, 2)))
	var pivot := center - Vector2(0, lift)
	var foot_size := Vector2(15.0, lerpf(6.5, 15.0, view_height))
	var foot := _arc(center, foot_size, 0.0, TAU, 44)
	draw_colored_polygon(foot.slice(0, foot.size() - 1), Color("746351"))
	Sketch.stroke(self, foot, Sketch.INK, 1.2)
	if lift > 0.8:
		var shaft := PackedVector2Array([pivot + Vector2(-8, 2), pivot + Vector2(8, 2),
			center + Vector2(8, 1), center + Vector2(-8, 1)])
		Sketch.plane(self, shaft, Color("9a8064"), Sketch.INK, 1.15)
		Sketch.edge(self, pivot + Vector2(-4, 3), center + Vector2(-4, 0), Color("d0b896"), 1.0)

	var pointer_thickness := lerpf(3.5, 0.0, view_height)
	if pointer_thickness > 0.35:
		draw_colored_polygon(_needle_shape(pivot + Vector2(0, pointer_thickness), oval), Color("63362c"))
	Sketch.plane(self, _needle_shape(pivot, oval), Sketch.ACCENT, Color("6a3328"), 1.0)
	var highlight := Vector2.from_angle(needle_angle) * oval * 0.78
	Sketch.edge(self, pivot + Vector2(0, -1), pivot + highlight - Vector2(0, 1), Color("c47559"), 0.9)

	_draw_instrument(pivot, oval.y / oval.x)

func _draw_instrument(pivot: Vector2, squeeze: float) -> void:
	var side_view := sqrt(maxf(0.0, 1.0 - squeeze * squeeze))
	var thickness := side_view * 25.0
	var cap := pivot - Vector2(0, thickness + side_view * 7.0)
	# 顶盖略朝玩家倾斜，读数、刻度和外沿使用同一个投影。
	var cap_squeeze := lerpf(squeeze, 1.0, 0.26)
	var radius := Vector2(DIAL_RADIUS, DIAL_RADIUS * cap_squeeze)
	if thickness > 0.5:
		var lower_edge := _arc(cap + Vector2(0, thickness), radius, 0, PI, 38)
		var upper_edge := _arc(cap, radius, PI, 0, 38)
		var casing := lower_edge + upper_edge
		draw_colored_polygon(casing, Color("b9a382"))
		Sketch.hatch(self, casing, Color(DIAL_EDGE, 0.48), 8.5, 1.0)
		Sketch.stroke(self, lower_edge, DIAL_EDGE, 1.25)

	var ring := _arc(cap, radius, 0, TAU, 80)
	draw_colored_polygon(ring.slice(0, ring.size() - 1), DIAL_BRASS)
	Sketch.stroke(self, ring, DIAL_EDGE, 1.7)
	var plate := _arc(cap, radius * 0.895, 0, TAU, 72)
	draw_colored_polygon(plate.slice(0, plate.size() - 1), Color("f1e4cc"))
	Sketch.stroke(self, plate, DIAL_LINE, 1.1)
	for i in range(36):
		var ray := Vector2.from_angle(i * TAU / 36.0) * radius
		draw_line(cap + ray * 0.91, cap + ray * 0.978, DIAL_LINE, 1.0, true)

	_draw_upper_dials(cap, cap_squeeze)

func _draw_upper_dials(cap: Vector2, squeeze: float) -> void:
	draw_set_transform_matrix(Transform2D(Vector2.RIGHT, Vector2(0, squeeze), cap))
	var reading := Rect2(Vector2(-49, -16), Vector2(46, 30))
	_draw_number_window(reading, center_steps, roundi(23 * number_scale), Sketch.INK)
	Sketch.centered(self, ui_font, center_caption, Vector2(-26.0, 24), 12, Sketch.MUTED)

	var at := Vector2(24, -2)
	draw_circle(at, 22.5, Color("e0cdad"), true, -1.0, true)
	draw_circle(at, 21.5, Color("f8ecd5"), true, -1.0, true)
	draw_arc(at, 22.5, 0, TAU, 60, DIAL_EDGE, 1.15, true)
	for i in range(12):
		var ray := Vector2.from_angle(i * TAU / 12.0 - PI / 2.0)
		draw_line(at + ray * (15.0 if i % 3 == 0 else 16.5), at + ray * 20.0, DIAL_EDGE, 1.15, true)
	if countdown_seconds >= 0:
		var angle := TAU * float(countdown_seconds) / 60.0 - PI / 2.0
		var mark := Vector2.from_angle(angle)
		Sketch.edge(self, at + mark * 15.0, at + mark * 22.0, Sketch.ACCENT, 2.0)
	Sketch.centered(self, dial_number_font if dial_number_font != null else ui_font,
		_seconds_text(), at, 23, _timer_ink())
	Sketch.centered(self, ui_font, "秒", Vector2(24.0, 30.0), 12, Sketch.MUTED)
	for y in [-44.0, 43.0]:
		draw_circle(Vector2(0, y), 1.8, DIAL_EDGE, true, -1.0, true)
		draw_line(Vector2(-0.9, y + 0.7), Vector2(0.9, y - 0.7), Sketch.PAPER, 0.8, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_number_window(rect: Rect2, value: String, font_size: int, ink: Color) -> void:
	draw_rect(rect, DIAL_EDGE)
	var paper := rect.grow(-1.3)
	draw_rect(paper, Color("fcf1da"))
	draw_line(paper.position, Vector2(paper.end.x, paper.position.y), DIAL_LINE, 1.0, true)
	var font := dial_number_font if dial_number_font != null else ui_font
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var safe_width := paper.size.x - 3.0
	if width > safe_width:
		font_size = maxi(8, floori(font_size * safe_width / width))
	Sketch.centered(self, font, value, rect.get_center(), font_size, ink)

func _seconds_text() -> String:
	return "%02d" % countdown_seconds if countdown_seconds >= 0 else "—"

func _timer_ink() -> Color:
	if countdown_seconds in [0, 1, 2, 3]:
		return Sketch.ACCENT
	return Sketch.MUTED if countdown_seconds < 0 else Sketch.INK

func _draw_opponents(center: Vector2, oval: Vector2) -> void:
	var opponents: Array = []
	for offset in range(1, seats.size() + 1):
		var seat = seats[(front_index + offset) % seats.size()]
		if seat.id != local_player_id:
			opponents.append(seat)
	var opacity = 1.0 - smoothstep(0.05, 0.92, view_height)
	var spacing = oval.x * 1.88 / maxi(1, opponents.size() - 1)
	for i in range(opponents.size()):
		var seat = opponents[i]
		var spread = 0.0 if opponents.size() == 1 else lerpf(-0.94, 0.94, float(i) / (opponents.size() - 1))
		var rim_height = sqrt(1.0 - spread * spread)
		var at = Vector2(center.x + oval.x * spread, center.y - oval.y * rim_height + 19.0)
		var figure_scale = clampf(spacing / 105.0, 0.72, 1.17) * lerpf(1.18, 0.83, rim_height)
		var rotation = spread * 0.12
		var seat_opacity = opacity if seat.get("alive", true) else opacity * 0.5
		_draw_figure(at, figure_scale, rotation, seat_opacity, int(seat.id))
		var tag = at + Vector2(0, -134.0 * figure_scale - 14.0)
		var badge: Array[String] = []
		if seat.has("hp"):
			badge.append("HP %d" % seat.hp)
		if seat.has("balance"):
			badge.append("%dr" % seat.balance)
		var label := str(seat.name).left(7)
		if not badge.is_empty():
			label += "  " + " · ".join(badge)
		Sketch.centered(self, ui_font, label, tag, 12 if opponents.size() > 7 else 14, Color(Sketch.INK, seat_opacity))
		_draw_public_cards(seat, tag + Vector2(0, -13.0), minf(spacing, 162.0), seat_opacity, i, opponents.size())

func _draw_figure(at: Vector2, factor: float, rotation: float, opacity: float, id: int) -> void:
	var shoulders = -5 + (id * 7) % 13
	var body = PackedVector2Array([Vector2(-54, 10), Vector2(-50, -24), Vector2(-38, -48),
		Vector2(-17, -56), Vector2(-12, -76), Vector2(12, -76), Vector2(16, -56),
		Vector2(shoulders + 35, -50), Vector2(47, -25), Vector2(55, 13), Vector2(20, 18), Vector2(-17, 17)])
	var head := PackedVector2Array()
	for i in range(23):
		var angle = TAU * i / 23.0
		var point = Vector2.from_angle(angle) * Vector2(23 + id % 3, 28)
		head.append(Vector2(shoulders * 0.55, -102) + point * (1.0 + sin(i * 1.89 + id) * 0.10))
	for polygon in [body, head]:
		var transformed := PackedVector2Array()
		for point in polygon:
			transformed.append(at + point.rotated(rotation) * factor)
		Sketch.plane(self, transformed, Color("34312d", opacity), Color(Sketch.INK, opacity), 1.35)
		Sketch.hatch(self, transformed, Color("171616", opacity * 0.8), 7.5 * factor, 5.1 * factor)
		Sketch.hatch(self, transformed, Color("b3a18b", opacity * 0.32), 11.3 * factor, 1.15)

func _draw_public_cards(seat: Dictionary, at: Vector2, width: float, opacity: float, index: int, count: int) -> void:
	var cards: Array = seat.cards
	if showing_actions and play_progress >= 0.5:
		cards = cards.filter(func(card): return not card.get("played", false))
	if cards.is_empty():
		return
	var columns := clampi(floori(width / 18.0), 3, 8)
	var card_width := clampf(width / (mini(cards.size(), columns) + 0.4) - 3.0, 13.0, 26.0)
	var card_size := Vector2(card_width, card_width * 1.13)
	var gap := 3.0
	var rows := ceili(float(cards.size()) / columns)
	for row in range(rows):
		var length := mini(columns, cards.size() - row * columns)
		var start := at - Vector2((length * (card_width + gap) - gap) / 2.0, (rows - row) * (card_size.y + gap))
		for column in range(length):
			var card: Dictionary = cards[row * columns + column]
			var point := start + Vector2(column * (card_width + gap), 0)
			if deal_progress < 1.0 and card.get("id", -2) == seat.get("dealt_id", -1):
				var delay := 0.30 * index / maxi(1, count - 1)
				var flight := clampf((deal_progress - delay) / 0.67, 0.0, 1.0)
				if flight < 1.0:
					if flight > 0.0:
						_opponent_deals.append({"target": Transform2D(0.0, point + card_size / 2.0),
							"extent": card_size, "card": card, "progress": flight})
					continue
			_draw_seat_card(Rect2(point, card_size), card, opacity)

func place_local_card(slot: int, from: Vector2, extent: Vector2, angle: float) -> void:
	if _placements.has(slot):
		_placements[slot].tween.kill()
	var tween := create_tween()
	var placement := {"origin": from, "extent": extent, "angle": angle, "progress": 0.0, "tween": tween}
	_placements[slot] = placement
	tween.tween_method(func(progress: float):
		placement.progress = progress
		queue_redraw(), 0.0, 1.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func():
		_placements.erase(slot)
		queue_redraw())

func clear_placements() -> void:
	for placement in _placements.values():
		placement.tween.kill()
	_placements.clear()
	queue_redraw()

func _table_card_transform(point: Vector2, angle: float, squeeze: float, factor: float = 1.0) -> Transform2D:
	var projection := Vector2(1, squeeze) * factor
	return Transform2D(Vector2.RIGHT.rotated(angle) * projection, Vector2.DOWN.rotated(angle) * projection, point)

func _draw_table_cards(center: Vector2, oval: Vector2) -> void:
	var width := clampf(oval.x * 0.113, 29.0, 51.0)
	var card_size := Vector2(width, width * 1.39)
	var squeeze := oval.y / oval.x
	for index in range(seats.size()):
		var id: int = seats[index].id
		var cards: Dictionary = table_cards.get(id, {})
		if cards.is_empty():
			continue
		var angle := seat_angle(index)
		var direction := Vector2.from_angle(angle)
		var ray := direction * oval
		var tangent := Vector2.from_angle(angle - PI / 2.0) * Vector2(1, squeeze)
		var factor: float = 1.0 + direction.y * 0.15 * (1.0 - view_height)
		for slot in range(2):
			if not cards.has(slot):
				continue
			var card: Dictionary = cards[slot]
			if card.get("discard", false) and play_progress >= 0.5:
				continue
			# 地面牌避开扇区中线，给停下的指针和牌面留出空间。
			var offset := (float(slot) - 0.5) * (width + 12.0) if cards.size() > 1 else width * 0.68
			var point := center + ray * 0.60 + tangent * offset * factor
			var transform := _table_card_transform(point, angle - PI / 2.0, squeeze, factor)
			var extent := card_size
			if id == local_player_id and _placements.has(slot):
				var placement: Dictionary = _placements[slot]
				var amount: float = placement.progress
				var origin := get_global_transform().affine_inverse() * Vector2(placement.origin)
				transform = Transform2D(placement.angle, origin).interpolate_with(transform, amount)
				transform.origin.y -= 36.0 * sin(PI * amount)
				extent = Vector2(placement.extent).lerp(extent, amount)
			var face_up: bool = card.get("face_up", false)
			if card.get("flip", false) or card.get("discard", false):
				extent.x = maxf(3.0, extent.x * absf(cos(play_progress * PI)))
				face_up = face_up and play_progress >= 0.5
			_draw_projected_card(transform, extent, card, face_up)

func _deck_transform(center: Vector2, oval: Vector2) -> Transform2D:
	var at := center + oval * Vector2(-0.73, 0.425) - Vector2(0, 10)
	return _table_card_transform(at, -0.16, oval.y / oval.x)

func _draw_deck(center: Vector2, oval: Vector2) -> void:
	var opacity := 1.0 - smoothstep(0.08, 0.66, view_height)
	if opacity <= 0.0:
		return
	var transform := _deck_transform(center, oval)
	var rect := Rect2(-DECK_SIZE / 2.0, DECK_SIZE)
	for layer in range(4, 0, -1):
		var sheet := transform
		sheet.origin += Vector2(layer * 0.6, layer * 2.5)
		draw_set_transform_matrix(sheet)
		draw_rect(rect, Color("e4d4ba", opacity))
		draw_rect(rect, Color(Sketch.MUTED, opacity * 0.8), false, 1.0)
	draw_set_transform_matrix(transform)
	_draw_covered_card(rect, opacity)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_deal_flights(center: Vector2, oval: Vector2) -> void:
	if not is_zero_approx(view_height):
		return
	var deck := _deck_transform(center, oval)
	for flight in _opponent_deals:
		_draw_dealing_card(deck, flight.target, flight.extent, flight.card, flight.progress, 20)
	if not self_deal.is_empty() and self_deal.progress > 0.34:
		var progress := smoothstep(0.34, 1.0, float(self_deal.progress))
		var to_local := get_global_transform().affine_inverse()
		var target := to_local * Transform2D(self_deal.angle, self_deal.target)
		_draw_dealing_card(deck, target, self_deal.extent, self_deal.card, progress, 34)

func _draw_dealing_card(deck: Transform2D, target: Transform2D, extent: Vector2, card: Dictionary,
		progress: float, font_max: int) -> void:
	var pose := deck.interpolate_with(target, progress)
	pose.origin.y -= sin(progress * PI) * 47.0
	var card_size := DECK_SIZE.lerp(extent, progress)
	if progress > 0.46 and progress < 0.78:
		var turn := inverse_lerp(0.46, 0.78, progress)
		card_size.x *= maxf(0.08, absf(cos(turn * PI)))
	_draw_projected_card(pose, card_size, card, progress >= 0.62, font_max)

func _draw_projected_card(transform: Transform2D, extent: Vector2, card: Dictionary,
		face_up: bool, font_max: int = 20) -> void:
	var rect := Rect2(-extent / 2.0, extent)
	var shadow := transform
	shadow.origin += Vector2(2, 2.5)
	draw_set_transform_matrix(shadow)
	draw_rect(rect, Color(Sketch.INK, 0.22))
	draw_set_transform_matrix(transform)
	if face_up:
		_draw_seat_card(rect, card, 1.0, font_max)
	else:
		_draw_covered_card(rect)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_covered_card(rect: Rect2, opacity: float = 1.0) -> void:
	draw_rect(rect, Color("463c34", opacity))
	if rect.size.x < 9.0:
		return
	draw_rect(rect.grow(-3.0), Color("c6ab8b", opacity), false, 1.0)
	var at := rect.get_center()
	var half := minf(rect.size.x, rect.size.y) * 0.24
	var diamond := PackedVector2Array([at + Vector2(0, -half), at + Vector2(half, 0),
		at + Vector2(0, half), at + Vector2(-half, 0)])
	Sketch.plane(self, diamond, Color("725a49", opacity), Color("d6bb97", opacity), 1.0)
	Sketch.hatch(self, diamond, Color("ac8d72", opacity), 3.2, 0.9)

func _draw_seat_card(rect: Rect2, card: Dictionary, opacity: float, font_max: int = 20) -> void:
	var played: bool = card.get("played", false)
	var tint := Sketch.ACCENT if played else Sketch.INK
	var face_up: bool = card.get("face_up", false)
	var fill := Sketch.CARD if face_up else Color("d7cbb8")
	draw_rect(rect, Color(fill, opacity))
	var p := rect.position
	var outline := PackedVector2Array([p, Vector2(rect.end.x, p.y), rect.end, Vector2(p.x, rect.end.y), p])
	draw_polyline(outline, Color(tint, opacity * 0.85), 1.2, true)
	var mark := str(card.get("value", ""))
	if played:
		mark = card.get("caption", mark)
	elif not face_up:
		var quantity := int(card.get("quantity", 1))
		mark = "▧" if quantity == 1 else "▧%d" % quantity
	var font_size := clampi(roundi(rect.size.x * (0.46 if mark.length() < 3 else 0.36)), 1, font_max)
	var points: String = card.get("points", "")
	Sketch.centered(self, ui_font, mark, rect.get_center() - Vector2(0, 7 if not points.is_empty() else 0), font_size, Color(tint, opacity))
	if not points.is_empty():
		Sketch.centered(self, ui_font, points, rect.get_center() + Vector2(0, 8), font_size, Color(tint, opacity))
