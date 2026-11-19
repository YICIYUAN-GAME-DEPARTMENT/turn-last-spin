extends Control
## 复用原型的对局布局，直接呈现团队 Session 的公开状态。

signal menu_requested
signal restart_requested
signal player_count_changed(count: int)
signal initial_lives_changed(lives: int)

const HandCardScene = preload("res://scenes/ui/hand_card.tscn")
const HandCard = preload("res://scripts/ui/hand_card.gd")
const Rules = preload("res://scripts/core/game_rules.gd")
const MINT := Color("91e7c2")
const WHITE := Color("edf0e7")
const MUTED := Color("8da4ad")
const CORAL := Color("ffb28e")

@onready var wheel = $Table/Wheel
@onready var round_label = $Table/Round
@onready var status_label: Label = $Table/Status
@onready var count_picker: OptionButton = $Table/Toolbar/PlayerCount
@onready var ranking_label: Label = $Table/HandPanel/Column/Ranking
@onready var lives_picker: OptionButton = $Table/InitialLives
@onready var shop_button: Button = $Table/ShopButton
@onready var reward = $RoundReward
@onready var played_cards_layer: Control = $PlayedCards
@onready var coins = $Table/ShopButton/CoinWindow/Reels
@onready var shop = $Table/SpecialShop
@onready var restart_button: Button = $Table/Toolbar/Restart
@onready var menu_button: Button = $Table/Toolbar/Menu
@onready var hand_scroll: ScrollContainer = $Table/HandPanel/Column/Scroll
@onready var hand_fan = $Table/HandPanel/Column/Scroll/Cards
@onready var hand_title: Label = $Table/HandPanel/Column/Title
@onready var primary_button: Button = $Table/HandPanel/Column/Primary
@onready var stats_panel: PanelContainer = $Table/StatisticsPanel
@onready var stats_totals: Label = $Table/StatisticsPanel/Content/Totals
@onready var stats_grid: GridContainer = $Table/StatisticsPanel/Content/Scroll/Grid
@onready var action_overlay: Control = $ActionOverlay
@onready var action_menu = $ActionOverlay/CardActionMenu

var game: Node
var allow_menu: bool = true
var _round_state: Dictionary = {}
var _wheel_balances: Dictionary = {}
var _wheel_hidden_counts: Dictionary = {}
var _wallet_balance: int = -1
var _payouts: Array[Dictionary] = []
var _pending_gain: int = 0
var _counting_steps: bool = false
var _display_match_id: int = -1
var _round_key: String = ""
var _last_phase: String = ""
var _rendered_hand: Array = []
var _selected_card: Button
var _incoming_card: HandCard
var _initial_spin: bool = false
var _animation: Tween

func _ready() -> void:
	reward.delivered.connect(_on_reward_delivered)
	for count in range(2, Rules.MAX_PLAYERS + 1):
		count_picker.add_item("%d 人" % count, count)
	count_picker.item_selected.connect(_on_player_count_selected)
	for lives in range(1, Rules.MAX_INITIAL_LIVES + 1):
		lives_picker.add_item("生命 %d" % lives, lives)
	lives_picker.item_selected.connect(func(index: int):
		initial_lives_changed.emit(lives_picker.get_item_id(index)))
	restart_button.pressed.connect(func(): restart_requested.emit())
	menu_button.pressed.connect(func(): menu_requested.emit())
	primary_button.pressed.connect(_on_primary)
	$Table/Toolbar/Statistics.pressed.connect(_toggle_statistics)
	shop_button.pressed.connect(_toggle_shop)
	action_menu.direction_selected.connect(_play_selected)
	action_menu.special_confirmed.connect(_use_selected_special)
	action_menu.cancelled.connect(_close_card_menu)
	action_overlay.gui_input.connect(_on_overlay_input)
	resized.connect(_close_card_menu)
	primary_button.disabled = true
	_clear_children(hand_fan)

