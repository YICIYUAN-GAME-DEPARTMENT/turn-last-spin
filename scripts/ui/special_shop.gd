@tool
extends Control

signal view_changed(amount: float)
const Sketch = preload("res://scripts/ui/sketch_ink.gd")
const Rules = preload("res://scripts/core/game_rules.gd")
const HandCard = preload("res://scripts/ui/hand_card.gd")
const KINDS = ["defense", "change", "super"]
const WIDTH = 564.0
const HEIGHT = 366.0
const SLOT_X = [98.0, 282.0, 466.0]
const CARD_SIZE = Vector2(104, 140)
const FRONT = Color("eadcc4")
const TOP = Color("f2e9d5")
const SIDE = Color("d9c5a4")

var progress = 0.0:
	set(amount):
		progress = amount
		_position_controls()
		queue_redraw()
		view_changed.emit(amount)
var is_open = false
var available = false
var game: Node
var _can_batch = false
var balance = 0
var offers: Array = []

var entry: Button
var back: Button
var pickup_buttons: Array[Button] = []
var reduce_buttons: Array[Button] = []
var add_buttons: Array[Button] = []
var card_buttons: Array[Button] = []
var _amounts = [1, 1, 1]
var _focus_slot = -1
var _hover_slot = -1
var _camera: Tween
var _font: Font
var _report = ""
var _deliveries: Array[Dictionary] = []
var _delivery: Dictionary = {}
var _delivery_time = 0.0

func _ready() -> void:
	_font = get_theme_default_font()
	resized.connect(_on_resize)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	if Engine.is_editor_hint():
		return
	entry = _button("", "打开卡牌商店", &"SketchHitbox")
	entry.pressed.connect(_enter)
	entry.mouse_entered.connect(queue_redraw)
	entry.mouse_exited.connect(queue_redraw)
	entry.focus_entered.connect(queue_redraw)
	entry.focus_exited.connect(queue_redraw)
	back = _button("←  返回牌桌", "返回牌桌")
	back.pressed.connect(close)
	for slot in range(SLOT_X.size()):
		var card = _button("", "商品详情", &"SketchHitbox")
		card.mouse_entered.connect(_hover_card.bind(slot))
		card.mouse_exited.connect(_hover_card.bind(-1))
		card.focus_entered.connect(_focus_card.bind(slot))
		card.focus_exited.connect(_focus_card.bind(-1))
		card_buttons.append(card)
		var reduce = _button("−", "减少购买数量")
		reduce.pressed.connect(_change_amount.bind(slot, -1))
		reduce_buttons.append(reduce)
		var add = _button("+", "增加购买数量")
		add.pressed.connect(_change_amount.bind(slot, 1))
		add_buttons.append(add)
		var buy = _button("购买", "购买卡牌", &"PrimaryButton")
		buy.pressed.connect(_request_purchase.bind(slot))
		pickup_buttons.append(buy)
	_position_controls()

