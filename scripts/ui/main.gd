extends Control
const Rules = preload("res://scripts/core/game_rules.gd")
const NetBridge = preload("res://scripts/network/net_bridge.gd")
## 启动菜单、联机大厅和所有玩家共用的对局界面。
@export_group("本地测试")
@export var local_test: bool = false
@export_range(2, 12) var local_player_count: int = 4
@export_range(1, 5) var local_initial_lives: int = 1

@export var local_game_mode: Rules.Mode = Rules.Mode.CLASSIC

@onready var game = $Session
@onready var mode_menu: CenterContainer = $ModeMenu
@onready var game_margin: MarginContainer = $Margin
@onready var menu_button: Button = %MenuButton
@onready var message_label: Label = %Message
@onready var address_input: LineEdit = %AddressInput
@onready var port_input: LineEdit = %PortInput
@onready var connection_row: HBoxContainer = %ConnectionRow
@onready var lobby_box: VBoxContainer = %LobbyBox
@onready var roster_label: Label = %Roster
@onready var ready_button: Button = %ReadyButton
@onready var start_button: Button = %StartButton
@onready var mode_picker: OptionButton = %GameMode
@onready var lives_spin: SpinBox = %LivesSpin
@onready var match_view = $MatchView
@onready var host_button: Button = $Margin/Layout/ConnectionRow/HostButton
@onready var join_button: Button = $Margin/Layout/ConnectionRow/JoinButton
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var member_admin: HBoxContainer = %MemberAdmin
@onready var member_choice: OptionButton = %MemberChoice

var mode_selected: bool = false
var auto_smoke: bool = false
var auto_ready_sent: bool = false
var auto_start_sent: bool = false
var auto_finished: bool = false
var auto_expected_players: int = 2
var auto_initial_lives: int = 1
var auto_silent: bool = false

func _ready() -> void:
	address_input.text = str(ProjectSettings.get_setting("turn/network/server_address", "127.0.0.1"))
	mode_picker.add_item("经典模式", Rules.Mode.CLASSIC)
	mode_picker.add_item("贪婪模式", Rules.Mode.GREED)
	mode_picker.item_selected.connect(func(index: int): game.set_game_mode(mode_picker.get_item_id(index)))
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
	mode_menu.get_node("Options").visible = not show_modes
	mode_menu.get_node("LocalModes").visible = show_modes
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
	get_tree().reload_current_scene()

func _on_host() -> void:
	if game.phase == "offline":
		game.connect_server(address_input.text.strip_edges(), _port())
	elif game.phase == "connected":
		game.create_room()

func _on_join() -> void:
	if game.phase == "connected":
		game.join_room(room_code_input.text.strip_edges())

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
	connection_row.visible = game.phase in ["offline", "connected", "connecting"]
	address_input.visible = disconnected
	port_input.visible = disconnected
	$Margin/Layout/ConnectionRow/AddressLabel.visible = disconnected
	$Margin/Layout/ConnectionRow/PortLabel.visible = disconnected
	host_button.text = "连接专服" if disconnected else "创建房间"
	host_button.disabled = game.phase == "connecting"
	join_button.visible = game.phase == "connected"
	room_code_input.visible = game.phase == "connected"
	menu_button.visible = not auto_smoke and game.phase in ["offline", "connected"]
	message_label.text = "角色: %s   |   本地 ID: %d   |   %s" % [game.role, game.local_id(), game.status]
	lobby_box.visible = game.phase == "lobby"
	if game.phase == "lobby":
		var lines: Array[String] = ["房间码：%s  |  最多 12 人" % game.room_code]
		for member in game.members:
			lines.append("%s%s    %s%s" % [
				str(member["name"]), " (YOU)" if int(member["id"]) == game.local_id() else "",
				"已准备" if bool(member["ready"]) else "未准备",
				"" if bool(member["online"]) else " (离线)"
			])
		roster_label.text = "\n".join(lines)
		var selected_member := member_choice.get_selected_id()
		member_choice.clear()
		for member in game.members:
			var id: int = int(member["id"])
			if id != game.local_id() and member["online"]:
				member_choice.add_item(str(member["name"]), id)
		if selected_member > 0 and member_choice.get_item_index(selected_member) >= 0:
			member_choice.select(member_choice.get_item_index(selected_member))
		member_admin.visible = game.am_host() and member_choice.item_count > 0
		mode_picker.select(mode_picker.get_item_index(game.game_mode))
		mode_picker.disabled = not game.am_host()
		lives_spin.get_parent().visible = game.game_mode == Rules.Mode.CLASSIC
		lives_spin.set_value_no_signal(float(game.initial_lives))
		lives_spin.editable = game.am_host()
		ready_button.text = "取消准备" if game.is_ready() else "准备"
		start_button.disabled = not game.am_host() or not game.all_ready()
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
	# 自动化结束由 _refresh 的事件驱动完成，避免 Host 断开时丢失终局状态。
