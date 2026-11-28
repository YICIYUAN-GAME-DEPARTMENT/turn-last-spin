@tool
extends Control
## 冷战“暗市补给箱”特殊牌商店：左下角公文包入口 + 居中报刊目录浮层

signal view_changed(amount: float)

const Ink = preload("res://scripts/ui/editorial_ink.gd")
const Rules = preload("res://scripts/core/game_rules.gd")
const HandCard = preload("res://scripts/ui/hand_card.gd")

const KINDS: Array[String] = ["defense", "change", "super"]
const CATALOG_SIZE := Vector2(732.0, 444.0)

var progress: float = 0.0:
	set(amount):
		progress = amount
		_position_controls()
		queue_redraw()
		view_changed.emit(amount)
var is_open: bool = false
var available: bool = false
var game: Node
var _can_batch: bool = false
var balance: int = 0
var offers: Array[Dictionary] = []

var entry: Button
var back: Button
var pickup_buttons: Array[Button] = []
var reduce_buttons: Array[Button] = []
var add_buttons: Array[Button] = []
var card_buttons: Array[Button] = []
var _amounts: Array[int] = [1, 1, 1]
var _hover_slot: int = -1
var _focus_slot: int = -1
var _stamp_timers: Array[float] = [0.0, 0.0, 0.0]
var _camera: Tween
var _font: Font
var _report: String = ""

func _ready() -> void:
	_font = get_theme_default_font()
	resized.connect(_on_resize)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	if Engine.is_editor_hint():
		return
	entry = _make_button("", "打开特殊牌商店", &"GhostButton")
	entry.flat = true
	entry.pressed.connect(_enter)
	entry.mouse_entered.connect(queue_redraw)
	entry.mouse_exited.connect(queue_redraw)
	entry.focus_entered.connect(queue_redraw)
	entry.focus_exited.connect(queue_redraw)

	back = _make_button("←  返回牌桌", "返回牌桌", &"Button")
	back.pressed.connect(close)

	for slot in range(KINDS.size()):
		var card := _make_button("", "商品详情", &"GhostButton")
		card.flat = true
		card.mouse_entered.connect(_hover_card.bind(slot))
		card.mouse_exited.connect(_hover_card.bind(-1))
		card.focus_entered.connect(_focus_card.bind(slot))
		card.focus_exited.connect(_focus_card.bind(-1))
		card_buttons.append(card)

		var reduce := _make_button("−", "减少购买数量", &"Button")
		reduce.pressed.connect(_change_amount.bind(slot, -1))
		reduce_buttons.append(reduce)

		var add := _make_button("+", "增加购买数量", &"Button")
		add.pressed.connect(_change_amount.bind(slot, 1))
		add_buttons.append(add)

		var buy := _make_button("购买", "购买卡牌", &"InkButton")
		buy.pressed.connect(_request_purchase.bind(slot))
		pickup_buttons.append(buy)
	_position_controls()

func _make_button(caption: String, description: String, variation: StringName) -> Button:
	var btn := Button.new()
	btn.text = caption
	btn.accessibility_name = description
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.theme_type_variation = variation
	btn.add_theme_font_size_override("font_size", 14)
	add_child(btn)
	return btn

func present(blocked: bool) -> void:
	offers.clear()
	if game != null and not game.card_prices.is_empty():
		for kind in KINDS:
			offers.append({
				"kind": kind,
				"price": int(game.card_prices.get(kind, -1))
			})
	balance = int(game.balance) if game != null else 0
	_can_batch = bool(game.batch_purchases) if game != null else false
	available = game != null and not blocked and not offers.is_empty() and game.can_buy_cards()
	_report = str(game.economy_notice) if game != null else ""
	if is_open and not available:
		close()
	_position_controls()
	queue_redraw()

