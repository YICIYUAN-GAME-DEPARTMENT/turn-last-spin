extends Control
## 固定正俯视角的冷战讽刺漫画对局主视图：协调轮盘、明牌席位、倒计时指挥条、手牌扇区与暗市商店

signal menu_requested
signal restart_requested
signal player_count_changed(count: int)
signal initial_lives_changed(lives: int)

const HandCardScene = preload("res://scenes/ui/hand_card.tscn")
const HandCard = preload("res://scripts/ui/hand_card.gd")
const Rules = preload("res://scripts/core/game_rules.gd")
const Ink = preload("res://scripts/ui/editorial_ink.gd")
const DEAL_SECONDS := 0.68

@onready var table: Control = $Table
@onready var wheel = $Table/Wheel
@onready var mode_badge: Label = %ModeBadge
@onready var round_label = $Table/Round
@onready var round_announcement: Label = $RoundAnnouncement
@onready var status_label: Label = $Table/Status
@onready var count_picker: OptionButton = %PlayerCount
@onready var lives_picker: OptionButton = %InitialLives
@onready var ranking_panel: Control = %RankingPanel
@onready var ranking_label: Label = %Ranking
@onready var wallet_frame: Control = %WalletFrame
@onready var coins = %Reels
@onready var hand_panel: Control = $Table/HandPanel
@onready var reward = $RoundReward
@onready var shop = $SpecialShop
@onready var restart_button: Button = %Restart
@onready var menu_button: Button = %Menu
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
var _phase_duration: float = 15.0
var _rendered_hand: Array = []
var _selected_card: Button
var _incoming_id: int = -1
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
	lives_picker.item_selected.connect(func(index: int) -> void:
		initial_lives_changed.emit(lives_picker.get_item_id(index)))
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	primary_button.pressed.connect(_on_primary)
	$Table/Toolbar/Statistics.pressed.connect(_toggle_statistics)
	shop.view_changed.connect(_on_shop_view_changed)
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
	if phase != "round_intro" and round_announcement.visible:
		_hide_round_announcement()

	if phase != _last_phase:
		if phase == "choosing":
			_phase_duration = maxf(1.0, game.phase_time_left())
		elif phase == "settlement":
			_phase_duration = maxf(1.0, game.phase_time_left())

	var new_deal := phase == "choosing" and _round_key != round_key
	if phase == "round_intro" and (_last_phase != phase or _display_match_id != game.match_id):
		_stop_animation()
		wheel.clear_placements()
		wheel.table_cards = {}
		wheel.hit_defended = false
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
		wheel.queue_redraw()
		_render_statistics()
	elif phase == "settlement" and _round_key != round_key:
		_round_key = round_key
		_round_state = game.public
		_update_wheel_seats({})
		wheel.start_index = int(_round_state.get("initial_index", 0))
		wheel.needle_angle = wheel.seat_angle(wheel.start_index)
		wheel.target_index = -1
		wheel.hit_defended = false
		wheel.center_caption = "初始席位"
		wheel.center_steps = "%02d" % (wheel.start_index + 1)
		wheel.showing_actions = false
		_render_statistics()
	elif phase in ["result", "ended"] and phase != _last_phase:
		if _round_key != round_key:
			_round_key = round_key
			_round_state = game.public.duplicate(true)
			_round_state["initial_index"] = game.last_result.get("initial_index", 0)
			var action_peers: Array = []
			for a_var in game.last_result.get("actions", []):
				var a: Dictionary = a_var
				action_peers.append(a["peer_id"])
			_round_state["alive"] = action_peers
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
		var hands_dict: Dictionary = game.public.get("hands", {})
		var hand: Array = hands_dict.get(game.local_id(), [])
		if not hand.is_empty():
			var last_card: Dictionary = hand.back()
			var slot: HandCard = hand_fan.get_node_or_null("HandCard_%d" % int(last_card["id"]))
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
		var order: Dictionary = {}
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
		reward.play(int(payout["gain"]), payout["result"], coins)

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
	wheel.countdown_ratio = 0.0
	wheel.hit_defended = false
	_round_key = ""
	_display_match_id = -1
	_last_phase = ""
	_round_state = {}
	_wheel_hidden_counts.clear()
	_wheel_balances.clear()
	round_label.set_number(0)
	round_label.countdown_seconds = -1
	round_label.countdown_ratio = 0.0
	_stop_animation()
	_close_card_menu()
	stats_panel.hide()
	shop.reset()

