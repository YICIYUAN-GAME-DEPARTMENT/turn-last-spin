@tool
extends Control

const Cards = preload("res://scripts/ui/player_cards.gd")
const MINT = Color("91e7c2")
const CORAL = Color("ffb28e")
const INK = Color("0a141d")
var seats: Array = []
var local_player_id = 0
var start_index = 0
var target_index = -1
var center_caption = "初始"
var center_steps = "1"
var needle_angle = -PI / 2.0:
	set(value):
		needle_angle = value
		queue_redraw()
var ui_font: Font

@export_range(2, 12, 1) var preview_players: int = 8:
	set(number):
		preview_players = number
		if Engine.is_editor_hint() and is_node_ready():
			_editor_preview()

func _ready() -> void:
	ui_font = get_theme_default_font()
	resized.connect(queue_redraw)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Engine.is_editor_hint():
		_editor_preview()

func _editor_preview() -> void:
	seats.clear()
	for i in range(preview_players):
		seats.append({"id": i, "name": "玩家" if i == 0 else String.chr(96 + i),
			"alive": true, "cards": [{"id": i, "value": (i * 3 + 2) % preview_players + 1,
			"face_up": true, "played": false, "sign": 0}]})
	start_index = 0
	center_steps = "1"
	queue_redraw()

func _draw() -> void:
	if seats.is_empty() or ui_font == null:
		return
	var center = size / 2.0
	var radius = minf(size.x, size.y) * 0.465
	var count = seats.size()
	var step = TAU / count
	draw_circle(center + Vector2(0, 10), radius + 9, Color(0, 0, 0, 0.22))
	draw_circle(center, radius + 9, Color("21363e"))
	draw_arc(center, radius + 9, 0, TAU, 160, Color("45606a"), 1.0, true)
	for i in range(count):
		var mid = -PI / 2.0 + i * step
		var begin = mid - step / 2.0 + 0.006
		var end = mid + step / 2.0 - 0.006
		var points = PackedVector2Array([center])
		for j in range(41):
			points.append(center + Vector2.from_angle(lerpf(begin, end, j / 40.0)) * radius)
		var color = Color("18333e") if i % 2 == 0 else Color("122a35")
		if seats[i].id == local_player_id:
			color = Color("25483e")
		if i == start_index:
			color = Color("493c33")
		if i == target_index:
			color = Color("694336")
		draw_colored_polygon(points, color)
		draw_line(center, center + Vector2.from_angle(begin) * radius, Color("091b25"), 2, true)
		if i == start_index:
			draw_circle(center + Vector2.from_angle(mid) * (radius + 5), 4, CORAL)
	for tick in range(80):
		var angle = tick * TAU / 80.0
		var vector = Vector2.from_angle(angle)
		draw_line(center + vector * (radius + 14), center + vector * (radius + (21 if tick % 5 == 0 else 17)), Color("3b5660"), 1, true)
	var direction = Vector2.from_angle(needle_angle)
	var normal = direction.orthogonal()
	var pointer_color = CORAL if target_index >= 0 else MINT
	draw_line(center, center + direction * radius * 0.90, pointer_color, 4, true)
	draw_colored_polygon(PackedVector2Array([center + direction * radius * 0.96,
		center + direction * radius * 0.86 + normal * 10,
		center + direction * radius * 0.86 - normal * 10]), pointer_color)
	draw_circle(center, radius * 0.235, INK)
	draw_arc(center, radius * 0.235, 0, TAU, 96, Color("4e6d69"), 1.5, true)
	center_text(center_caption, center + Vector2(0, -34), 13, Color("9fb5bb"))
	center_text(center_steps, center + Vector2(0, 3), 44 if center_steps.length() < 4 else 34, pointer_color)
	center_text("格", center + Vector2(0, 39), 12, Color("9fb5bb"))
	for i in range(count):
		var angle = -PI / 2.0 + i * step
		draw_seat(seats[i], center + Vector2.from_angle(angle) * radius * 0.70, radius, count)

func draw_seat(seat: Dictionary, position: Vector2, radius: float, count: int) -> void:
	var own = seat.id == local_player_id
	var alive = seat.get("alive", true)
	var avatar_radius = clampf(radius * 0.067, 19, 28)
	var accent = MINT if own else Color("9ab6c4")
	if not alive:
		accent = CORAL
	draw_circle(position + Vector2(0, 3), avatar_radius + 3, Color(0, 0, 0, 0.22))
	draw_circle(position, avatar_radius + 2, accent)
	draw_circle(position, avatar_radius, Color("102b30") if own else Color("15242f"))
	var avatar_text = "你" if own else str(seat.name).left(1).to_upper()
	center_text(avatar_text, position, int(avatar_radius * 0.85), accent)
	if not alive:
		draw_line(position + Vector2(-avatar_radius * 0.7, -avatar_radius * 0.7),
			position + Vector2(avatar_radius * 0.7, avatar_radius * 0.7), CORAL, 2, true)
	var caption: String = "你" if own else str(seat.name)
	if seat.has("hp"):
		caption += " · HP %d" % int(seat["hp"])
	center_text(caption, position + Vector2(0, avatar_radius + 19), 13, accent)
	var cards = seat.get("cards", [])
	var card_width: float = clampf(radius * 0.071, 21, 29)
	var card_height: float = card_width * 1.38
	var columns = 3 if count >= 9 else (4 if count >= 5 else 6)
	var gap = 3.0
	var rows = ceili(float(cards.size()) / columns)
	var height = rows * (card_height + gap) - gap if rows > 0 else 0.0
	var first_y = position.y - avatar_radius - 13 - height
	for row in range(rows):
		var in_row = mini(columns, cards.size() - row * columns)
		var width = in_row * (card_width + gap) - gap
		for column in range(in_row):
			var point = Vector2(position.x - width / 2.0 + column * (card_width + gap), first_y + row * (card_height + gap))
			Cards.draw_card(self, Rect2(point, Vector2(card_width, card_height)), cards[row * columns + column], ui_font)

func center_text(value: String, position: Vector2, font_size: int, color: Color) -> void:
	var width = ui_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(ui_font, position + Vector2(-width / 2.0, font_size * 0.33), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
