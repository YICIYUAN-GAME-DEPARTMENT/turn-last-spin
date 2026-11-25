extends Control
## 复用原型的对局布局，直接呈现团队 Session 的公开状态。

signal menu_requested
signal restart_requested
signal player_count_changed(count: int)
signal initial_lives_changed(lives: int)

const HandCardScene = preload("res://scenes/ui/hand_card.tscn")
const HandCard = preload("res://scripts/ui/hand_card.gd")
const Rules = preload("res://scripts/core/game_rules.gd")
const Sketch = preload("res://scripts/ui/sketch_ink.gd")
const DEAL_SECONDS := 0.68

@onready var table: Control = $Table
@onready var wheel = $Table/Wheel
@onready var round_label = $Table/Round
@onready var round_announcement: Label = $RoundAnnouncement
@onready var status_label: Label = $Table/Status
@onready var count_picker: OptionButton = $Table/Toolbar/PlayerCount
@onready var ranking_label: Label = $Table/Ranking
@onready var lives_picker: OptionButton = $Table/InitialLives
@onready var hand_panel: Control = $Table/HandPanel
@onready var reward = $RoundReward
@onready var coins = $Table/CoinWindow/Reels
@onready var shop = $SpecialShop
@onready var restart_button: Button = $Table/Toolbar/Restart
@onready var menu_button: Button = $Table/Toolbar/Menu
@onready var hand_scroll: ScrollContainer = $Table/HandPanel/Column/Scroll
@onready var hand_fan = $Table/HandPanel/Column/Scroll/Cards
@onready var hand_title: Label = $Table/HandPanel/Column/Title
@onready var primary_button: Button = $Table/Primary
@onready var stats_panel: PanelContainer = $Table/StatisticsPanel
@onready var stats_totals: Label = $Table/StatisticsPanel/Content/Totals
@onready var stats_grid: GridContainer = $Table/StatisticsPanel/Content/Scroll/Grid
@onready var action_overlay: Control = $ActionOverlay
@onready var action_menu = $ActionOverlay/CardActionMenu

@export var presentation_timing = preload("res://ui/round_presentation_timing.tres")

var game: Node
var allow_menu: bool = true
var _round_state: Dictionary = {}
var _wheel_balances: Dictionary = {}
var _wheel_hidden_counts: Dictionary = {}
var _wallet_balance: int = -1
var _wallet_cards: Dictionary = {}
var _payouts: Array[Dictionary] = []
var _pending_gain: int = 0
var _presenting_result: bool = false
var _display_match_id: int = -1
var _round_key: String = ""
var _last_phase: String = ""
var _rendered_hand: Array = []
var _selected_card: Button
var _incoming_id := -1
var _initial_spin: bool = false
var _animation: Tween
var _announcement_animation: Tween

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
	shop.view_changed.connect(_move_to_shop)
	action_menu.direction_selected.connect(_play_selected)
	action_menu.special_confirmed.connect(_use_selected_special)
	action_menu.cancelled.connect(_close_card_menu)
	action_overlay.gui_input.connect(_on_overlay_input)
	resized.connect(func():
		_close_card_menu()
		_move_to_shop(shop.progress))
	primary_button.disabled = true
	_clear_children(hand_fan)

