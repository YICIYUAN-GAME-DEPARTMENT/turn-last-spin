extends Control
## 客户端大厅与牌局界面。
const WheelScript = preload("res://scripts/ui/wheel_view.gd")
const NetBridge = preload("res://scripts/network/net_bridge.gd")
const Rules = preload("res://scripts/core/game_rules.gd")
@onready var game = $Session

var message_label: Label
var connect_button: Button
var disconnect_button: Button
var leave_button: Button
var room_row: HBoxContainer
var room_code_input: LineEdit
var lobby_box: VBoxContainer
var roster_label: Label
var ready_button: Button
var start_button: Button
var lives_spin: SpinBox
var member_admin: HBoxContainer
var member_choice: OptionButton
var game_box: HBoxContainer
var wheel: Control
var stage_label: Label
var public_label: Label
var score_label: Label
var reveal_label: Label
var action_row: HBoxContainer
var hand_choice: OptionButton
var draft_label: Label
var confirm_button: Button
var action_buttons: Array[BaseButton] = []
var return_button: Button
var draft: Dictionary = {"type": "pass"}
var previous_hand_signature: String = ""
var _server_address: String = ProjectSettings.get_setting("turn/network/server_address", "127.0.0.1")
var _server_port := NetBridge.DEFAULT_PORT

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--turn-address="):
			_server_address = argument.trim_prefix("--turn-address=")
		elif argument.begins_with("--turn-port="):
			_server_port = int(argument.trim_prefix("--turn-port="))
	_build_layout()
	game.changed.connect(_refresh)
	_refresh()
	_connect_on_launch.call_deferred()

func _connect_on_launch() -> void:
	# 手动实例化场景的测试由测试脚本指定连接目标。
	if get_tree().current_scene == self:
		_on_connect()

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
	var header := HBoxContainer.new()
	vertical.add_child(header)
	var headline := _new_label("TURN · LAST SPIN", 26)
	headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(headline)
	disconnect_button = _new_button("退出服务器", game.disconnect_server)
	header.add_child(disconnect_button)
	leave_button = _new_button("离开房间", game.leave_room)
	header.add_child(leave_button)
	message_label = _new_label("", 13)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vertical.add_child(message_label)
	connect_button = _new_button("重试连接", _on_connect)
	connect_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vertical.add_child(connect_button)
	room_row = HBoxContainer.new()
	room_row.add_theme_constant_override("separation", 8)
	vertical.add_child(room_row)
	room_row.add_child(_new_button("创建房间", game.create_room))
	room_code_input = LineEdit.new()
	room_code_input.placeholder_text = "房间码"
	room_code_input.custom_minimum_size = Vector2(120.0, 0.0)
	room_code_input.max_length = 6
	room_code_input.text_submitted.connect(func(_code: String): _on_join())
	room_row.add_child(room_code_input)
	room_row.add_child(_new_button("加入房间", _on_join))
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
	member_admin = HBoxContainer.new()
	lobby_box.add_child(member_admin)
	member_choice = OptionButton.new()
	member_admin.add_child(member_choice)
	member_admin.add_child(_new_button("转交房主", func(): _manage_member("transfer_owner")))
	member_admin.add_child(_new_button("移出房间", func(): _manage_member("remove_member")))
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
	reveal_label = _new_label("", 13)
	reveal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(reveal_label)
	action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 7)
	vertical.add_child(action_row)
	hand_choice = OptionButton.new()
	hand_choice.custom_minimum_size = Vector2(145.0, 0.0)
	action_row.add_child(hand_choice)
	action_buttons = [
		hand_choice,
		_new_button("加 +", func(): _draft_play(1)),
		_new_button("减 -", func(): _draft_play(-1)),
		_new_button("不出牌 PASS", _draft_pass),
	]
	for button in action_buttons.slice(1):
		action_row.add_child(button)
	draft_label = _new_label("当前选择：PASS", 14)
	draft_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(draft_label)
	confirm_button = _new_button("确认并锁定", _on_confirm)
	action_row.add_child(confirm_button)
	action_buttons.append(confirm_button)
	return_button = _new_button("结束后返回房间", _on_return)
	vertical.add_child(return_button)

func _on_connect() -> void:
	game.connect_server(_server_address, _server_port)

func _on_join() -> void:
	game.join_room(room_code_input.text)

func _on_ready() -> void:
	game.set_ready(not game.is_ready())

func _manage_member(command: String) -> void:
	var target := member_choice.get_selected_id()
	if target > 0:
		game.manage_member(command, target)

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
	connect_button.visible = game.phase == "offline"
	disconnect_button.visible = game.phase != "offline"
	disconnect_button.text = "取消重连" if game.phase == "reconnecting" else "退出服务器"
	leave_button.visible = not game.room_code.is_empty() and game.phase != "reconnecting"
	room_row.visible = game.phase == "connected"
	message_label.text = game.status
	lobby_box.visible = game.phase == "lobby"
	game_box.visible = game.phase in ["choosing", "result", "ended", "aborted"]
	action_row.visible = game.phase == "choosing" and game.public.get("alive", []).has(game.local_id())
	for button in action_buttons:
		button.disabled = not game.can_act()
	if game.phase == "lobby":
		var lines: Array[String] = ["房间码  %s   ·   人数 %d / %d" % [
			game.room_code, game.members.size(), Rules.MAX_PLAYERS
		]]
		var previous_target := member_choice.get_selected_id()
		member_choice.clear()
		for member in game.members:
			lines.append("%s%s%s    %s%s" % [
				str(member["name"]), "（你）" if int(member["id"]) == game.local_id() else "",
				"（房主）" if int(member["id"]) == game.owner_id else "",
				"已准备" if bool(member["ready"]) else "未准备",
				"" if bool(member["online"]) else " (离线)"
			])
			if member["id"] != game.local_id():
				var target_id: int = member["id"]
				var name: String = member["name"]
				member_choice.add_item(name, target_id)
		if previous_target > 0:
			var index := member_choice.get_item_index(previous_target)
			if index >= 0:
				member_choice.select(index)
		member_admin.visible = game.is_room_owner() and member_choice.item_count > 0
		roster_label.text = "\n".join(lines)
		lives_spin.set_value_no_signal(float(game.initial_lives))
		lives_spin.editable = game.is_room_owner()
		ready_button.text = "取消准备" if game.is_ready() else "准备"
		start_button.disabled = not game.is_room_owner() or not game.all_ready()
	return_button.visible = game.is_room_owner() and game.phase in ["ended", "aborted"]
	if game_box.visible:
		_update_match_ui()

func _update_match_ui() -> void:
	var state: Dictionary = game.public
	wheel.present(game.last_result.get("wheel", state), game.members, game.local_id())
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
	var revealed: Array[String] = []
	for action in game.last_result.get("actions", []):
		var choice := "%+d" % (action["sign"] * action["value"]) if action["type"] == "play" else "PASS"
		revealed.append("%s %s" % [game.name_for(action["peer_id"]), choice])
	reveal_label.text = "本轮揭晓  " + "  ·  ".join(revealed) if not revealed.is_empty() else ""
	reveal_label.visible = not revealed.is_empty()
	_rebuild_hand_list()

func _rebuild_hand_list() -> void:
	var hand: Array = game.public.get("hands", {}).get(game.local_id(), [])
	var parts: Array[String] = []
	for card in hand:
		parts.append(str(card["id"]))
	var signature := "%d:%d:%d:%s" % [game.match_id, game.public.get("round", 0), game.local_id(), ",".join(parts)]
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
			game.seconds_left(), game.confirmed_count
		]
