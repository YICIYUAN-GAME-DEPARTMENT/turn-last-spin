extends Control
const Rules = preload("res://scripts/core/game_rules.gd")
const NetBridge = preload("res://scripts/network/net_bridge.gd")
const MemberRowScript = preload("res://scripts/ui/lobby_member_row.gd")
## 启动菜单、联机大厅和所有玩家共用的对局界面。

@export_group("本地测试")
@export var local_test: bool = false
@export_range(2, 12) var local_player_count: int = 4
@export_range(1, 5) var local_initial_lives: int = 1
@export var local_game_mode: Rules.Mode = Rules.Mode.CLASSIC

@onready var game = $Session
@onready var mode_menu: Control = $ModeMenu
@onready var game_margin: MarginContainer = $Margin
@onready var stage_badge: Label = %StageBadge
@onready var peer_meta: Label = %PeerMeta
@onready var menu_button: Button = %MenuButton
@onready var message_label: Label = %Message
@onready var connect_stage: Control = %ConnectStage
@onready var dispatch_stage: Control = %DispatchStage
@onready var hotline_art = %HotlineArt
@onready var address_input: LineEdit = %AddressInput
@onready var port_input: LineEdit = %PortInput
@onready var connection_row: HBoxContainer = %ConnectionRow
@onready var host_button: Button = %HostButton
@onready var create_room_button: Button = %CreateRoomButton
@onready var join_button: Button = %JoinButton
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var lobby_box: Control = %LobbyBox
@onready var room_code_display: Label = %RoomCodeDisplay
@onready var copy_code_button: Button = %CopyCodeButton
@onready var seat_counter: Label = %SeatCounter
@onready var roster_label: Label = %Roster
@onready var member_list: VBoxContainer = %MemberList
@onready var ready_button: Button = %ReadyButton
@onready var start_button: Button = %StartButton
@onready var start_hint: Label = %StartHint
@onready var mode_picker: OptionButton = %GameMode
@onready var mode_summary: Label = %ModeSummary
@onready var lives_row: HBoxContainer = %LivesRow
@onready var lives_spin: SpinBox = %LivesSpin
@onready var admin_divider: Control = %AdminDivider
@onready var member_admin: Control = %MemberAdmin
@onready var member_choice: OptionButton = %MemberChoice
@onready var match_view = $MatchView

var mode_selected: bool = false
var auto_smoke: bool = false
var auto_ready_sent: bool = false
var auto_start_sent: bool = false
var auto_finished: bool = false
var auto_expected_players: int = 2
var auto_initial_lives: int = 1
var auto_silent: bool = false
var _copy_reset_timer: Timer

func _ready() -> void:
	address_input.text = str(ProjectSettings.get_setting("turn/network/server_address", "127.0.0.1"))
	lives_spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_picker.add_item("经典模式  ·  CLASSIC", Rules.Mode.CLASSIC)
	mode_picker.add_item("贪婪模式  ·  GREED", Rules.Mode.GREED)
	mode_picker.item_selected.connect(func(index: int): game.set_game_mode(mode_picker.get_item_id(index)))
	room_code_input.text_changed.connect(_on_room_code_edited)
	_copy_reset_timer = Timer.new()
	_copy_reset_timer.one_shot = true
	_copy_reset_timer.timeout.connect(func(): copy_code_button.text = "复制暗码")
	add_child(_copy_reset_timer)

	match_view.game = game
	match_view.allow_menu = not local_test
	match_view.menu_requested.connect(_on_menu)
	match_view.restart_requested.connect(_on_return)
	match_view.player_count_changed.connect(_on_local_player_count_changed)
	match_view.initial_lives_changed.connect(_on_local_initial_lives_changed)
	game.changed.connect(_refresh)

	mode_menu.get_node("%OnlineGame").pressed.connect(_on_online_game)
	mode_menu.get_node("%LocalGame").pressed.connect(_show_local_modes.bind(true))
	mode_menu.get_node("%Back").pressed.connect(_show_local_modes.bind(false))
	mode_menu.get_node("%ClassicMode").pressed.connect(_start_local_mode.bind(Rules.Mode.CLASSIC))
	mode_menu.get_node("%GreedMode").pressed.connect(_start_local_mode.bind(Rules.Mode.GREED))
	var quit_btn: Button = mode_menu.get_node_or_null("%QuitGame")
	if quit_btn != null:
		quit_btn.pressed.connect(func(): get_tree().quit())

	if local_test:
		_start_local_mode(local_game_mode)
		return

	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--turn-smoke-players="):
			auto_expected_players = clampi(int(arg.get_slice("=", 1)), 2, 12)
		if arg.begins_with("--turn-smoke-lives="):
			auto_initial_lives = clampi(int(arg.get_slice("=", 1)), 1, 5)
	auto_silent = args.has("--turn-smoke-silent")
	var smoke_host: bool = args.has("--turn-smoke-host")
	var smoke_join: bool = args.has("--turn-smoke-join")
	auto_smoke = smoke_host or smoke_join
	mode_selected = auto_smoke
	_refresh()
	if auto_smoke:
		game.connect_server("127.0.0.1", 24680)