func _show_round_announcement(number: int, duration: float) -> void:
	_hide_round_announcement()
	round_announcement.text = "TURN %d" % number
	round_announcement.modulate.a = 0.0
	round_announcement.pivot_offset = round_announcement.size * 0.5
	round_announcement.scale = Vector2.ONE * 1.12
	round_announcement.rotation = deg_to_rad(-2.4)
	round_announcement.show()

	_announcement_animation = create_tween()
	_announcement_animation.tween_property(round_announcement, "modulate:a", 1.0, duration * 0.16)
	_announcement_animation.parallel().tween_property(round_announcement, "scale", Vector2.ONE, duration * 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_announcement_animation.tween_interval(duration * 0.44)
	_announcement_animation.tween_property(round_announcement, "modulate:a", 0.0, duration * 0.24)
	_announcement_animation.finished.connect(func() -> void:
		_announcement_animation = null
		_hide_round_announcement())

func _hide_round_announcement() -> void:
	if _announcement_animation != null and _announcement_animation.is_valid():
		_announcement_animation.kill()
	round_announcement.hide()

func _show_wheel(result: Dictionary) -> void:
	_stop_animation()
	_presenting_result = not result.is_empty()
	_update_wheel_seats(result)
	wheel.start_index = int(_round_state.get("initial_index", 0))
	wheel.target_index = -1
	wheel.hit_defended = bool(result.get("defended", false))
	var delta: int = int(result.get("delta", 0))
	wheel.center_caption = "初始席位" if result.is_empty() else "准备翻牌"
	wheel.center_steps = "—"

	var step: float = TAU / float(maxi(1, wheel.seats.size()))
	var target: float = wheel.seat_angle(wheel.start_index)
	wheel.showing_actions = not result.is_empty()
	if wheel.showing_actions:
		_render_revealed_table(result)
	else:
		wheel.clear_placements()
		wheel.table_cards = {}
	shop.close()

	# 固定正俯视角：移除一切升镜/降镜切换，保留流畅转盘、停盘悬念与发牌节奏
	_animation = create_tween()
	if result.is_empty():
		_initial_spin = true
		wheel.needle_angle = target - TAU
		wheel.deal_progress = 0.0
		_animation.tween_property(wheel, "needle_angle", target, 0.72).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_animation.tween_callback(func() -> void:
			wheel.center_steps = "%02d" % (wheel.start_index + 1)
			wheel.queue_redraw())
		_animation.tween_interval(presentation_timing.wheel_stop_hold)
		_animation.tween_property(wheel, "deal_progress", 1.0, DEAL_SECONDS)
	else:
		var landing: int = int(result["target_index"])
		wheel.needle_angle = target
		wheel.play_progress = 0.0
		_animation.tween_interval(presentation_timing.RESULT_CAMERA_LIFT_SECONDS)
		_animation.tween_property(wheel, "play_progress", 1.0, presentation_timing.RESULT_REVEAL_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_animation.tween_callback(func() -> void:
			wheel.center_caption = "转动中"
			wheel.queue_redraw()
			_update_status())
		_animation.tween_method(func(value: float) -> void:
			wheel.needle_angle = target + value * step,
			0.0, float(delta), presentation_timing.RESULT_ROTATION_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_animation.tween_callback(func() -> void:
			wheel.center_caption = "停盘"
			wheel.queue_redraw()
			_update_status())
		_animation.tween_interval(presentation_timing.wheel_stop_hold)
		_animation.tween_callback(func() -> void:
			wheel.target_index = landing
			wheel.center_caption = "最终位移"
			wheel.center_steps = ("−" if delta < 0 else "+") + str(absi(delta))
			wheel.queue_redraw()
			_update_status())
		_animation.tween_method(func(t: float) -> void:
			wheel.number_scale = 1.0 + 0.24 * sin(PI * t)
			wheel.queue_redraw(), 0.0, 1.0, presentation_timing.RESULT_NUMBER_PULSE_SECONDS)
		_animation.tween_interval(presentation_timing.RESULT_CAMERA_RETURN_SECONDS)
	_animation.finished.connect(_on_wheel_animation_finished.bind(result))

func _on_wheel_animation_finished(result: Dictionary) -> void:
	_initial_spin = false
	_presenting_result = false
	if not result.is_empty():
		_update_wheel_seats(result)
		_render_statistics()
		_render_hand()
		_sync_wallet(true)
	_refresh_controls()

func _on_shop_view_changed(amount: float) -> void:
	if amount > 0.0:
		stats_panel.hide()
		_close_card_menu()

func _update_wheel_seats(result: Dictionary) -> void:
	var seats: Array = []
	var played_cards: Dictionary = {}
	var spent_specials: Dictionary = {}
	for action_var in result.get("actions", []):
		var action: Dictionary = action_var
		var id: int = int(action["peer_id"])
		match str(action["type"]):
			"play":
				played_cards[id] = int(action["card_id"])
			"defense", "change":
				spent_specials[id] = 1
	for id_var in result.get("super_users", []):
		var id: int = int(id_var)
		spent_specials[id] = int(spent_specials.get(id, 0)) + 1

	var visible_state: Dictionary = _round_state if _presenting_result else game.public
	var counts: Dictionary = visible_state.get("hidden_card_counts", {})
	var round_counts: Dictionary = _round_state.get("hidden_card_counts", {})
	var hands_map: Dictionary = _round_state.get("hands", {})
	var balances_map: Dictionary = visible_state.get("balances", {})
	var lives_map: Dictionary = visible_state.get("lives", {})

	for id_var in _round_state.get("alive", []):
		var id: int = int(id_var)
		var cards: Array = []
		var raw_hand: Array = hands_map.get(id, [])
		for card_var in raw_hand:
			var card: Dictionary = card_var
			cards.append({
				"id": int(card["id"]),
				"value": int(card["value"]),
				"face_up": true,
				"played": int(card["id"]) == int(played_cards.get(id, -1))
			})
		var spent: int = int(spent_specials.get(id, 0))
		var quantity: int = int(counts.get(id, maxi(0, int(round_counts.get(id, 0)) - spent)))
		if quantity > 0:
			cards.append({"face_up": false, "quantity": quantity})
		var dealt_id: int = int((raw_hand.back() as Dictionary)["id"]) if not raw_hand.is_empty() else -1
		var seat: Dictionary = {
			"id": id,
			"name": game.name_for(id),
			"cards": cards,
			"dealt_id": dealt_id
		}
		if id != game.local_id() and visible_state.has("balances"):
			seat["balance"] = int(balances_map.get(id, 0))
		if game.game_mode == Rules.Mode.CLASSIC:
			var hp: int = int(lives_map.get(id, 0))
			seat["hp"] = hp
			seat["alive"] = hp > 0
		else:
			seat["alive"] = true
		seats.append(seat)

	_wheel_balances = balances_map.duplicate()
	_wheel_hidden_counts = counts.duplicate()
	wheel.seats = seats
	wheel.local_player_id = game.local_id()
	wheel.front_index = maxi(0, seats.find_custom(func(s: Dictionary) -> bool: return int(s["id"]) == game.local_id()))
	wheel.queue_redraw()

func _render_pending_table() -> void:
	var cards: Dictionary = {}
	var own: int = game.local_id()
	for id_var in game.committed_ids:
		var id: int = int(id_var)
		if id != own:
			_set_table_card(cards, id, 0, {"face_up": false})
	for id_var in game.settlement_ids:
		var id: int = int(id_var)
		if id != own:
			_set_table_card(cards, id, 1, {"face_up": false})
	var action: Dictionary = game.table_action()
	if str(action.get("type", "")) == "play":
		action = action.duplicate()
		var hands_dict: Dictionary = game.public.get("hands", {})
		for card_var in hands_dict.get(own, []):
			var card: Dictionary = card_var
			if int(card["id"]) == int(action["card_id"]):
				action["value"] = int(card["value"])
				break
	var face := _table_face(action)
	if not face.is_empty():
		_set_table_card(cards, own, 0, face)
	if game.phase == "settlement" and game.sealed_super:
		_set_table_card(cards, own, 1, _table_face({"type": "super"}))
	wheel.table_cards = cards

func _render_revealed_table(result: Dictionary) -> void:
	var cards: Dictionary = {}
	var own: int = game.local_id()
	for action_var in result.get("actions", []):
		var action: Dictionary = action_var
		var face := _table_face(action)
		if not face.is_empty():
			var pid: int = int(action["peer_id"])
			face["flip"] = pid != own
			_set_table_card(cards, pid, 0, face)
	for id_var in result.get("super_users", []):
		var id: int = int(id_var)
		var face := _table_face({"type": "super"})
		face["flip"] = id != own
		_set_table_card(cards, id, 1, face)
	for id_key in wheel.table_cards:
		var slot_map: Dictionary = wheel.table_cards[id_key]
		for slot_key in slot_map:
			if not (cards.get(id_key, {}) as Dictionary).has(slot_key):
				_set_table_card(cards, int(id_key), int(slot_key), {"face_up": false, "discard": true})
	wheel.table_cards = cards

func _set_table_card(cards: Dictionary, id: int, slot: int, face: Dictionary) -> void:
	if not cards.has(id):
		cards[id] = {}
	cards[id][slot] = face

func _table_face(action: Dictionary) -> Dictionary:
	var kind: String = str(action.get("type", ""))
	var face: Dictionary = {"face_up": true, "played": true}
	match kind:
		"play":
			if not action.has("value"):
				return {}
			face["caption"] = "%+d" % (int(action["value"]) * int(action["sign"]))
		"change":
			face["caption"] = "变化"
			face["points"] = "%+d" % (int(action["value"]) * int(action["sign"]))
		"defense":
			face["caption"] = "防御"
		"super":
			face["caption"] = "超级"
			face["points"] = "%+d" % int(game.super_steps)
		_:
			return {}
	return face

func _deal_to_hand(slot: HandCard) -> void:
	_incoming_id = slot.card_id
	slot.modulate.a = 0.0
	var flight := _animation.parallel().tween_method(_position_incoming_card, 0.0, 1.0, DEAL_SECONDS)
	flight.finished.connect(_finish_hand_deal)

func _position_incoming_card(progress: float) -> void:
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
	wheel.play_progress = 1.0
	wheel.number_scale = 1.0
	wheel.deal_progress = 1.0

func _render_hand() -> void:
	var cards: Array = []
	for kind in HandCard.SPECIAL_NAMES:
		var amount: int = game.special_card_count(kind)
		if amount > 0:
			cards.append({"kind": kind, "quantity": amount})
	var action: Dictionary = game.table_action()
	var out_id: int = int(action.get("card_id", -1)) if str(action.get("type", "")) == "play" else -1
	var hands_dict: Dictionary = game.public.get("hands", {})
	for card_var in hands_dict.get(game.local_id(), []):
		var card: Dictionary = card_var
		if int(card["id"]) != out_id:
			cards.append(card)

	var total: int = 0
	for card_var in cards:
		var card: Dictionary = card_var
		total += int(card.get("quantity", 1))
	hand_title.text = "HAND // 我的手牌  %02d" % total
	if cards == _rendered_hand:
		return

	_close_card_menu()
	_rendered_hand = cards
	_clear_children(hand_fan)
	for card_var in cards:
		var card: Dictionary = card_var
		var button = HandCardScene.instantiate()
		button.kind = str(card.get("kind", "play"))
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
	mode_badge.text = "♦ GREED" if game.game_mode == Rules.Mode.GREED else "♦ CLASSIC"
	var can_act: bool = game.can_act() and not _initial_spin
	var can_use_super: bool = game.can_settle() and game.special_card_count("super") > 0
	for child in hand_fan.get_children():
		if child is Button:
			var btn: Button = child
			btn.disabled = not (can_use_super if btn.get("kind") == "super" else can_act)
	if is_instance_valid(_selected_card) and _selected_card.disabled:
		_close_card_menu()

	shop.game = game
	wallet_frame.visible = not game.card_prices.is_empty()
	shop.present(_initial_spin or _presenting_result)

	var is_local: bool = game.role == "local"
	count_picker.visible = is_local
	lives_picker.visible = is_local and game.game_mode == Rules.Mode.CLASSIC
	if _presenting_result:
		primary_button.text = "结算中"
		primary_button.disabled = true
		return

	var ranking: Array = game.public.get("ranking", [])
	ranking_panel.visible = not ranking.is_empty()
	if ranking_panel.visible:
		var lines := PackedStringArray(["♦ 最终排名" if game.phase == "ended" else "♦ 已达标退席"])
		var balances: Dictionary = game.public.get("balances", {})
		for index in range(ranking.size()):
			var id: int = int(ranking[index])
			var entry := "第 %d 名  %s" % [index + 1, "你" if id == game.local_id() else game.name_for(id)]
			if id != game.local_id() and balances.has(id):
				entry += "  %dr" % int(balances[id])
			lines.append(entry)
		ranking_label.text = "\n".join(lines)

	if is_local:
		count_picker.select(count_picker.get_item_index(game.members.size()))
		lives_picker.select(lives_picker.get_item_index(game.initial_lives))
	restart_button.visible = is_local
	menu_button.visible = is_local and allow_menu
	primary_button.disabled = true
	primary_button.theme_type_variation = &"InkButton"
	match game.phase:
		"round_intro":
			primary_button.text = "准备发牌"
		"choosing":
			var alive_list: Array = game.public.get("alive", [])
			var in_round: bool = alive_list.has(game.local_id())
			primary_button.text = "不出牌  /  PASS" if in_round else "观战中"
			if in_round and game._locked:
				primary_button.text = "✓  已锁定"
			elif in_round and game._submitting:
				primary_button.text = "提交中…"
			primary_button.disabled = not can_act
		"settlement":
			primary_button.text = "跳过超级卡" if can_use_super else "确认结算"
			primary_button.theme_type_variation = &"CrimsonButton" if game.can_settle() else &"InkButton"
			if game.settlement_submitted:
				primary_button.text = "等待结算…"
			elif not (game.public.get("alive", []) as Array).has(game.local_id()):
				primary_button.text = "观战中"
			primary_button.disabled = not game.can_settle()
		"result":
			primary_button.text = "等待下一轮"
		"ended", "aborted":
			primary_button.text = "对局结束"
			primary_button.theme_type_variation = &"CrimsonButton"
			if is_local:
				primary_button.text = "♦  再来一局"
			elif game.am_host():
				primary_button.text = "♦  返回房间"
			primary_button.disabled = not (is_local or game.am_host())

func _update_status() -> void:
	var timed_phase: bool = game.phase in ["choosing", "settlement"]
	var show_clock: bool = timed_phase and not _initial_spin
	var secs: int = game.seconds_left() if show_clock else -1
	var ratio: float = clampf(game.phase_time_left() / maxf(1.0, _phase_duration), 0.0, 1.0) if show_clock else 0.0

	wheel.countdown_seconds = secs
	wheel.countdown_ratio = ratio
	round_label.countdown_seconds = secs
	round_label.countdown_ratio = ratio

	var alive_count: int = (game.public.get("alive", []) as Array).size()
	var caption := ""
	var locked_str := ""
	var urgent := false

	if _presenting_result:
		urgent = true
		match wheel.center_caption:
			"停盘":
				caption = "停盘待定"
			"最终位移":
				caption = "结算落地"
			_:
				caption = "公开出牌" if wheel.play_progress < 1.0 else "轮盘转动"
	else:
		match game.phase:
			"round_intro":
				caption = "新回合发牌"
			"choosing":
				caption = "定初始指向" if _initial_spin else "出牌决策"
				if not _initial_spin and alive_count > 0:
					locked_str = "已锁 %d / %d" % [int(game.commit_count), alive_count]
			"settlement":
				caption = "超级卡窗口"
				urgent = true
				if alive_count > 0:
					locked_str = "已确认 %d / %d" % [(game.settlement_ids as Array).size(), alive_count]
			"result":
				caption = "单轮结算"
			"ended":
				caption = "会议终局"
				urgent = true
			"aborted":
				caption = "会议中止"
				urgent = true
			_:
				caption = "等待中"

	round_label.phase_caption = caption
	round_label.locked_text = locked_str
	round_label.phase_urgent = urgent

	var status_str: String = str(game.status).replace("金币", "筹码")
	if _presenting_result:
		match wheel.center_caption:
			"停盘":
				status_str = "指针已停稳，正在核对结果…"
			"最终位移":
				status_str = "本轮结算完成"
			_:
				status_str = "全员翻牌公开中…" if wheel.play_progress < 1.0 else "轮盘转动中…"
	elif timed_phase:
		if _initial_spin:
			status_str = "正在确定本轮初始指向…"
		elif game.phase == "choosing":
			status_str = "点击下方手牌选择加减，或点击右侧「不出牌」" if game.can_act() else status_str
		elif game.phase == "settlement":
			status_str = "如有超级卡可现在打出，否则确认结算" if game.can_settle() else "等待其他代表确认结算…"
	elif game.phase == "ended":
		var winner: int = int(game.last_result.get("winner", 0))
		status_str = "♦ %s获得最终胜利！" % ("你" if winner == game.local_id() else game.name_for(winner) + " ")

	if status_label.text != status_str:
		status_label.text = status_str
		status_label.add_theme_color_override("font_color",
			Ink.CRIMSON if (_presenting_result or game.phase in ["settlement", "result", "ended", "aborted"]) else Ink.INK_SOFT)

func _process(_delta: float) -> void:
	if visible and game != null and game.phase in ["choosing", "settlement"]:
		_update_status()

func _open_card_menu(button: Button) -> void:
	if button.disabled:
		return
	_selected_card = button
	hand_fan.pin(button)
	var kind: String = str(button.get("kind"))
	match kind:
		"change":
			action_menu.set_change_range((game.public.get("alive", []) as Array).size())
		"defense":
			action_menu.set_special_card(HandCard.SPECIAL_NAMES["defense"],
				"被命中时保住本轮筹码。" if game.game_mode == Rules.Mode.GREED else "被命中时保住最后 1 点生命。")
		"super":
			action_menu.set_special_card(HandCard.SPECIAL_NAMES["super"], "最终位移额外增加 %d 格。" % int(game.super_steps))
		_:
			action_menu.set_card_value(int(button.get("value")))

	var top: Vector2 = button.get_global_transform() * Vector2(button.size.x * 0.5, 0.0)
	action_overlay.show()
	action_menu.reset_size()
	var room: Vector2 = size - action_menu.size - Vector2(18.0, 18.0)
	var point := top - global_position - Vector2(action_menu.size.x * 0.5, action_menu.size.y + 16.0)
	action_menu.position = point.clamp(Vector2(18.0, 96.0), room.max(Vector2(18.0, 96.0)))

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
	var kind: String = str(_selected_card.get("kind"))
	match kind:
		"play":
			action = {"type": "play", "card_id": int(_selected_card.get("card_id")), "sign": direction}
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
	var kind: String = str(_selected_card.get("kind"))
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
	stats_totals.text = "已发 %d / 已出 %d / 剩余 %d" % [
		int(stats.get("issued", 0)), int(stats.get("played", 0)), int(stats.get("held", 0))]
	_clear_children(stats_grid)
	var headers: Array[String] = ["牌", "已发", "已出", "离场弃" if game.game_mode == Rules.Mode.GREED else "淘汰弃", "剩余"]
	for header in headers:
		_add_stat_cell(header, 11, Ink.INK_SOFT)
	var by_value: Dictionary = stats.get("by_value", {})
	var values: Array = by_value.keys()
	values.sort()
	for value in values:
		_add_stat_cell(str(value), 13, Ink.INK)
		var fields: Array[String] = ["issued", "played", "discarded", "held"]
		for field in fields:
			var row_dict: Dictionary = by_value[value]
			_add_stat_cell(str(int(row_dict[field])), 13, Ink.CRIMSON if field == "held" else Ink.INK)

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