func present() -> void:
	var round_number: int = int(game.public.get("round", 0))
	var round_key: String = "%d:%d" % [game.match_id, round_number]
	var phase: String = game.phase
	if phase != "round_intro" and round_announcement.visible:
		_hide_round_announcement()
	var new_deal := phase == "choosing" and _round_key != round_key
	if phase == "round_intro" and (_last_phase != phase or _display_match_id != game.match_id):
		_stop_animation()
		wheel.clear_placements()
		wheel.table_cards = {}
		_close_card_menu()
		_round_state = game.public
		_update_wheel_seats({})
		wheel.start_index = -1
		wheel.target_index = -1
		wheel.center_caption = ""
		wheel.center_steps = "—"
		round_label.set_number(round_number + 1)
		var remaining: float = game.phase_time_left()
		if remaining > 0.0:
			_show_round_announcement(round_number + 1, remaining)
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
		wheel.clear_placements()
		wheel.table_cards = {}
		wheel.seats = []
		wheel.figure_seats = []
		wheel.queue_redraw()
		_render_statistics()
	elif phase == "settlement" and _round_key != round_key:
		_round_key = round_key
		_round_state = game.public
		_update_wheel_seats({})
		wheel.start_index = int(_round_state.get("initial_index", 0))
		wheel.needle_angle = wheel.seat_angle(wheel.start_index)
		wheel.target_index = -1
		wheel.center_caption = "初始"
		wheel.center_steps = str(wheel.start_index + 1)
		wheel.showing_actions = false
		_render_statistics()
	elif phase in ["result", "ended"] and phase != _last_phase:
		if _round_key != round_key:
			_round_key = round_key
			_round_state = game.public.duplicate(true)
			_round_state["initial_index"] = game.last_result.get("initial_index", 0)
			_round_state["alive"] = game.last_result.get("actions", []).map(func(action): return action.peer_id)
		_show_wheel(game.last_result)
	elif game.public.get("hidden_card_counts", {}) != _wheel_hidden_counts or game.public.get("balances", {}) != _wheel_balances:
		_update_wheel_seats(game.last_result if phase in ["result", "ended"] else {})
	if phase in ["choosing", "settlement"]:
		_render_pending_table()
	elif phase == "aborted":
		_stop_animation()
		wheel.clear_placements()
		wheel.table_cards = {}
	_last_phase = phase
	if not _presenting_result:
		_render_hand()
	if new_deal:
		var hand: Array = game.public.hands.get(game.local_id(), [])
		if not hand.is_empty():
			var slot: HandCard = hand_fan.get_node_or_null("HandCard_%d" % hand.back().id)
			if slot != null:
				_deal_to_hand(slot)
	if not _presenting_result:
		_sync_wallet(phase in ["result", "ended"] and round_number > 0)
	_refresh_controls()

func _sync_wallet(is_round_result: bool) -> void:
	if _display_match_id != game.match_id:
		reward.cancel()
		_payouts.clear()
		_pending_gain = 0
		_display_match_id = game.match_id
		_wallet_balance = game.balance
		_wallet_cards = game.special_cards.duplicate()
		shop.reset()
		coins.set_amount(_wallet_balance, false)
	elif _wallet_balance != game.balance:
		var change: int = game.balance - _wallet_balance
		_wallet_balance = game.balance
		if is_round_result and change > 0:
			_pending_gain += change
			_payouts.append({"gain": change, "result": game.last_result})
		else:
			coins.set_amount(maxi(0, _wallet_balance - _pending_gain), false)
	if _wallet_cards != game.special_cards:
		var order := {}
		for kind in HandCard.SPECIAL_NAMES:
			var gained: int = int(game.special_cards.get(kind, 0)) - int(_wallet_cards.get(kind, 0))
			if gained > 0:
				order[kind] = gained
		_wallet_cards = game.special_cards.duplicate()
		shop.animate_purchase(order)
	_present_reward()

func _present_reward() -> void:
	if not _payouts.is_empty() and not _presenting_result and not reward.visible:
		var payout: Dictionary = _payouts.pop_front()
		reward.play(payout.gain, payout.result, coins)

func _on_reward_delivered(gain: int) -> void:
	_pending_gain -= gain
	coins.set_amount(maxi(0, _wallet_balance - _pending_gain), true)
	_present_reward()

func reset() -> void:
	_hide_round_announcement()
	reward.cancel()
	_payouts.clear()
	_pending_gain = 0
	wheel.clear_placements()
	wheel.table_cards = {}
	wheel.countdown_seconds = -1
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
	shop.reset()