func present() -> void:
	var round_number: int = int(game.public.get("round", 0))
	var round_key: String = "%d:%d" % [game.match_id, round_number]
	var phase: String = game.phase
	var new_deal := phase == "choosing" and _round_key != round_key
	if phase == "round_intro" and (_last_phase != phase or _display_match_id != game.match_id):
		_stop_animation()
		_close_card_menu()
		_round_state = game.public
		_update_wheel_seats({})
		wheel.start_index = -1
		wheel.target_index = -1
		wheel.center_caption = ""
		wheel.center_steps = "—"
		round_label.roll_to(round_number + 1, game.INTRO_SECONDS)
	elif new_deal:
		round_label.set_number(round_number)
		_round_key = round_key
		_round_state = game.public
		_close_card_menu()
		_show_wheel({})
		_render_statistics()
	elif phase == "ended" and round_number == 0:
		_round_state = {}
		_stop_animation()
		wheel.seats = []
		wheel.queue_redraw()
		_render_statistics()
	elif phase in ["result", "ended"] and phase != _last_phase:
		_show_wheel(game.last_result)
		_render_statistics()
	elif game.public.get("hidden_card_counts", {}) != _wheel_hidden_counts or game.public.get("balances", {}) != _wheel_balances:
		_update_wheel_seats(game.last_result if phase in ["result", "ended"] else {})
	_last_phase = phase
	_render_hand()
	if new_deal:
		var hand: Array = game.public.hands.get(game.local_id(), [])
		if not hand.is_empty():
			_deal_to_hand(hand_fan.get_node("HandCard_%d" % hand.back().id))
	_sync_wallet(phase in ["result", "ended"] and round_number > 0)
	_refresh_controls()

func _sync_wallet(is_round_result: bool) -> void:
	if _display_match_id != game.match_id:
		reward.cancel()
		_payouts.clear()
		_pending_gain = 0
		_display_match_id = game.match_id
		_wallet_balance = game.balance
		coins.set_amount(_wallet_balance, false)
	elif _wallet_balance != game.balance:
		var change: int = game.balance - _wallet_balance
		_wallet_balance = game.balance
		if is_round_result and change > 0:
			_pending_gain += change
			_payouts.append({"gain": change, "result": game.last_result})
		else:
			coins.set_amount(maxi(0, _wallet_balance - _pending_gain), false)
	_present_reward()

func _present_reward() -> void:
	if not _payouts.is_empty() and not _counting_steps and not reward.visible:
		var payout: Dictionary = _payouts.pop_front()
		reward.play(payout.gain, payout.result, coins)

func _on_reward_delivered(gain: int) -> void:
	_pending_gain -= gain
	coins.set_amount(maxi(0, _wallet_balance - _pending_gain), true)
	_present_reward()

func reset() -> void:
	reward.cancel()
	_payouts.clear()
	_pending_gain = 0
	_clear_children(played_cards_layer)
	_round_key = ""
	_display_match_id = -1
	_last_phase = ""
	_round_state = {}
	_wheel_hidden_counts.clear()
	_wheel_balances.clear()
	round_label.set_number(0)
	_stop_animation()
	_close_card_menu()
	stats_panel.hide()
	shop.hide()