func _button(caption: String, description: String, variation: StringName = &"Button") -> Button:
	var button = Button.new()
	button.text = caption
	button.accessibility_name = description
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.theme_type_variation = variation
	button.add_theme_font_size_override("font_size", 16)
	add_child(button)
	if caption in ["+", "−"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style = button.get_theme_stylebox(state).duplicate()
			style.content_margin_left = 5
			style.content_margin_right = 5
			button.add_theme_stylebox_override(state, style)
	return button

func present(blocked: bool) -> void:
	offers = KINDS.map(func(kind): return {
		"kind": kind,
		"price": int(game.card_prices.get(kind, -1))
	}) if not game.card_prices.is_empty() else []
	balance = game.balance
	_can_batch = game.batch_purchases
	available = not blocked and not offers.is_empty() and game.can_buy_cards()
	_report = game.economy_notice
	if is_open and not available:
		close()
	_position_controls()
	queue_redraw()

func reset() -> void:
	is_open = false
	available = false
	_can_batch = false
	offers = []
	balance = 0
	_hover_slot = -1
	_focus_slot = -1
	_amounts = [1, 1, 1]
	_report = ""
	_deliveries.clear()
	_delivery.clear()
	set_process(false)
	if _camera and _camera.is_valid():
		_camera.kill()
	progress = 0.0

func _enter() -> void:
	if not available or is_open:
		return
	entry.release_focus()
	is_open = true
	_report = ""
	_change_view(1.0)

func close() -> void:
	if not is_open:
		return
	is_open = false
	_hover_slot = -1
	_focus_slot = -1
	_change_view(0.0)

func _change_view(destination: float) -> void:
	if _camera and _camera.is_valid():
		_camera.kill()
	_position_controls()
	_camera = create_tween()
	_camera.tween_property(self, "progress", destination, 0.56).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func _change_amount(slot: int, adjustment: int) -> void:
	_amounts[slot] = clampi(_amounts[slot] + adjustment, 0, _affordable(slot))
	_refresh_controls()
	queue_redraw()

func _affordable(slot: int) -> int:
	var price = int(offers[slot].price)
	if price < 0:
		return 0
	if not _can_batch:
		return int(balance >= price)
	if price == 0:
		return 9223372036854775806
	@warning_ignore("integer_division")
	return balance / price

func _request_purchase(slot: int) -> void:
	if not is_open or not available:
		return
	var quantity: int = _amounts[slot] if _can_batch else 1
	game.buy_special_cards({KINDS[slot]: quantity})

func _hover_card(slot: int) -> void:
	_hover_slot = slot
	queue_redraw()

func _focus_card(slot: int) -> void:
	_focus_slot = slot
	queue_redraw()

func _on_resize() -> void:
	_position_controls()
	queue_redraw()

func _machine_scale() -> float:
	return lerpf(0.23, minf(1.02, minf(size.y / 865.0, size.x / 1000.0)), progress)

func _machine_position() -> Vector2:
	var small = Vector2(42, size.y - 164)
	var large = Vector2(size.x * 0.5 - 349 * _machine_scale(), size.y * 0.353)
	return small.lerp(large, progress)

func _position_controls() -> void:
	if not is_instance_valid(entry):
		return
	mouse_filter = Control.MOUSE_FILTER_STOP if is_open or progress > 0.001 else Control.MOUSE_FILTER_IGNORE
	entry.position = Vector2(32, size.y - 195)
	entry.size = Vector2(181, 145)
	entry.visible = progress <= 0.001 and not is_open and not offers.is_empty()
	back.position = Vector2(34, size.y - 65)
	back.size = Vector2(163, 39)
	back.visible = progress > 0.84
	back.disabled = not is_open
	var controls_visible = is_open and progress > 0.985 and offers.size() == SLOT_X.size()
	var origin = _machine_position()
	var zoom = _machine_scale()
	for slot in range(SLOT_X.size()):
		var x = SLOT_X[slot]
		_place(card_buttons[slot], origin, zoom, Vector2(x - CARD_SIZE.x / 2, 67), CARD_SIZE, controls_visible)
		_place(reduce_buttons[slot], origin, zoom, Vector2(x - 62, 265), Vector2(34, 32), controls_visible and _can_batch)
		_place(add_buttons[slot], origin, zoom, Vector2(x + 28, 265), Vector2(34, 32), controls_visible and _can_batch)
		_place(pickup_buttons[slot], origin, zoom, Vector2(x - 62, 306), Vector2(124, 37), controls_visible)
	_refresh_controls()

func _place(button: Button, origin: Vector2, zoom: float, point: Vector2, extent: Vector2, shown: bool) -> void:
	button.position = origin + point * zoom
	button.size = extent * zoom
	button.visible = shown

func _refresh_controls() -> void:
	if not is_instance_valid(entry):
		return
	entry.disabled = not available
	entry.accessibility_name = "打开特殊牌商店，余额 %d 筹码" % balance
	if offers.size() != SLOT_X.size():
		return
	for slot in range(SLOT_X.size()):
		var limit := _affordable(slot)
		_amounts[slot] = clampi(_amounts[slot], 0, maxi(1, limit)) if _can_batch else 1
		var quantity: int = _amounts[slot]
		var offer = offers[slot]
		reduce_buttons[slot].disabled = quantity == 0
		add_buttons[slot].disabled = quantity >= limit
		pickup_buttons[slot].disabled = quantity == 0 or quantity > limit
		pickup_buttons[slot].text = ("购买 ×%d" % quantity) if quantity > 1 else "购买"
		card_buttons[slot].accessibility_name = "%s，单价 %dr" % [HandCard.SPECIAL_NAMES[offer.kind], offer.price]

func animate_purchase(order: Dictionary) -> void:
	if not is_open:
		return
	var cards: Array[Dictionary] = []
	var cost := 0
	for offer in offers:
		var quantity := int(order.get(offer.kind, 0))
		cost += quantity * int(offer.price)
		for index in range(mini(quantity, 4)):
			cards.append({"kind": offer.kind, "quantity": quantity - 3 if index == 3 else 1})
	if not cards.is_empty():
		_deliveries.append({"cards": cards, "chips": mini(7, cost)})
		set_process(true)

func _process(delta: float) -> void:
	if _delivery.is_empty() and not _deliveries.is_empty():
		_delivery = _deliveries.pop_front()
		_delivery_time = 0.0
	if _delivery.is_empty():
		set_process(false)
		return
	_delivery_time += delta
	var count = _delivery.cards.size()
	var last_card = (count - 1) * _stagger(count)
	if _delivery_time > _dispense_start() + 0.80 + last_card:
		_delivery.clear()
	queue_redraw()

func _stagger(count: int) -> float:
	return minf(0.11, 0.78 / maxi(1, count - 1))

func _dispense_start() -> float:
	var count = int(_delivery.chips)
	return 0.16 if count == 0 else 0.63 + (count - 1) * _stagger(count)

func _draw() -> void:
	if _font == null or size.x < 200:
		return
	if progress <= 0.001 and offers.is_empty() and not Engine.is_editor_hint():
		return
	var focus_opacity = smoothstep(0.58, 0.98, progress)
	if progress > 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(Sketch.PAPER, smoothstep(0.06, 0.70, progress) * 0.67))
	if focus_opacity > 0.0:
		_draw_shop_heading(focus_opacity)
	var origin = _machine_position()
	var zoom = _machine_scale()
	draw_set_transform(origin, 0.0, Vector2.ONE * zoom)
	var depth = Vector2(lerpf(132, 118, progress), lerpf(-110, -104, progress))
	_draw_box(depth)
	if progress > 0.72 and not _delivery.is_empty():
		_draw_delivery(depth)
	if focus_opacity > 0.0 and offers.size() == SLOT_X.size():
		_draw_goods(focus_opacity)
	draw_set_transform(Vector2.ZERO)
	if progress < 0.50:
		_draw_entry(1.0 - smoothstep(0.03, 0.5, progress))
	if focus_opacity > 0.5:
		_draw_details(origin, zoom, focus_opacity)

