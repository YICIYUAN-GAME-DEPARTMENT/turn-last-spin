extends Control
## 全体玩家相同的占位 UI；Host 后台运行 Session，不额外生成管理控制台。
const WheelScript = preload("res://scripts/ui/wheel_view.gd")
@onready var game = $Session

var headline: Label
var message_label: Label
var address_input: LineEdit
var port_input: LineEdit
var connection_row: HBoxContainer
var lobby_box: VBoxContainer
var roster_label: Label
var ready_button: Button
var start_button: Button
var lives_spin: SpinBox
var game_box: HBoxContainer
var wheel: Control
var stage_label: Label
var public_label: Label
var score_label: Label
var action_row: HBoxContainer
var hand_choice: OptionButton
var draft_label: Label
var confirm_button: Button
var return_button: Button
var draft: Dictionary = {"type": "pass"}
var previous_hand_signature: String = ""
var auto_smoke: bool = false
var auto_ready_sent: bool = false
var auto_start_sent: bool = false
var auto_finished: bool = false
var auto_expected_players: int = 2
var auto_initial_lives: int = 1
var auto_silent: bool = false

func _ready() -> void:
	_build_layout()
	game.changed.connect(_refresh)
	_refresh()
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--turn-smoke-players="):
			auto_expected_players = clampi(int(arg.get_slice("=", 1)), 2, 12)
		if arg.begins_with("--turn-smoke-lives="):
			auto_initial_lives = clampi(int(arg.get_slice("=", 1)), 1, 5)
	auto_silent = args.has("--turn-smoke-silent")
	if args.has("--turn-smoke-host"):
		auto_smoke = true
		game.start_host(24680)
		game.set_initial_lives(auto_initial_lives)
	elif args.has("--turn-smoke-join"):
		auto_smoke = true
		game.join_host("127.0.0.1", 24680)

func _new_label(text_value: String = "", font_size: int = 16) -> Label:
	var node := Label.new()
	node.text = text_value
	node.add_theme_font_size_override("font_size", font_size)
	node.autowrap_mode = TextServer.AUTOWRAP_OFF
	return node