func reset() -> void:
	is_open = false
	available = false
	_can_batch = false
	offers.clear()
	balance = 0
	_hover_slot = -1
	_focus_slot = -1
	_amounts = [1, 1, 1]
	_stamp_timers = [0.0, 0.0, 0.0]
	_report = ""
	set_process(false)
	if _camera != null and _camera.is_valid():
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
	if _camera != null and _camera.is_valid():
		_camera.kill()
	_position_controls()
	_camera = create_tween()
	_camera.tween_property(self, "progress", destination, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _change_amount(slot: int, adjustment: int) -> void:
	_amounts[slot] = clampi(_amounts[slot] + adjustment, 0, _affordable(slot))
	_refresh_controls()
	queue_redraw()

func _affordable(slot: int) -> int:
	if slot < 0 or slot >= offers.size():
		return 0
	var price: int = int(offers[slot]["price"])
	if price < 0:
		return 0
	if not _can_batch:
		return int(balance >= price)
	if price == 0:
		return 99
	@warning_ignore("integer_division")
	return balance / price

func _request_purchase(slot: int) -> void:
	if not is_open or not available or game == null:
		return
	var quantity: int = _amounts[slot] if _can_batch else 1
	game.buy_special_cards({KINDS[slot]: quantity})

func animate_purchase(order: Dictionary) -> void:
	if not is_open:
		return
	var triggered := false
	for slot in range(KINDS.size()):
		if int(order.get(KINDS[slot], 0)) > 0:
			_stamp_timers[slot] = 1.25
			triggered = true
	if triggered:
		set_process(true)
		queue_redraw()

func _process(delta: float) -> void:
	var any_active := false
	for i in range(_stamp_timers.size()):
		if _stamp_timers[i] > 0.0:
			_stamp_timers[i] = maxf(0.0, _stamp_timers[i] - delta)
			if _stamp_timers[i] > 0.0:
				any_active = true
	queue_redraw()
	if not any_active:
		set_process(false)

func _hover_card(slot: int) -> void:
	_hover_slot = slot
	queue_redraw()

func _focus_card(slot: int) -> void:
	_focus_slot = slot
	queue_redraw()

func _on_resize() -> void:
	_position_controls()
	queue_redraw()

func _catalog_rect() -> Rect2:
	var w := minf(CATALOG_SIZE.x, size.x - 48.0)
	var h := minf(CATALOG_SIZE.y, size.y - 68.0)
	var shift_y := (1.0 - progress) * 26.0
	return Rect2((size - Vector2(w, h)) * 0.5 + Vector2(0.0, shift_y), Vector2(w, h))

func _entry_rect() -> Rect2:
	return Rect2(Vector2(28.0, size.y - 134.0), Vector2(168.0, 58.0))

func _position_controls() -> void:
	if not is_instance_valid(entry):
		return
	mouse_filter = Control.MOUSE_FILTER_STOP if (is_open or progress > 0.01) else Control.MOUSE_FILTER_IGNORE
	var er := _entry_rect()
	entry.position = er.position
	entry.size = er.size
	entry.visible = progress <= 0.01 and not is_open and not offers.is_empty()

	var cat := _catalog_rect()
	var shown := is_open and progress > 0.85 and offers.size() == KINDS.size()
	back.position = Vector2(cat.end.x - 138.0, cat.position.y + 18.0)
	back.size = Vector2(118.0, 36.0)
	back.visible = progress > 0.5
	back.disabled = not is_open

	var inner_w := cat.size.x - 48.0
	var col_gap := 18.0
	var col_w := (inner_w - col_gap * 2.0) / 3.0
	for slot in range(KINDS.size()):
		var sx := cat.position.x + 24.0 + float(slot) * (col_w + col_gap)
		var card_top := cat.position.y + 84.0
		card_buttons[slot].position = Vector2(sx, card_top)
		card_buttons[slot].size = Vector2(col_w, 224.0)
		card_buttons[slot].visible = shown

		var step_y := cat.end.y - 98.0
		reduce_buttons[slot].position = Vector2(sx + 10.0, step_y)
		reduce_buttons[slot].size = Vector2(36.0, 32.0)
		reduce_buttons[slot].visible = shown and _can_batch

		add_buttons[slot].position = Vector2(sx + col_w - 46.0, step_y)
		add_buttons[slot].size = Vector2(36.0, 32.0)
		add_buttons[slot].visible = shown and _can_batch

		pickup_buttons[slot].position = Vector2(sx + 10.0, cat.end.y - 56.0)
		pickup_buttons[slot].size = Vector2(col_w - 20.0, 38.0)
		pickup_buttons[slot].visible = shown
	_refresh_controls()

func _refresh_controls() -> void:
	if not is_instance_valid(entry):
		return
	entry.disabled = not available
	entry.accessibility_name = "打开特殊牌商店，余额 %d 筹码" % balance
	if offers.size() != KINDS.size():
		return
	for slot in range(KINDS.size()):
		var limit := _affordable(slot)
		_amounts[slot] = clampi(_amounts[slot], 0, maxi(1, limit)) if _can_batch else 1
		var quantity: int = _amounts[slot]
		var offer: Dictionary = offers[slot]
		reduce_buttons[slot].disabled = quantity <= 0
		add_buttons[slot].disabled = quantity >= limit
		pickup_buttons[slot].disabled = quantity <= 0 or quantity > limit
		pickup_buttons[slot].text = ("购买 ×%d" % quantity) if quantity > 1 else "购入库存"
		card_buttons[slot].accessibility_name = "%s，单价 %dr" % [HandCard.SPECIAL_NAMES[offer["kind"]], int(offer["price"])]

func _draw() -> void:
	if _font == null:
		_font = get_theme_default_font()
	if _font == null or size.x < 240.0:
		return
	if progress <= 0.005 and offers.is_empty() and not Engine.is_editor_hint():
		return

	# 1. 左下角公文包商店入口按钮（关闭态）
	if progress < 0.6 and not offers.is_empty():
		_draw_briefcase_entry(1.0 - smoothstep(0.0, 0.5, progress))

	if progress <= 0.005:
		return

	# 2. 半透明米白报刊遮罩
	draw_rect(Rect2(Vector2.ZERO, size), Color(Ink.PAPER, progress * 0.78), true)

	# 3. 居中暗市补给目录卡片
	var cat := _catalog_rect()
	var alpha := smoothstep(0.15, 0.95, progress)
	Ink.draw_hatch_shadow(self, cat, Vector2(9.0, 10.0), Color(Ink.INK, 0.24 * alpha), 5.2)
	Ink.draw_pen_rect(self, cat, Color(Ink.PAPER_CARD, alpha), Color(Ink.INK, alpha), 2.3, 131, 0.9, 2.2, true)

	# 标题栏
	draw_string(_font, cat.position + Vector2(24.0, 32.0), "BLACK MARKET // 暗市特殊牌补给",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Ink.INK_SOFT, alpha))
	draw_string(_font, cat.position + Vector2(24.0, 58.0), "♦  外交公文包商店",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(Ink.INK, alpha))

	# 钱包余额（居中靠右，位于返回按钮左侧）
	var bal_str := "持有筹码  %dr" % balance
	var bal_w := _font.get_string_size(bal_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(_font, Vector2(cat.end.x - 156.0 - bal_w, cat.position.y + 42.0), bal_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(Ink.CRIMSON, alpha))

	# 顶部分隔线
	Ink.draw_pen_line(self, Vector2(cat.position.x + 22.0, cat.position.y + 72.0),
		Vector2(cat.end.x - 22.0, cat.position.y + 72.0), Color(Ink.RULE, alpha), 1.1, 139, 0.5, 0.0)

	if offers.size() != KINDS.size():
		return

	var inner_w := cat.size.x - 48.0
	var col_gap := 18.0
	var col_w := (inner_w - col_gap * 2.0) / 3.0
	var active_slot := _hover_slot if _hover_slot >= 0 else _focus_slot

	for slot in range(KINDS.size()):
		var offer: Dictionary = offers[slot]
		var kind: String = str(offer["kind"])
		var price: int = int(offer["price"])
		var sx := cat.position.x + 24.0 + float(slot) * (col_w + col_gap)
		var slot_rect := Rect2(Vector2(sx, cat.position.y + 84.0), Vector2(col_w, cat.size.y - 102.0))
		var highlighted := active_slot == slot
		var col_border := Color(Ink.CRIMSON, alpha) if highlighted else Color(Ink.INK, 0.65 * alpha)
		Ink.draw_pen_rect(self, slot_rect, Color(Ink.PAPER, alpha), col_border,
			2.0 if highlighted else 1.3, 150 + slot * 17, 0.65, 1.2)

		# 卡牌插图缩略（黑底白纹 + 朱红角标）
		var card_rect := Rect2(Vector2(slot_rect.get_center().x - 38.0, slot_rect.position.y + 14.0), Vector2(76.0, 102.0))
		_draw_catalog_card(card_rect, kind, alpha)

		# 卡名 + 单价
		var card_name: String = HandCard.SPECIAL_NAMES[kind]
		Ink.draw_centered_text(self, _font, card_name, Vector2(slot_rect.get_center().x, card_rect.end.y + 20.0), 16, Color(Ink.INK, alpha))
		Ink.draw_centered_text(self, _font, "%dr / 张" % price, Vector2(slot_rect.get_center().x, card_rect.end.y + 42.0), 15, Color(Ink.CRIMSON, alpha))

		# 简明效果说明
		var desc := _description_for(kind)
		var lines := _wrap_short(desc, 13)
		for li in range(lines.size()):
			Ink.draw_centered_text(self, _font, lines[li],
				Vector2(slot_rect.get_center().x, card_rect.end.y + 66.0 + float(li) * 17.0),
				12, Color(Ink.INK_SOFT, alpha))

		# 批量数量读数
		if _can_batch:
			Ink.draw_centered_text(self, _font, "× %d" % _amounts[slot],
				Vector2(slot_rect.get_center().x, cat.end.y - 82.0), 16, Color(Ink.INK, alpha))

		# 购入成功的朱红盖章反馈
		if _stamp_timers[slot] > 0.0:
			var sa := clampf(_stamp_timers[slot] * 1.4, 0.0, 1.0)
			Ink.draw_rubber_stamp(self, card_rect.get_center(), "已入库", _font, 15,
				Color(Ink.CRIMSON, sa), -10.0, 210 + slot, Color(Ink.PAPER_CARD, 0.92 * sa))

	if not _report.is_empty():
		Ink.draw_centered_text(self, _font, _report, Vector2(cat.get_center().x, cat.end.y + 22.0), 13, Color(Ink.CRIMSON, alpha))

func _draw_briefcase_entry(opacity: float) -> void:
	var rect := _entry_rect()
	var hovered := is_instance_valid(entry) and (entry.is_hovered() or entry.has_focus()) and available
	var alpha := opacity * (1.0 if available else 0.45)
	var bg := Color(Ink.INK, alpha) if hovered else Color(Ink.PAPER_CARD, alpha)
	var fg := Color(Ink.PAPER_CARD, alpha) if hovered else Color(Ink.INK, alpha)
	var accent := Color(Ink.CRIMSON, alpha)

	Ink.draw_hatch_shadow(self, rect, Vector2(4.0, 4.0), Color(accent if hovered else Ink.INK, 0.25 * alpha), 4.5)
	Ink.draw_pen_rect(self, rect, bg, Color(Ink.INK, alpha), 2.0, 121, 0.7, 1.5)

	# 左侧手绘冷战公文包图标
	var bx := rect.position.x + 14.0
	var by := rect.position.y + 18.0
	var case_r := Rect2(Vector2(bx, by), Vector2(30.0, 22.0))
	draw_rect(case_r, fg, false, 1.8)
	draw_rect(Rect2(Vector2(bx + 9.0, by - 5.0), Vector2(12.0, 5.0)), fg, false, 1.6)
	draw_line(Vector2(bx, by + 9.0), Vector2(bx + 30.0, by + 9.0), fg, 1.3, true)
	draw_rect(Rect2(Vector2(bx + 12.5, by + 7.0), Vector2(5.0, 5.0)), accent, true)

	# 文字标题与提示
	draw_string(_font, Vector2(rect.position.x + 54.0, rect.position.y + 27.0), "暗市商店",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, fg)
	draw_string(_font, Vector2(rect.position.x + 54.0, rect.position.y + 45.0),
		"购入特殊暗牌 ↗" if available else "动画中暂不可用",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, accent if hovered else Color(Ink.INK_SOFT, alpha))

func _draw_catalog_card(rect: Rect2, kind: String, alpha: float) -> void:
	draw_rect(rect, Color(Ink.INK, alpha), true)
	draw_rect(rect.grow(-4.0), Color(Ink.PAPER_CARD, 0.45 * alpha), false, 1.0)
	Ink.draw_diamond(self, rect.position + Vector2(12.0, 13.0), 3.6, 5.2, Color(Ink.CRIMSON, alpha), true)
	var c := rect.get_center()
	var fg := Color(Ink.PAPER_CARD, alpha)
	var accent := Color(Ink.CRIMSON, alpha)
	match kind:
		"defense":
			var shield := PackedVector2Array([
				c + Vector2(0.0, -17.0), c + Vector2(14.0, -11.0), c + Vector2(12.0, 4.0),
				c + Vector2(0.0, 17.0), c + Vector2(-12.0, 4.0), c + Vector2(-14.0, -11.0)
			])
			draw_colored_polygon(shield, fg)
			Ink.draw_diamond(self, c, 5.0, 7.5, accent, true)
		"change":
			draw_arc(c, 13.0, 0.3, PI - 0.3, 14, fg, 2.0, true)
			draw_arc(c, 13.0, PI + 0.3, TAU - 0.3, 14, fg, 2.0, true)
			Ink.draw_diamond(self, c, 6.0, 8.5, accent, true)
		"super":
			var star := PackedVector2Array()
			for i in range(10):
				var a := -PI * 0.5 + TAU * float(i) / 10.0
				var r := 16.5 if i % 2 == 0 else 7.0
				star.append(c + Vector2.from_angle(a) * r)
			draw_colored_polygon(star, accent)
			draw_circle(c, 4.0, fg)

func _description_for(kind: String) -> String:
	if kind == "defense" and game != null and game.game_mode == Rules.Mode.GREED:
		return "出牌阶段使用，命中时保住全部筹码。"
	if kind == "super":
		var steps: int = int(game.super_steps) if game != null else 1
		return "结算阶段使用，额外追加 +%d 格位移。" % steps
	return str(HandCard.SPECIAL_HINTS.get(kind, ""))

func _wrap_short(text: String, max_chars: int) -> Array[String]:
	var out: Array[String] = []
	var idx := 0
	while idx < text.length():
		out.append(text.substr(idx, max_chars))
		idx += max_chars
	return out