func _draw_shop_heading(opacity: float) -> void:
	draw_string(_font, Vector2(35, 59), "特殊牌商店", HORIZONTAL_ALIGNMENT_LEFT, -1, 31, Color(Sketch.INK, opacity))
	Sketch.chip(self, Vector2(size.x - 180, 52), 13, Color(Sketch.ACCENT, opacity))
	Sketch.centered(self, _font, "筹码  %dr" % balance, Vector2(size.x - 100, 52), 20, Color(Sketch.INK, opacity))
	if not _report.is_empty():
		Sketch.centered(self, _font, _report, Vector2(size.x * 0.5, 136), 16, Color(Sketch.ACCENT, opacity))

func _draw_entry(opacity: float) -> void:
	var color = Sketch.ACCENT if is_instance_valid(entry) and (entry.is_hovered() or entry.has_focus()) else Sketch.INK
	var y = size.y - 59
	draw_string(_font, Vector2(45, y + 1.5), "卡牌商店  ↗", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(color, opacity))
	Sketch.chip(self, Vector2(52, y + 23), 7.0, Color(Sketch.ACCENT, opacity))

func _draw_box(depth: Vector2) -> void:
	var top_right = Vector2(WIDTH, 0)
	var bottom_right = Vector2(WIDTH, HEIGHT)
	var foot = Vector2(0, HEIGHT)
	var shadow = PackedVector2Array([foot + Vector2(-9, 7), bottom_right + Vector2(18, 7),
		bottom_right + depth + Vector2(24, 7), foot + depth + Vector2(9, 7)])
	draw_colored_polygon(shadow, Color("dcd0bb"))
	var rim = PackedVector2Array([Vector2.ZERO, top_right, top_right + depth, depth])
	var side = PackedVector2Array([top_right, top_right + depth, bottom_right + depth, bottom_right])
	var front = PackedVector2Array([Vector2.ZERO, top_right, bottom_right, Vector2(0, HEIGHT)])
	Sketch.plane(self, rim, TOP, Sketch.INK, 2.1)
	Sketch.plane(self, side, SIDE, Sketch.INK, 2.1)
	Sketch.hatch(self, side, Color(Sketch.MUTED, 0.27), 13.0, 1.25)
	Sketch.plane(self, front, FRONT, Sketch.INK, 2.1)
	Sketch.plane(self, PackedVector2Array([Vector2(13, 12), Vector2(WIDTH - 15, 14),
		Vector2(WIDTH - 14, HEIGHT - 15), Vector2(13, HEIGHT - 12)]), FRONT, Sketch.LINE, 1.15)
	for corner in [Vector2(21, 22), Vector2(WIDTH - 22, 22), Vector2(21, HEIGHT - 22), Vector2(WIDTH - 22, HEIGHT - 22)]:
		draw_circle(corner, 3.0, Sketch.MUTED, true, -1, true)
		draw_line(corner + Vector2(-2, 1), corner + Vector2(2, -1), TOP, 0.85, true)
	for slot in range(SLOT_X.size()):
		var x = SLOT_X[slot]
		var surround = Rect2(Vector2(x - 64, 55), Vector2(128, 164))
		draw_rect(surround, Color("b8a183"))
		draw_rect(surround.grow(-2.5), Color("6f6151"))
		draw_rect(surround.grow(-5.5), Color("50463c"))
		draw_rect(Rect2(Vector2(x - 62, 306), Vector2(124, 37)), Sketch.ACCENT)
		if progress < 0.85:
			_draw_card(Rect2(Vector2(x - CARD_SIZE.x / 2, 67), CARD_SIZE), KINDS[slot])
		if slot > 0:
			Sketch.edge(self, Vector2(x - 92, 51), Vector2(x - 92, HEIGHT - 24), Color(Sketch.LINE, 0.69), 1.05)
	var coin = _coin_slot(depth)
	var slit = PackedVector2Array([coin + Vector2(-60, 8), coin + Vector2(53, 8), coin + Vector2(63, -8), coin + Vector2(-50, -8)])
	Sketch.plane(self, slit, Sketch.INK, Sketch.MUTED, 2)
	Sketch.edge(self, slit[0] - Vector2(10, -4), slit[1] + Vector2(8, 5), Color(Sketch.MUTED, 0.65), 1.5)
	var tray = _card_outlet(depth)
	var mouth = PackedVector2Array([tray + Vector2(-9, -48), tray + Vector2(6, -58), tray + Vector2(8, 45), tray + Vector2(-7, 56)])
	Sketch.plane(self, mouth, Sketch.INK, Sketch.MUTED, 2)
	if progress > 0.6:
		var opacity = smoothstep(0.6, 0.95, progress)
		Sketch.centered(self, _font, "投币口", coin + Vector2(1, -24), 16, Color(Sketch.MUTED, opacity))
		Sketch.centered(self, _font, "出卡口", tray + Vector2(8, 73), 13, Color(Sketch.MUTED, opacity))