func _new_button(caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(callback)
	return button

func _build_layout() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("#142234")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	move_child(background, 0)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % edge, 18)
	add_child(margin)
	var vertical := VBoxContainer.new()
	vertical.add_theme_constant_override("separation", 9)
	margin.add_child(vertical)
	headline = _new_label("TURN · LAST SPIN   /   MINIMAL DEMO", 26)
	vertical.add_child(headline)
	message_label = _new_label("", 13)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vertical.add_child(message_label)
	connection_row = HBoxContainer.new()
	connection_row.add_theme_constant_override("separation", 8)
	vertical.add_child(connection_row)
	connection_row.add_child(_new_label("房主 IP:", 15))
	address_input = LineEdit.new()
	address_input.text = "127.0.0.1"
	address_input.custom_minimum_size = Vector2(170.0, 0.0)
	connection_row.add_child(address_input)
	connection_row.add_child(_new_label("端口:", 15))
	port_input = LineEdit.new()
	port_input.text = "24680"
	port_input.custom_minimum_size = Vector2(74.0, 0.0)
	connection_row.add_child(port_input)
	connection_row.add_child(_new_button("创建房间 (Host)", _on_host))
	connection_row.add_child(_new_button("直连加入 (Client)", _on_join))
	vertical.add_child(_new_label("占位资源 · Demo 使用 IP:端口直连；正式公网房间码、NAT/中继尚未实现。", 12))
	lobby_box = VBoxContainer.new()
	vertical.add_child(lobby_box)
	roster_label = _new_label("", 17)
	roster_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_box.add_child(roster_label)
	var lives_row := HBoxContainer.new()
	lives_row.add_theme_constant_override("separation", 8)
	lobby_box.add_child(lives_row)
	lives_row.add_child(_new_label("初始生命（全员相同）:", 15))
	lives_spin = SpinBox.new()
	lives_spin.min_value = 1.0
	lives_spin.max_value = 5.0
	lives_spin.step = 1.0
	lives_spin.value = 1.0
	lives_spin.custom_minimum_size = Vector2(105.0, 0.0)
	lives_spin.value_changed.connect(func(value: float): game.set_initial_lives(int(value)))
	lives_row.add_child(lives_spin)
	var lobby_actions := HBoxContainer.new()
	lobby_box.add_child(lobby_actions)
	ready_button = _new_button("准备", _on_ready)
	lobby_actions.add_child(ready_button)
	start_button = _new_button("房主开始", _on_start)
	lobby_actions.add_child(start_button)
	game_box = HBoxContainer.new()
	game_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_box.add_theme_constant_override("separation", 12)
	vertical.add_child(game_box)
	wheel = WheelScript.new()
	wheel.custom_minimum_size = Vector2(530.0, 500.0)
	wheel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wheel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_box.add_child(wheel)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(335.0, 0.0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_box.add_child(right)
	stage_label = _new_label("", 17)
	right.add_child(stage_label)
	right.add_child(_new_label("公开手牌（完整信息）", 15))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	public_label = _new_label("", 15)
	public_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(public_label)
	score_label = _new_label("", 13)
	right.add_child(score_label)
	action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 7)
	vertical.add_child(action_row)
	hand_choice = OptionButton.new()
	hand_choice.custom_minimum_size = Vector2(145.0, 0.0)
	action_row.add_child(hand_choice)
	action_row.add_child(_new_button("加 +", func(): _draft_play(1)))
	action_row.add_child(_new_button("减 -", func(): _draft_play(-1)))
	action_row.add_child(_new_button("不出牌 PASS", _draft_pass))
	draft_label = _new_label("当前选择：PASS", 14)
	draft_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(draft_label)
	confirm_button = _new_button("确认并锁定", _on_confirm)
	action_row.add_child(confirm_button)
	return_button = _new_button("结束后返回房间", _on_return)
	vertical.add_child(return_button)

func _on_host() -> void:
	game.start_host(_port())

func _on_join() -> void:
	game.join_host(address_input.text.strip_edges(), _port())

func _port() -> int:
	return clampi(int(port_input.text), 1, 65535)

func _on_ready() -> void:
	game.set_ready(not game.is_ready())

func _on_start() -> void:
	game.request_start()

func _on_return() -> void:
	game.request_return_lobby()

func _draft_pass() -> void:
	draft = {"type": "pass"}
	draft_label.text = "当前选择：PASS"

func _draft_play(sign_value: int) -> void:
	if hand_choice.item_count == 0:
		return
	var card_id: int = hand_choice.get_selected_id()
	if card_id <= 0:
		return
	draft = {"type": "play", "card_id": card_id, "sign": sign_value}
	draft_label.text = "当前选择：卡牌 #%d %s" % [card_id, "+" if sign_value == 1 else "-"]

func _on_confirm() -> void:
	game.submit_action(draft)

func _refresh() -> void:
	connection_row.visible = game.role == "none"
	message_label.text = "角色: %s   |   本地 ID: %d   |   %s" % [game.role, game.local_id(), game.status]
	lobby_box.visible = game.phase == "lobby"
	game_box.visible = game.phase in ["choosing", "revealing", "result", "ended", "aborted"]
	action_row.visible = game.phase == "choosing" and game.public.get("alive", []).has(game.local_id())
	confirm_button.disabled = not game.can_act()
	if game.phase == "lobby":
		var lines: Array[String] = ["房间已建立（单房间 Demo，最多 12 人）。"]
		for member in game.members:
			lines.append("%s%s    %s%s" % [
				str(member["name"]), " (YOU)" if int(member["id"]) == game.local_id() else "",
				"已准备" if bool(member["ready"]) else "未准备",
				"" if bool(member["online"]) else " (离线)"
			])
		roster_label.text = "\n".join(lines)
		lives_spin.set_value_no_signal(float(game.initial_lives))
		lives_spin.editable = game.am_host()
		ready_button.text = "取消准备" if game.is_ready() else "准备"
		start_button.disabled = not game.am_host() or not game.all_ready()
	return_button.visible = game.am_host() and game.phase in ["ended", "aborted"]
	if game_box.visible:
		_update_match_ui()
	if auto_smoke and not auto_finished and game.phase in ["ended", "aborted"]:
		auto_finished = true
		var final_phase: String = game.phase
		print("TURN_SMOKE_FINAL peer=%d phase=%s" % [game.local_id(), final_phase])
		get_tree().create_timer(0.8).timeout.connect(func(): get_tree().quit(0 if final_phase == "ended" else 5))