func _on_online_game() -> void:
	mode_selected = true
	_refresh()
	address_input.grab_focus()

func _show_local_modes(show_modes: bool) -> void:
	mode_menu.get_node("Spread/LeftColumn/Options").visible = not show_modes
	mode_menu.get_node("Spread/LeftColumn/LocalModes").visible = show_modes
	mode_menu.get_node("%ClassicMode" if show_modes else "%LocalGame").grab_focus()

func _start_local_mode(mode: Rules.Mode) -> void:
	local_game_mode = mode
	mode_selected = true
	game.start_local_test(local_player_count, local_initial_lives, local_game_mode)

func _on_local_player_count_changed(count: int) -> void:
	local_player_count = count
	_on_return()

func _on_local_initial_lives_changed(lives: int) -> void:
	local_initial_lives = lives
	_on_return()

func _on_menu() -> void:
	if game.role == "client" and game.phase != "offline":
		game.disconnect_server()
	get_tree().reload_current_scene()

func _on_connect_submitted(_text: String) -> void:
	_on_host()

func _on_host() -> void:
	if game.phase == "offline":
		game.connect_server(address_input.text.strip_edges(), _port())
	elif game.phase == "connected":
		game.create_room()

func _on_create_room() -> void:
	if game.phase == "connected":
		game.create_room()

func _on_join_submitted(_text: String) -> void:
	_on_join()

func _on_join() -> void:
	if game.phase == "connected":
		var code := room_code_input.text.strip_edges().to_upper()
		if code.is_empty():
			message_label.text = "请先输入 6 位房间暗码。"
			room_code_input.grab_focus()
			return
		game.join_room(code)

func _on_disconnect() -> void:
	game.disconnect_server()

func _on_room_code_edited(new_text: String) -> void:
	var upper := new_text.to_upper()
	if upper != new_text:
		var col := room_code_input.caret_column
		room_code_input.text = upper
		room_code_input.caret_column = mini(col, upper.length())

func _on_copy_room_code() -> void:
	if game.room_code.is_empty():
		return
	DisplayServer.clipboard_set(game.room_code)
	copy_code_button.text = "已复制 ✓"
	_copy_reset_timer.start(1.6)

func _port() -> int:
	return clampi(int(port_input.text), 1, 65535)

func _on_lives_changed(value: float) -> void:
	game.set_initial_lives(int(value))

func _on_transfer_owner() -> void:
	var target := member_choice.get_selected_id()
	if target > 0:
		game.manage_member("transfer_owner", target)

func _on_remove_member() -> void:
	var target := member_choice.get_selected_id()
	if target > 0:
		game.manage_member("remove_member", target)

func _on_leave_room() -> void:
	game.leave_room()

func _on_ready() -> void:
	game.set_ready(not game.is_ready())

func _on_start() -> void:
	game.request_start()

func _on_return() -> void:
	if game.role == "local":
		game.start_local_test(local_player_count, local_initial_lives, local_game_mode)
	else:
		game.request_return_lobby()

func _refresh() -> void:
	var disconnected: bool = game.role == "none" and game.phase == "offline"
	var in_match: bool = game.phase in ["round_intro", "choosing", "settlement", "result", "ended", "aborted"]
	mode_menu.visible = not mode_selected and disconnected
	game_margin.visible = not (mode_menu.visible or in_match)

	# 顶部阶段标识与连接信息
	match game.phase:
		"offline":
			stage_badge.text = "♦  专服接线台"
			peer_meta.text = "离线"
		"connecting":
			stage_badge.text = "♦  正在接线"
			peer_meta.text = "CONNECTING..."
		"reconnecting":
			stage_badge.text = "♦  席位恢复中"
			peer_meta.text = "RECONNECTING..."
		"connected":
			stage_badge.text = "♦  席位调度"
			peer_meta.text = "已接入专服  ·  ID #%d" % game.local_id()
		"lobby":
			stage_badge.text = "♦  圆桌大厅"
			peer_meta.text = "代表 ID #%d" % game.local_id()
		_:
			stage_badge.text = "♦  会议进行中"
			peer_meta.text = "ID #%d" % game.local_id()

	menu_button.visible = not auto_smoke and game.phase in ["offline", "connected", "reconnecting"]
	message_label.text = game.status

	# 三个联机前/大厅子视图互斥切换
	var show_connect: bool = game.phase in ["offline", "connecting", "reconnecting"]
	connect_stage.visible = show_connect
	dispatch_stage.visible = game.phase == "connected"
	lobby_box.visible = game.phase == "lobby"

	if show_connect:
		var busy: bool = game.phase in ["connecting", "reconnecting"]
		hotline_art.active_pulse = busy
		address_input.editable = not busy
		port_input.editable = not busy
		host_button.disabled = busy
		if game.phase == "connecting":
			host_button.text = "正在接线，请稍候…"
		elif game.phase == "reconnecting":
			host_button.text = "正在尝试恢复席位…"
		else:
			host_button.text = "♦   连接专服"

	if game.phase == "lobby":
		_refresh_lobby()

	if match_view.visible and not in_match:
		match_view.reset()
	match_view.visible = in_match
	if in_match:
		match_view.present()

	if auto_smoke and not auto_finished and game.phase in ["ended", "aborted"]:
		auto_finished = true
		var final_phase: String = game.phase
		print("TURN_SMOKE_FINAL peer=%d phase=%s" % [game.local_id(), final_phase])
		get_tree().create_timer(0.8).timeout.connect(func(): get_tree().quit(0 if final_phase == "ended" else 5))

