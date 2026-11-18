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
@onready var round_label: Label = $Table/Round
@onready var status_label: Label = $Table/Status
@onready var count_picker: OptionButton = $Table/Toolbar/PlayerCount
@onready var lives_picker: OptionButton = $Table/InitialLives
@onready var shop_button: Button = $Table/ShopButton
@onready var shop = $Table/SpecialShop
@onready var restart_button: Button = $Table/Toolbar/Restart
@onready var menu_button: Button = $Table/Toolbar/Menu
@onready var hand_grid: GridContainer = $Table/HandPanel/Column/Scroll/Cards
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
var _wheel_hidden_counts: Dictionary = {}
var _round_key: String = ""
var _last_phase: String = ""
var _rendered_hand: Array = []
var _selected_card: Button
var _initial_spin: bool = false
var _animation: Tween

func _ready() -> void:
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
	_clear_children(hand_grid)

func present() -> void:
	var round_number: int = int(game.public.get("round", 0))
	var round_key: String = "%d:%d" % [game.match_id, round_number]
	var phase: String = game.phase
	if phase == "choosing" and _round_key != round_key:
		_round_key = round_key
		_round_state = game.public
		_close_card_menu()
		_show_wheel({})
		_render_statistics()
	elif phase in ["result", "ended"] and phase != _last_phase:
		_show_wheel(game.last_result)
		_render_statistics()
	elif game.public.get("hidden_card_counts", {}) != _wheel_hidden_counts:
		_update_wheel_seats(game.last_result if phase in ["result", "ended"] else {})
	_last_phase = phase
	round_label.text = "turn  %d" % round_number
	_render_hand()
	_refresh_controls()

func reset() -> void:
	_round_key = ""
	_last_phase = ""
	_round_state = {}
	_wheel_hidden_counts.clear()
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
		_tween_pointer(target, 0.85)
	else:
		wheel.needle_angle = target
		_tween_pointer(target + float(delta) * step, 0.95)

func _update_wheel_seats(result: Dictionary) -> void:
	var seats: Array = []
	var played_cards: Dictionary = {}
	var revealed: Dictionary = {}
	for action in result.get("actions", []):
		var id: int = int(action["peer_id"])
		match action["type"]:
			"play":
				played_cards[id] = int(action["card_id"])
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
		for card in _round_state["hands"].get(id, []):
			cards.append({
				"value": card["value"], "face_up": true,
				"played": int(card["id"]) == played_cards.get(id, -1)
			})
		var played_specials: Array = revealed.get(id, [])
		cards.append_array(played_specials)
		var quantity: int = int(counts.get(id, maxi(0, int(round_counts.get(id, 0)) - played_specials.size())))
		if quantity > 0:
			cards.append({"face_up": false, "quantity": quantity})
		var hp: int = int(game.public.get("lives", {}).get(id, 0))
		seats.append({"id": id, "name": game.name_for(id), "alive": hp > 0, "hp": hp, "cards": cards})
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

func _stop_animation() -> void:
	if _animation != null and _animation.is_valid():
		_animation.kill()
	_initial_spin = false

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
	_clear_children(hand_grid)
	for card in cards:
		var button = HandCardScene.instantiate()
		button.kind = card.get("kind", "play")
		if button.kind == "play":
			button.card_id = int(card["id"])
			button.value = int(card["value"])
			button.name = "HandCard_%d" % button.card_id
		else:
			button.quantity = int(card["quantity"])
			button.name = "SpecialCard_%s" % button.kind
		button.pressed.connect(_open_card_menu.bind(button))
		hand_grid.add_child(button)

func _refresh_controls() -> void:
	_update_status()
	var can_act: bool = game.can_act() and not _initial_spin
	var can_use_super: bool = game.can_settle() and game.special_card_count("super") > 0
	for button in hand_grid.get_children():
		button.disabled = not (can_use_super if button.kind == "super" else can_act)
	if is_instance_valid(_selected_card) and _selected_card.disabled:
		_close_card_menu()

	shop.game = game
	shop_button.visible = not game.card_prices.is_empty()
	shop_button.text = "商店 · %dr" % game.balance
	if shop.visible:
		shop.present()

	var is_local: bool = game.role == "local"
	count_picker.visible = is_local
	lives_picker.visible = is_local
	if is_local:
		count_picker.select(count_picker.get_item_index(game.members.size()))
		lives_picker.select(lives_picker.get_item_index(game.initial_lives))
	restart_button.visible = is_local
	menu_button.visible = is_local and allow_menu
	primary_button.disabled = true
	match game.phase:
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
	if game.phase == "choosing":
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
	match button.kind:
		"change":
			action_menu.set_change_range(game.public.get("alive", []).size())
		"defense":
			action_menu.set_special_card(HandCard.SPECIAL_NAMES["defense"], "被命中时保住最后 1 点生命。")
		"super":
			action_menu.set_special_card(HandCard.SPECIAL_NAMES["super"], "最终位移增加 %d 格。" % game.super_steps)
		_:
			action_menu.set_card_value(button.value)

	var point: Vector2 = button.global_position - global_position + Vector2(button.size.x + 12.0, -12.0)
	action_overlay.show()
	action_menu.reset_size()
	var room: Vector2 = size - action_menu.size - Vector2(16, 16)
	action_menu.position = point.clamp(Vector2(16, 76), room.max(Vector2(16, 76)))

func _close_card_menu() -> void:
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
	_close_card_menu()
	game.submit_action(action)

func _use_selected_special() -> void:
	if not is_instance_valid(_selected_card) or _selected_card.disabled:
		return
	var kind: String = _selected_card.kind
	_close_card_menu()
	if kind == "defense":
		game.submit_action({"type": kind})
	elif kind == "super":
		game.submit_settlement(true)

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
	for header in ["牌", "已发", "已出", "淘汰弃", "剩余"]:
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