func _coin_slot(depth: Vector2) -> Vector2:
	return Vector2(WIDTH * 0.49, 0) + depth * 0.53

func _card_outlet(depth: Vector2) -> Vector2:
	return Vector2(WIDTH, HEIGHT * 0.48) + depth * 0.59

func _draw_goods(opacity: float) -> void:
	var slot_detail = _hover_slot if _hover_slot >= 0 else _focus_slot
	for slot in range(SLOT_X.size()):
		var x = SLOT_X[slot]
		var offer = offers[slot]
		_draw_card(Rect2(Vector2(x - CARD_SIZE.x / 2.0, 67), CARD_SIZE), offer.kind, slot_detail == slot)
		var tint = Color(Sketch.ACCENT, opacity)
		Sketch.chip(self, Vector2(x - 42, 239), 9.0, tint)
		Sketch.centered(self, _font, "%dr / 张" % offer.price, Vector2(x + 12, 239), 18, tint)
		if _can_batch:
			Sketch.centered(self, _font, str(_amounts[slot]), Vector2(x, 280), 17, Color(Sketch.INK, opacity))

func _draw_card(rect: Rect2, kind: String, highlighted := false, quantity := 1) -> void:
	var title: String = HandCard.SPECIAL_NAMES[kind]
	Sketch.card_face(self, _font, rect, title.left(1) if rect.size.x >= 25 else "", highlighted)
	if rect.size.x >= 65:
		var caption := title if quantity == 1 else "%s ×%d" % [title, quantity]
		Sketch.centered(self, _font, caption, rect.get_center() + Vector2(0, rect.size.y * 0.28), 13, Sketch.MUTED)