func _show_round_announcement(number: int, duration: float) -> void:
	_hide_round_announcement()
	round_label.hide()
	round_announcement.text = "turn %d" % number
	round_announcement.modulate.a = 0.0
	round_announcement.pivot_offset = round_announcement.size * 0.5
	round_announcement.scale = Vector2.ONE * 0.94
	round_announcement.show()

	_announcement_animation = create_tween()
	_announcement_animation.tween_property(round_announcement, "modulate:a", 1.0, duration * 0.18)
	_announcement_animation.parallel().tween_property(round_announcement, "scale", Vector2.ONE, duration * 0.30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_announcement_animation.tween_interval(duration * 0.42)
	_announcement_animation.tween_property(round_announcement, "modulate:a", 0.0, duration * 0.28)
	_announcement_animation.finished.connect(func():
		_announcement_animation = null
		_hide_round_announcement())

func _hide_round_announcement() -> void:
	if _announcement_animation and _announcement_animation.is_valid():
		_announcement_animation.kill()
	round_announcement.hide()
	round_label.show()

func _show_wheel(result: Dictionary) -> void:
	_stop_animation()
	_presenting_result = not result.is_empty()
	_update_wheel_seats(result)
	wheel.start_index = int(_round_state.get("initial_index", 0))
	wheel.target_index = -1
	var delta: int = int(result.get("delta", 0))
	wheel.center_caption = "初始" if result.is_empty() else "位移"
	wheel.center_steps = "—"

	var step := TAU / float(maxi(1, wheel.seats.size()))
	var target: float = wheel.seat_angle(wheel.start_index)
	wheel.showing_actions = not result.is_empty()
	if wheel.showing_actions:
		_render_revealed_table(result)
	else:
		wheel.clear_placements()
		wheel.table_cards = {}
	shop.close()
	_animation = create_tween()
	if result.is_empty():
		_initial_spin = true
		wheel.needle_angle = target - TAU
		wheel.deal_progress = 0.0
		_tween_table_height(0.0, 1.0, 0.26)
		_animation.tween_property(wheel, "needle_angle", target, 0.70).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_animation.tween_callback(func():
			wheel.center_steps = str(wheel.start_index + 1)
			wheel.queue_redraw())
		_animation.tween_interval(presentation_timing.wheel_stop_hold)
		_tween_table_height(1.0, 0.0, presentation_timing.INITIAL_CAMERA_RETURN_SECONDS)
		_animation.tween_property(wheel, "deal_progress", 1.0, DEAL_SECONDS)
	else:
		var landing: int = result["target_index"]
		wheel.needle_angle = target
		wheel.play_progress = 0.0
		_tween_table_height(0.0, 1.0, presentation_timing.RESULT_CAMERA_LIFT_SECONDS)
		_animation.tween_property(wheel, "play_progress", 1.0, presentation_timing.RESULT_REVEAL_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_animation.tween_callback(_update_status)
		_animation.tween_method(func(value: float):
			wheel.needle_angle = target + value * step,
			0.0, float(delta), presentation_timing.RESULT_ROTATION_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_animation.tween_callback(func():
			wheel.center_caption = "停盘"
			wheel.queue_redraw()
			_update_status())
		_animation.tween_interval(presentation_timing.wheel_stop_hold)
		_animation.tween_callback(func():
			wheel.target_index = landing
			wheel.center_caption = "最终位移"
			wheel.center_steps = ("−" if delta < 0 else "+") + str(absi(delta))
			wheel.queue_redraw()
			_update_status())
		_animation.tween_method(func(t: float):
			wheel.number_scale = 1.0 + 0.22 * sin(PI * t)
			wheel.queue_redraw(), 0.0, 1.0, presentation_timing.RESULT_NUMBER_PULSE_SECONDS)
		_tween_table_height(1.0, 0.0, presentation_timing.RESULT_CAMERA_RETURN_SECONDS)
		var eliminated: int = result.get("eliminated", 0)
		if eliminated != 0:
			_animation.tween_callback(func():
				wheel.tombstone_player_id = eliminated
				wheel.tombstone_fall = 0.0
				wheel.tombstone_impact = 0.0)
			_animation.tween_property(wheel, "tombstone_fall", 1.0, presentation_timing.TOMBSTONE_FALL_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_animation.tween_property(wheel, "tombstone_impact", 1.0, presentation_timing.TOMBSTONE_IMPACT_SECONDS)
	_animation.finished.connect(_on_wheel_animation_finished.bind(result))

func _on_wheel_animation_finished(result: Dictionary) -> void:
	_initial_spin = false
	_presenting_result = false
	if not result.is_empty():
		_update_wheel_seats(result)
		wheel.tombstone_player_id = 0
		_render_statistics()
		_render_hand()
		_sync_wallet(true)
	_refresh_controls()

func _tween_table_height(from: float, to: float, duration: float) -> void:
	_animation.tween_method(_set_table_height, from, to, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func _set_table_height(amount: float) -> void:
	wheel.view_height = amount
	hand_panel.modulate.a = 1.0 - smoothstep(0.0, 0.76, amount)
	stats_panel.modulate.a = hand_panel.modulate.a

func _move_to_shop(amount: float) -> void:
	if amount > 0.0:
		stats_panel.hide()
	table.pivot_offset = Vector2(106.0, size.y - 124.0)
	table.scale = Vector2.ONE * lerpf(1.0, 1.36, amount)
	table.position = Vector2(size.x * 0.24, -size.y * 0.25) * amount
	table.modulate.a = 1.0 - smoothstep(0.04, 0.85, amount)
	table.visible = amount < 0.985

func _update_wheel_seats(result: Dictionary) -> void:
	var seats: Array = []
	var played_cards := {}
	var spent_specials := {}
	for action in result.get("actions", []):
		var id: int = action["peer_id"]
		match action["type"]:
			"play":
				played_cards[id] = action["card_id"]
			"defense", "change":
				spent_specials[id] = 1
	for id in result.get("super_users", []):
		spent_specials[id] = int(spent_specials.get(id, 0)) + 1

	var visible_state: Dictionary = _round_state if _presenting_result else game.public
	var counts: Dictionary = visible_state.get("hidden_card_counts", {})
	var round_counts: Dictionary = _round_state.get("hidden_card_counts", {})
	var seats_by_id := {}
	for id in _round_state.get("alive", []):
		var cards: Array = []
		for card in _round_state["hands"].get(id, []):
			cards.append({"id": card["id"], "value": card["value"], "face_up": true,
				"played": card["id"] == played_cards.get(id, -1)})
		var spent: int = spent_specials.get(id, 0)
		var quantity: int = int(counts.get(id, maxi(0, int(round_counts.get(id, 0)) - spent)))
		if quantity > 0:
			cards.append({"face_up": false, "quantity": quantity})
		var hand: Array = _round_state["hands"].get(id, [])
		var seat := {"id": id, "name": game.name_for(id), "cards": cards,
			"dealt_id": hand.back().id if not hand.is_empty() else -1}
		if id != game.local_id() and visible_state.has("balances"):
			seat["balance"] = visible_state.balances.get(id, 0)
		if game.game_mode == Rules.Mode.CLASSIC:
			seat["hp"] = visible_state.get("lives", {}).get(id, 0)
		seats.append(seat)
		seats_by_id[id] = seat
	var figure_seats: Array = []
	if game.game_mode == Rules.Mode.CLASSIC:
		# Original room order keeps the silhouettes and tombstones in the same positions.
		var alive: Array = visible_state.get("alive", [])
		for member in game.members:
			var id: int = member.id
			if not alive.has(id):
				figure_seats.append({"id": id, "name": member.name, "eliminated": true})
			elif seats_by_id.has(id):
				figure_seats.append(seats_by_id[id])
	_wheel_balances = visible_state.get("balances", {}).duplicate()
	_wheel_hidden_counts = counts.duplicate()
	wheel.seats = seats
	wheel.figure_seats = figure_seats
	wheel.local_player_id = game.local_id()
	wheel.front_index = maxi(0, seats.find_custom(func(seat): return seat.id == game.local_id()))
	wheel.queue_redraw()

func _render_pending_table() -> void:
	var cards := {}
	var own: int = game.local_id()
	# 宣布锁定时只知道玩家身份。空过和出牌使用同样的牌背。
	for id in game.committed_ids:
		if id != own:
			_set_table_card(cards, id, 0, {"face_up": false})
	for id in game.settlement_ids:
		if id != own:
			_set_table_card(cards, id, 1, {"face_up": false})
	var action: Dictionary = game.table_action()
	if action.get("type") == "play":
		action = action.duplicate()
		for card in game.public.get("hands", {}).get(own, []):
			if card.id == action.card_id:
				action["value"] = card.value
				break
	var face := _table_face(action)
	if not face.is_empty():
		_set_table_card(cards, own, 0, face)
	if game.phase == "settlement" and game.sealed_super:
		_set_table_card(cards, own, 1, _table_face({"type": "super"}))
	wheel.table_cards = cards

func _render_revealed_table(result: Dictionary) -> void:
	var cards := {}
	var own: int = game.local_id()
	for action in result.get("actions", []):
		var face := _table_face(action)
		if not face.is_empty():
			face["flip"] = action.peer_id != own
			_set_table_card(cards, action.peer_id, 0, face)
	for id in result.get("super_users", []):
		var face := _table_face({"type": "super"})
		face["flip"] = id != own
		_set_table_card(cards, id, 1, face)
	for id in wheel.table_cards:
		for slot in wheel.table_cards[id]:
			if not cards.get(id, {}).has(slot):
				_set_table_card(cards, id, slot, {"face_up": false, "discard": true})
	wheel.table_cards = cards

func _set_table_card(cards: Dictionary, id: int, slot: int, face: Dictionary) -> void:
	if not cards.has(id):
		cards[id] = {}
	cards[id][slot] = face

func _table_face(action: Dictionary) -> Dictionary:
	var kind: String = action.get("type", "")
	var face := {"face_up": true, "played": true}
	match kind:
		"play":
			if not action.has("value"):
				return {}
			face["caption"] = "%+d" % (int(action.value) * int(action.sign))
		"change":
			face["caption"] = "变化"
			face["points"] = "%+d" % (int(action.value) * int(action.sign))
		"defense":
			face["caption"] = "防御"
		"super":
			face["caption"] = "超级"
			face["points"] = "%+d" % game.super_steps
		_:
			return {}
	return face

func _deal_to_hand(slot: HandCard) -> void:
	_incoming_id = slot.card_id
	slot.modulate.a = 0.0
	var flight := _animation.parallel().tween_method(_position_incoming_card, 0.0, 1.0, DEAL_SECONDS)
	flight.finished.connect(_finish_hand_deal)

func _position_incoming_card(progress: float) -> void:
	# 商店更新可能重建扇形手牌，发牌始终对准当前牌位。
	var slot: HandCard = hand_fan.get_node_or_null("HandCard_%d" % _incoming_id)
	if slot == null or progress <= 0.0:
		return
	hand_scroll.ensure_control_visible(slot)
	wheel.self_deal = {
		"target": slot.get_global_transform() * (slot.size * 0.5),
		"angle": slot.get_global_transform().get_rotation(),
		"extent": slot.size * slot.scale,
		"card": {"face_up": true, "value": slot.value},
		"progress": progress,
	}

func _finish_hand_deal() -> void:
	if _incoming_id >= 0:
		var slot: HandCard = hand_fan.get_node_or_null("HandCard_%d" % _incoming_id)
		if slot != null:
			slot.modulate.a = 1.0
		_incoming_id = -1
	wheel.self_deal = {}

func _stop_animation() -> void:
	if _animation != null and _animation.is_valid():
		_animation.kill()
	_finish_hand_deal()
	_initial_spin = false
	_presenting_result = false
	wheel.tombstone_player_id = 0
	wheel.play_progress = 1.0
	wheel.number_scale = 1.0
	wheel.deal_progress = 1.0
	_set_table_height(0.0)

func _render_hand() -> void:
	var cards: Array = []
	for kind in HandCard.SPECIAL_NAMES:
		var amount: int = game.special_card_count(kind)
		if amount > 0:
			cards.append({"kind": kind, "quantity": amount})
	var action: Dictionary = game.table_action()
	var out_id: int = action.get("card_id", -1) if action.get("type") == "play" else -1
	for card in game.public.get("hands", {}).get(game.local_id(), []):
		if card.id != out_id:
			cards.append(card)
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
			if _incoming_id == button.card_id:
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
	$Table/CoinWindow.visible = not game.card_prices.is_empty()
	shop.present(_initial_spin or _presenting_result or wheel.view_height > 0.0)

	var is_local: bool = game.role == "local"
	count_picker.visible = is_local
	lives_picker.visible = is_local and game.game_mode == Rules.Mode.CLASSIC
	if _presenting_result:
		primary_button.text = "结算中"
		primary_button.disabled = true
		return
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
			if in_round and game._locked:
				primary_button.text = "已锁定"
			elif in_round and game._submitting:
				primary_button.text = "提交中"
			primary_button.disabled = not can_act
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
	var timed_phase: bool = game.phase in ["choosing", "settlement"]
	wheel.countdown_seconds = game.seconds_left() if timed_phase and not _initial_spin else -1
	var status: String = game.status.replace("金币", "筹码")
	if _presenting_result:
		match wheel.center_caption:
			"停盘":
				status = "停盘"
			"最终位移":
				status = "结算中"
			_:
				status = "公开出牌" if wheel.play_progress < 1.0 else "轮盘转动中"
	elif timed_phase:
		status = ""
	elif game.phase == "ended":
		var winner: int = int(game.last_result.get("winner", 0))
		status = "%s获胜" % ("你" if winner == game.local_id() else game.name_for(winner) + " ")
	if status_label.text == status:
		return
	status_label.text = status
	status_label.add_theme_color_override("font_color", Sketch.ACCENT if _presenting_result or game.phase in ["settlement", "result", "aborted"] else Sketch.MUTED)

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
			action_menu.set_special_card(HandCard.SPECIAL_NAMES["defense"], "被命中时保住本轮筹码。" if game.game_mode == Rules.Mode.GREED else "被命中时保住最后 1 点生命。")
		"super":
			action_menu.set_special_card(HandCard.SPECIAL_NAMES["super"], "最终位移增加 %d 格。" % game.super_steps)
		_:
			action_menu.set_card_value(button.value)

	var top: Vector2 = button.get_global_transform() * Vector2(button.size.x * 0.5, 0)
	action_overlay.show()
	action_menu.reset_size()
	var room: Vector2 = size - action_menu.size - Vector2(16, 16)
	var point := top - global_position - Vector2(action_menu.size.x * 0.5, action_menu.size.y + 14.0)
	action_menu.position = point.clamp(Vector2(16, 104), room.max(Vector2(16, 104)))

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
	_place_selected_on_table(0)
	_close_card_menu()
	game.submit_action(action)

func _use_selected_special() -> void:
	if not is_instance_valid(_selected_card) or _selected_card.disabled:
		return
	var kind: String = _selected_card.kind
	_place_selected_on_table(1 if kind == "super" else 0)
	_close_card_menu()
	if kind == "defense":
		game.submit_action({"type": kind})
	elif kind == "super":
		game.submit_settlement(true)

func _place_selected_on_table(slot: int) -> void:
	var origin: Vector2 = _selected_card.get_global_transform() * (_selected_card.size * 0.5)
	wheel.place_local_card(slot, origin, _selected_card.size * _selected_card.scale, _selected_card.rotation)

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
	if game == null or not visible:
		return
	if shop.is_open or shop.progress > 0.0:
		var right_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
		var escape: bool = event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE
		if right_click or escape:
			shop.close()
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
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

func _toggle_statistics() -> void:
	stats_panel.visible = not stats_panel.visible

func _render_statistics() -> void:
	var stats: Dictionary = game.public.get("stats", {})
	stats_totals.text = "已发 %d  /  已出 %d  /  剩余 %d" % [
		stats.get("issued", 0), stats.get("played", 0), stats.get("held", 0)]
	_clear_children(stats_grid)
	for header in ["牌", "已发", "已出", "离场弃" if game.game_mode == Rules.Mode.GREED else "淘汰弃", "剩余"]:
		_add_stat_cell(header, 10, Sketch.MUTED)
	var by_value: Dictionary = stats.get("by_value", {})
	var values := by_value.keys()
	values.sort()
	for value in values:
		_add_stat_cell(str(value), 12, Sketch.INK)
		for field in ["issued", "played", "discarded", "held"]:
			_add_stat_cell(str(by_value[value][field]), 12, Sketch.ACCENT if field == "held" else Sketch.INK)

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