func _update_match_ui() -> void:
	var state: Dictionary = game.public
	wheel.present(state, game.members, game.local_id())
	var alive: Array = state.get("alive", [])
	stage_label.text = "第 %d 轮 / 存活 %d 人 / 阶段: %s" % [
		int(state.get("round", 0)), alive.size(), game.phase
	]
	var texts: Array[String] = []
	var hands: Dictionary = state.get("hands", {})
	for peer_id in alive:
		var hand: Array = hands.get(peer_id, [])
		var cards: Array[String] = []
		for card in hand:
			cards.append("%d (#%d)" % [int(card["value"]), int(card["id"])])
		var life_count: int = int(state.get("lives", {}).get(peer_id, 1))
		texts.append("%s  [生命 %d/%d]: %s" % [
			game.name_for(int(peer_id)), life_count, int(state.get("initial_lives", 1)), ", ".join(cards)
		])
	public_label.text = "\n".join(texts)
	var stats: Dictionary = state.get("stats", {})
	score_label.text = "已发 %d   已出 %d   淘汰弃 %d   剩余 %d" % [
		int(stats.get("issued", 0)), int(stats.get("played", 0)),
		int(stats.get("discarded", 0)), int(stats.get("held", 0))
	]
	if game.phase == "ended":
		score_label.text += "\n最终胜者：%s" % game.name_for(int(game.last_result.get("winner", 0)))
	_rebuild_hand_list()

func _rebuild_hand_list() -> void:
	var hand: Array = game.public.get("hands", {}).get(game.local_id(), [])
	var parts: Array[String] = []
	for card in hand:
		parts.append(str(card["id"]))
	var signature: String = "%s:%d:%s" % [str(game.public.get("round", 0)), game.local_id(), ",".join(parts)]
	if signature == previous_hand_signature:
		return
	previous_hand_signature = signature
	hand_choice.clear()
	for card in hand:
		hand_choice.add_item("%d (#%d)" % [int(card["value"]), int(card["id"])], int(card["id"]))
	_draft_pass()

func _process(_delta: float) -> void:
	if game.phase == "choosing":
		stage_label.text = "第 %d 轮 / 存活 %d 人 / 倒计时 %d 秒 / 已确认 %d 人" % [
			int(game.public.get("round", 0)), game.public.get("alive", []).size(),
			game.seconds_left(), game.commit_count
		]
	if not auto_smoke or auto_finished:
		return
	# 自动化双实例测试；正常玩家不会调用这些逻辑。
	if game.phase == "lobby":
		if not auto_ready_sent and game.local_id() > 0:
			auto_ready_sent = true
			game.set_ready(true)
		if game.am_host() and game.all_ready() and game.members.size() >= auto_expected_players and not auto_start_sent:
			auto_start_sent = true
			game.request_start()
	elif game.phase == "choosing" and game.can_act() and not auto_silent:
		var action: Dictionary = {"type": "pass"}
		if game.am_host() and int(game.public.get("round", 0)) == 1:
			var my_hand: Array = game.public.get("hands", {}).get(game.local_id(), [])
			if not my_hand.is_empty():
				action = {"type": "play", "card_id": int(my_hand[0]["id"]), "sign": 1}
		game.submit_action(action)
	# 自动化结束由 _refresh 的事件驱动完成，避免 Host 断开时丢失终局状态。