func _draw_details(origin: Vector2, zoom: float, opacity: float) -> void:
	var slot = _hover_slot if _hover_slot >= 0 else _focus_slot
	if slot < 0 or slot >= offers.size():
		return
	var kind: String = offers[slot].kind
	var price = int(offers[slot].price)
	var at = origin + Vector2(SLOT_X[slot], 49) * zoom
	var panel = Rect2(at - Vector2(137, 98), Vector2(274, 86))
	draw_rect(Rect2(panel.position + Vector2(4, 5), panel.size), Color(Sketch.INK, opacity * 0.16))
	draw_rect(panel, Color(Sketch.CARD, opacity))
	draw_rect(panel, Color(Sketch.ACCENT, opacity), false, 1.3)
	draw_string(_font, panel.position + Vector2(13, 24), "%s  ·  %dr / 张" % [HandCard.SPECIAL_NAMES[kind], price], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Sketch.ACCENT)
	var description: String = HandCard.SPECIAL_HINTS[kind]
	if kind == "defense" and game.game_mode == Rules.Mode.GREED:
		description = "出牌阶段使用，被命中时保住筹码"
	elif kind == "super":
		description = "结算阶段使用，追加 +%d 格位移" % game.super_steps
	draw_string(_font, panel.position + Vector2(13, 48), description, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Sketch.INK)
	draw_string(_font, panel.position + Vector2(13, 70), "购入后进入自己的暗牌库存。", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Sketch.MUTED)

func _draw_delivery(depth: Vector2) -> void:
	var coin = _coin_slot(depth)
	var chip_count = int(_delivery.chips)
	for index in range(chip_count):
		var time = (_delivery_time - index * _stagger(chip_count)) / 0.59
		if time < 0.0 or time >= 1.0:
			continue
		var start = coin + Vector2(220 + index % 3 * 13, -129)
		var at = start.lerp(coin, time * time) + Vector2(20, -72) * sin(PI * time)
		var radius = lerpf(18, 12, time)
		var tilt = maxf(0.17, absf(cos(time * TAU * 1.3))) * lerpf(1.0, 0.40, time)
		Sketch.chip(self, at, radius, Sketch.ACCENT, tilt)
	var outlet = _card_outlet(depth)
	var card_count = _delivery.cards.size()
	for index in range(card_count):
		var time = (_delivery_time - _dispense_start() - index * _stagger(card_count)) / 0.80
		if time < 0.0 or time >= 1.0:
			continue
		var advance = smoothstep(0.0, 0.64, time)
		var drop = smoothstep(0.57, 1.0, time)
		var amount = lerpf(3, 82, advance)
		var at = outlet + Vector2(2.0 + advance * 32.0 + drop * 29.0, -43 + advance * -37.0 + drop * 104.0)
		var detail = Rect2(at, Vector2(amount, 87))
		if drop > 0.86:
			continue
		_draw_card(detail, _delivery.cards[index].kind, true, _delivery.cards[index].quantity)