func _show_wheel(result: Dictionary) -> void:
	_stop_animation()
	_update_wheel_seats(result)
	wheel.start_index = int(_round_state.get("initial_index", 0))
	wheel.target_index = int(result.get("target_index", -1))
	var delta: int = int(result.get("delta", 0))
	wheel.center_caption = "初始" if result.is_empty() else "合计"
	wheel.center_steps = str(wheel.start_index + 1) if result.is_empty() else "%+d" % delta

	var step := TAU / float(maxi(1, wheel.seats.size()))
	var target: float = -PI / 2.0 + float(wheel.start_index) * step
	if result.is_empty():
		_initial_spin = true
		wheel.needle_angle = -PI / 2.0 - TAU
		wheel.deal_progress = 0.0
		_tween_pointer(target, 0.85)
		_animation.parallel().tween_property(wheel, "deal_progress", 1.0, 0.78)
	else:
		var landing: int = wheel.target_index
		wheel.target_index = -1
		wheel.needle_angle = target
		wheel.center_steps = "+0"
		wheel.play_progress = 0.0
		_counting_steps = true
		_animation = create_tween()
		_animation.tween_property(wheel, "play_progress", 1.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_animation.tween_callback(func(): status_label.text = "结算位移")
		_animation.tween_method(func(value: float):
			wheel.center_steps = "%+d" % roundi(value)
			wheel.needle_angle = target + value * step,
			0.0, float(delta), 0.64).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_animation.tween_callback(func():
			wheel.target_index = landing
			wheel.center_caption = "最终位移"
			wheel.queue_redraw()
			_counting_steps = false
			_update_status()
			_present_reward())
		_animation.tween_method(func(t: float):
			wheel.number_scale = 1.0 + 0.22 * sin(PI * t)
			wheel.queue_redraw(), 0.0, 1.0, 0.24)

func _update_wheel_seats(result: Dictionary) -> void:
	var seats: Array = []
	var played_cards: Dictionary = {}
	var revealed: Dictionary = {}
	for action in result.get("actions", []):
		var id: int = int(action["peer_id"])
		match action["type"]:
			"play":
				played_cards[id] = action
			"defense":
				revealed[id] = [_revealed_card("防御")]
			"change":
				var delta: int = int(action["value"]) * int(action["sign"])
				revealed[id] = [_revealed_card("变化", "%+d" % delta)]
	for id in result.get("super_users", []):
		var played_specials: Array = revealed.get(id, [])
		played_specials.append(_revealed_card("超级", "%+d" % game.super_steps))
		revealed[id] = played_specials

	var counts: Dictionary = game.public.get("hidden_card_counts", {})
	var round_counts: Dictionary = _round_state.get("hidden_card_counts", {})
	for id in _round_state.get("alive", []):
		var cards: Array = []
		var played: Dictionary = played_cards.get(id, {})
		for card in _round_state["hands"].get(id, []):
			var shown: bool = int(card.id) == played.get("card_id", -1)
			cards.append({
				"id": card["id"], "value": card["value"], "face_up": true,
				"played": shown, "caption": "%+d" % (int(card.value) * int(played.sign)) if shown else ""
			})
		var played_specials: Array = revealed.get(id, [])
		cards.append_array(played_specials)
		var quantity: int = int(counts.get(id, maxi(0, int(round_counts.get(id, 0)) - played_specials.size())))
		if quantity > 0:
			cards.append({"face_up": false, "quantity": quantity})
		var hand: Array = _round_state["hands"][id]
		var seat := {"id": id, "name": game.name_for(id), "cards": cards,
			"dealt_id": hand.back().id if not hand.is_empty() else -1,
			"played_count": int(not played.is_empty()) + played_specials.size()}
		if id != game.local_id() and game.public.has("balances"):
			seat["balance"] = game.public.balances.get(id, 0)
		if game.game_mode == Rules.Mode.CLASSIC:
			seat["hp"] = game.public.get("lives", {}).get(id, 0)
			seat["alive"] = seat["hp"] > 0
		seats.append(seat)
	_wheel_balances = game.public.get("balances", {}).duplicate()
	_wheel_hidden_counts = counts.duplicate()
	wheel.seats = seats
	wheel.local_player_id = game.local_id()
	wheel.queue_redraw()

func _revealed_card(caption: String, points: String = "") -> Dictionary:
	return {"face_up": true, "played": true, "caption": caption, "points": points}

func _tween_pointer(angle: float, duration: float) -> void:
	_animation = create_tween()
	_animation.tween_property(wheel, "needle_angle", angle, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_animation.finished.connect(func():
		_initial_spin = false
		_refresh_controls())

func _deal_to_hand(slot: HandCard) -> void:
	_incoming_card = HandCardScene.instantiate()
	_incoming_card.card_id = slot.card_id
	_incoming_card.value = slot.value
	_incoming_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_incoming_card.focus_mode = Control.FOCUS_NONE
	played_cards_layer.add_child(_incoming_card)
	slot.modulate.a = 0.0
	_position_incoming_card(0.0)
	var flight := _animation.parallel().tween_method(_position_incoming_card, 0.0, 1.0, 0.78)
	flight.finished.connect(_finish_hand_deal)

func _position_incoming_card(progress: float) -> void:
	# 商店更新可能重建手牌；始终以同一张牌当前的扇形位置为落点。
	var slot: HandCard = hand_fan.get_node_or_null("HandCard_%d" % _incoming_card.card_id)
	if slot == null:
		return
	if progress > 0.0:
		hand_scroll.ensure_control_visible(slot)
	var start: Vector2 = wheel.get_global_rect().get_center()
	var end := slot.get_global_transform() * (slot.size * 0.5)
	var travel := smoothstep(0.0, 1.0, progress)
	var center := start.lerp(end, travel) - Vector2(0.0, sin(travel * PI) * 52.0)
	_incoming_card.size = slot.size
	_incoming_card.pivot_offset = slot.size * 0.5
	_incoming_card.scale = Vector2(0.30, 0.30).lerp(slot.scale, travel)
	_incoming_card.rotation = lerp_angle(-0.22, slot.rotation, travel)
	_incoming_card.show_corner = slot.show_corner and travel > 0.75
	_incoming_card.position = played_cards_layer.get_global_transform().affine_inverse() * center - _incoming_card.pivot_offset

func _finish_hand_deal() -> void:
	if not is_instance_valid(_incoming_card):
		return
	var slot: HandCard = hand_fan.get_node_or_null("HandCard_%d" % _incoming_card.card_id)
	if slot != null:
		slot.modulate.a = 1.0
	_incoming_card.hide()
	_incoming_card.queue_free()
	_incoming_card = null

func _stop_animation() -> void:
	if _animation != null and _animation.is_valid():
		_animation.kill()
	_finish_hand_deal()
	_initial_spin = false
	_counting_steps = false
	wheel.play_progress = 1.0
	wheel.number_scale = 1.0
	wheel.deal_progress = 1.0

func _render_hand() -> void:
	var cards: Array = []
	for kind in HandCard.SPECIAL_NAMES:
		var amount: int = game.special_card_count(kind)
		if amount > 0:
			cards.append({"kind": kind, "quantity": amount})
	cards.append_array(game.public.get("hands", {}).get(game.local_id(), []))
	var total: int = 0
	for card in cards:
		total += int(card.get("quantity", 1))
	hand_title.text = "我的手牌  %02d" % total
	if cards == _rendered_hand:
		return

	_close_card_menu()
	_rendered_hand = cards
	_clear_children(hand_fan)
	for card in cards:
		var button = HandCardScene.instantiate()
		button.kind = card.get("kind", "play")
		if button.kind == "play":
			button.card_id = int(card["id"])
			button.value = int(card["value"])
			button.name = "HandCard_%d" % button.card_id
			if _incoming_card != null and _incoming_card.card_id == button.card_id:
				button.modulate.a = 0.0
		else:
			button.quantity = int(card["quantity"])
			button.name = "SpecialCard_%s" % button.kind
		button.pressed.connect(_open_card_menu.bind(button))
		hand_fan.add_child(button)

func _refresh_controls() -> void:
	_update_status()
	var can_act: bool = game.can_act() and not _initial_spin
	var can_use_super: bool = game.can_settle() and game.special_card_count("super") > 0
	for button in hand_fan.get_children():
		button.disabled = not (can_use_super if button.kind == "super" else can_act)
	if is_instance_valid(_selected_card) and _selected_card.disabled:
		_close_card_menu()

	shop.game = game
	shop_button.visible = not game.card_prices.is_empty()
	shop_button.accessibility_name = "商店，余额 %d 金币" % game.balance
	if shop.visible:
		shop.present()

	var is_local: bool = game.role == "local"
	count_picker.visible = is_local
	lives_picker.visible = is_local and game.game_mode == Rules.Mode.CLASSIC
	var ranking: Array = game.public.get("ranking", [])
	ranking_label.visible = not ranking.is_empty()
	if ranking_label.visible:
		var lines := PackedStringArray(["最终排名" if game.phase == "ended" else "已达标"])
		for index in ranking.size():
			var id: int = ranking[index]
			var entry := "第 %d 名   %s" % [index + 1, "你" if id == game.local_id() else game.name_for(id)]
			if id != game.local_id() and game.public.get("balances", {}).has(id):
				entry += "   %dr" % game.public.balances[id]
			lines.append(entry)
		ranking_label.text = "\n".join(lines)
	if is_local:
		count_picker.select(count_picker.get_item_index(game.members.size()))
		lives_picker.select(lives_picker.get_item_index(game.initial_lives))
	restart_button.visible = is_local
	menu_button.visible = is_local and allow_menu
	primary_button.disabled = true
	match game.phase:
		"round_intro":
			primary_button.text = "准备发牌"
		"choosing":
			var in_round: bool = game.public.get("alive", []).has(game.local_id())
			primary_button.text = "不出牌" if in_round else "观战"
			if in_round and not game.sealed_hash.is_empty():
				primary_button.text = "已锁定"
			primary_button.disabled = not can_act
		"revealing":
			primary_button.text = "揭晓中"
		"settlement":
			primary_button.text = "跳过超级卡" if can_use_super else "确认结算"
			if game.settlement_submitted:
				primary_button.text = "等待结算"
			elif not game.public.get("alive", []).has(game.local_id()):
				primary_button.text = "观战"
			primary_button.disabled = not game.can_settle()
		"result":
			primary_button.text = "等待下一轮"
		"ended", "aborted":
			primary_button.text = "对局结束"
			if is_local:
				primary_button.text = "再来一局"
			elif game.am_host():
				primary_button.text = "返回房间"
			primary_button.disabled = not (is_local or game.am_host())

func _update_status() -> void:
	var alive: Array = game.public.get("alive", [])
	var status: String = game.status
	if _counting_steps:
		status = "公开出牌" if wheel.play_progress < 1.0 else "结算位移"
	elif game.phase == "choosing":
		if game.game_mode == Rules.Mode.GREED:
			status = "贪婪模式   /   金币 %d / %d   /   %d 人在场   /   %d 秒" % [floori(coins.reading), Rules.COIN_GOAL, alive.size(), game.seconds_left()]
		else:
			status = "%d 人存活   /   %d 秒" % [alive.size(), game.seconds_left()]
		if not alive.has(game.local_id()):
			status += "   /   观战"
		elif not game.sealed_hash.is_empty():
			status += "   /   已锁定"
	elif game.phase == "settlement":
		status = "结算   /   位移 %+d   /   %d 秒" % [game.settlement_delta, game.seconds_left()]
	elif game.phase == "ended":
		var winner: int = int(game.last_result.get("winner", 0))
		status = "%s获胜" % ("你" if winner == game.local_id() else game.name_for(winner) + " ")
	if status_label.text == status:
		return
	status_label.text = status
	status_label.add_theme_color_override("font_color", CORAL if game.phase in ["revealing", "settlement", "result", "aborted"] else MUTED)

func _process(_delta: float) -> void:
	if visible and game != null and game.phase in ["choosing", "settlement"]:
		_update_status()

func _open_card_menu(button: Button) -> void:
	if button.disabled:
		return
	_selected_card = button
	hand_fan.pin(button)
	match button.kind:
		"change":
			action_menu.set_change_range(game.public.get("alive", []).size())
		"defense":
			action_menu.set_special_card(HandCard.SPECIAL_NAMES["defense"], "被命中时保住本轮金币。" if game.game_mode == Rules.Mode.GREED else "被命中时保住最后 1 点生命。")
		"super":
			action_menu.set_special_card(HandCard.SPECIAL_NAMES["super"], "最终位移增加 %d 格。" % game.super_steps)
		_:
			action_menu.set_card_value(button.value)

	var corner: Vector2 = button.get_global_transform() * Vector2(button.size.x, 0)
	var point: Vector2 = corner - global_position + Vector2(12.0, -12.0)
	action_overlay.show()
	action_menu.reset_size()
	var room: Vector2 = size - action_menu.size - Vector2(16, 16)
	action_menu.position = point.clamp(Vector2(16, 76), room.max(Vector2(16, 76)))

func _close_card_menu() -> void:
	if is_instance_valid(_selected_card):
		hand_fan.pin(null)
	_selected_card = null
	action_menu.close_point_picker()
	action_overlay.hide()

func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_card_menu()

func _play_selected(direction: int, points: int) -> void:
	if not is_instance_valid(_selected_card) or _selected_card.disabled:
		return
	var action: Dictionary
	match _selected_card.kind:
		"play":
			action = {"type": "play", "card_id": _selected_card.card_id, "sign": direction}
		"change":
			action = {"type": "change", "value": points, "sign": direction}
		_:
			return
	var value: int = _selected_card.value if _selected_card.kind == "play" else points
	_animate_submission("%+d" % (value * direction))
	_close_card_menu()
	game.submit_action(action)

func _use_selected_special() -> void:
	if not is_instance_valid(_selected_card) or _selected_card.disabled:
		return
	var kind: String = _selected_card.kind
	_animate_submission(HandCard.SPECIAL_NAMES[kind])
	_close_card_menu()
	if kind == "defense":
		game.submit_action({"type": kind})
	elif kind == "super":
		game.submit_settlement(true)

func _animate_submission(caption: String) -> void:
	var card = HandCardScene.instantiate()
	card.kind = _selected_card.kind
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.focus_mode = Control.FOCUS_NONE
	played_cards_layer.add_child(card)
	card.text = caption
	card.size = _selected_card.size
	card.pivot_offset = _selected_card.pivot_offset
	card.scale = _selected_card.scale
	card.rotation = _selected_card.rotation
	var origin: Vector2 = _selected_card.get_global_transform() * _selected_card.pivot_offset
	card.position = origin - played_cards_layer.global_position - card.pivot_offset
	var end: Vector2 = wheel.get_global_rect().get_center() - played_cards_layer.global_position - card.pivot_offset
	var flight: Tween = card.create_tween().set_parallel(true)
	flight.tween_property(card, "position", end, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flight.tween_property(card, "scale", Vector2(0.48, 0.48), 0.36)
	flight.tween_property(card, "rotation", -0.12, 0.36)
	flight.tween_property(card, "modulate:a", 0.0, 0.14).set_delay(0.25)
	flight.chain().tween_callback(card.queue_free)

func _on_primary() -> void:
	if primary_button.disabled:
		return
	_close_card_menu()
	if game.phase == "choosing":
		game.submit_action({"type": "pass"})
	elif game.phase == "settlement":
		game.submit_settlement(false)
	elif game.phase in ["ended", "aborted"]:
		restart_requested.emit()

func _on_player_count_selected(index: int) -> void:
	player_count_changed.emit(count_picker.get_item_id(index))

func _input(event: InputEvent) -> void:
	if game == null or not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE and action_overlay.visible:
		_close_card_menu()
	elif event.keycode == KEY_SPACE and not action_overlay.visible:
		_on_primary()
	elif event.keycode == KEY_R and game.role == "local":
		restart_requested.emit()
	else:
		return
	get_viewport().set_input_as_handled()

func _toggle_shop() -> void:
	if game == null:
		return
	shop.visible = not shop.visible
	if shop.visible:
		stats_panel.hide()
		shop.present()

func _toggle_statistics() -> void:
	stats_panel.visible = not stats_panel.visible
	if stats_panel.visible:
		shop.hide()

func _render_statistics() -> void:
	var stats: Dictionary = game.public.get("stats", {})
	stats_totals.text = "已发 %d  /  已出 %d  /  剩余 %d" % [
		stats.get("issued", 0), stats.get("played", 0), stats.get("held", 0)]
	_clear_children(stats_grid)
	for header in ["牌", "已发", "已出", "离场弃" if game.game_mode == Rules.Mode.GREED else "淘汰弃", "剩余"]:
		_add_stat_cell(header, 10, MUTED)
	var by_value: Dictionary = stats.get("by_value", {})
	var values := by_value.keys()
	values.sort()
	for value in values:
		_add_stat_cell(str(value), 12, WHITE)
		for field in ["issued", "played", "discarded", "held"]:
			_add_stat_cell(str(by_value[value][field]), 12, MINT if field == "held" else WHITE)

func _add_stat_cell(text: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	stats_grid.add_child(label)

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