func _refresh_lobby() -> void:
	room_code_display.text = game.room_code if not game.room_code.is_empty() else "------"
	seat_counter.text = "%d / %d 席" % [game.members.size(), Rules.MAX_PLAYERS]

	# 重建成员档案行
	for child in member_list.get_children():
		member_list.remove_child(child)
		child.queue_free()

	var lines: Array[String] = ["房间码：%s  |  最多 12 人" % game.room_code]
	for idx in range(game.members.size()):
		var member: Dictionary = game.members[idx]
		var row = MemberRowScript.new()
		member_list.add_child(row)
		row.setup(idx + 1, member, game.local_id(), game.owner_id)
		lines.append("%s%s    %s%s" % [
			str(member["name"]), " (YOU)" if int(member["id"]) == game.local_id() else "",
			"已准备" if bool(member["ready"]) else "未准备",
			"" if bool(member["online"]) else " (离线)"
		])
	roster_label.text = "\n".join(lines)

	# 房主管理成员下拉
	var selected_member := member_choice.get_selected_id()
	member_choice.clear()
	for member in game.members:
		var id: int = int(member["id"])
		if id != game.local_id() and bool(member.get("online", true)):
			member_choice.add_item(str(member["name"]), id)
	if selected_member > 0 and member_choice.get_item_index(selected_member) >= 0:
		member_choice.select(member_choice.get_item_index(selected_member))
	var show_admin: bool = game.am_host() and member_choice.item_count > 0
	member_admin.visible = show_admin
	admin_divider.visible = show_admin

	# 模式与初始生命设置
	mode_picker.select(mode_picker.get_item_index(game.game_mode))
	mode_picker.disabled = not game.am_host()
	if game.game_mode == Rules.Mode.GREED:
		mode_summary.text = "贪婪模式：攒满 1000r 筹码体面退场；被指中则筹码清零但保留席位，商店半价。"
	else:
		mode_summary.text = "经典模式：被指针指中扣 1 点生命，归零即淘汰；留到最后者胜。"
	lives_row.visible = game.game_mode == Rules.Mode.CLASSIC
	lives_spin.set_value_no_signal(float(game.initial_lives))
	lives_spin.editable = game.am_host()

	# 准备与开局按钮反馈
	var local_ready: bool = game.is_ready()
	ready_button.text = "取消准备" if local_ready else "♦   盖章准备"
	ready_button.theme_type_variation = &"Button" if local_ready else &"InkButton"

	var can_start: bool = game.am_host() and game.all_ready()
	start_button.disabled = not can_start
	if game.members.size() < 2:
		start_hint.text = "至少需要 2 位代表入席才能开启会议。"
	elif not game.all_ready():
		start_hint.text = "等待所有在线代表盖章就绪。"
	elif game.am_host():
		start_hint.text = "全员已就绪，可以宣布开局。"
	else:
		start_hint.text = "全员已就绪，等待房主宣布开局。"

func _process(_delta: float) -> void:
	if not auto_smoke or auto_finished:
		return
	# 自动化双实例测试；正常玩家不会调用这些逻辑。
	if game.phase == "connected" and not auto_start_sent:
		if OS.get_cmdline_user_args().has("--turn-smoke-host"):
			game.create_room()
		elif OS.get_cmdline_user_args().has("--turn-smoke-join"):
			var target_code: String = ""
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--turn-room="):
					target_code = arg.get_slice("=", 1)
			if not target_code.is_empty():
				game.join_room(target_code)
		auto_start_sent = true
	if game.phase == "lobby":
		if not auto_ready_sent and game.local_id() > 0:
			auto_ready_sent = true
			game.set_ready(true)
		if game.am_host() and game.all_ready() and game.members.size() >= auto_expected_players and not auto_finished:
			game.request_start()
	elif game.phase == "choosing" and game.can_act() and not auto_silent:
		var action: Dictionary = {"type": "pass"}
		if game.am_host() and int(game.public.get("round", 0)) == 1:
			var my_hand: Array = game.public.get("hands", {}).get(game.local_id(), [])
			if not my_hand.is_empty():
				action = {"type": "play", "card_id": int(my_hand[0]["id"]), "sign": 1}
		game.submit_action(action)
	elif game.phase == "settlement" and game.can_settle():
		game.submit_settlement(false)
