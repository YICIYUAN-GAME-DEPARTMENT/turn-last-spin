extends Control
## 启动菜单、联机大厅和所有玩家共用的对局界面。
@export_group("本地测试")
@export var local_test: bool = false
@export_range(2, 12) var local_player_count: int = 4
@export_range(1, 5) var local_initial_lives: int = 1

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
@onready var lives_spin: SpinBox = %LivesSpin
@onready var match_view = $MatchView

var mode_selected: bool = false
var auto_smoke: bool = false
var auto_ready_sent: bool = false
var auto_start_sent: bool = false
var auto_finished: bool = false
var auto_expected_players: int = 2
var auto_initial_lives: int = 1
var auto_silent: bool = false

func _ready() -> void:
	match_view.game = game
	match_view.allow_menu = not local_test
	match_view.menu_requested.connect(_on_menu)
	match_view.restart_requested.connect(_on_return)
	match_view.player_count_changed.connect(_on_local_player_count_changed)
	match_view.initial_lives_changed.connect(_on_local_initial_lives_changed)
	game.changed.connect(_refresh)
	mode_menu.get_node("%OnlineGame").pressed.connect(_on_online_game)
	mode_menu.get_node("%LocalGame").pressed.connect(_on_local_game)
	if local_test:
		_on_local_game()
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
	if smoke_host:
		game.start_host(24680)
		game.set_initial_lives(auto_initial_lives)
	elif smoke_join:
		game.join_host("127.0.0.1", 24680)

func _on_online_game() -> void:
	mode_selected = true
	_refresh()
	address_input.grab_focus()

func _on_local_game() -> void:
	mode_selected = true
	game.start_local_test(local_player_count, local_initial_lives)

func _on_local_player_count_changed(count: int) -> void:
	local_player_count = count
	_on_return()

func _on_local_initial_lives_changed(lives: int) -> void:
	local_initial_lives = lives
	_on_return()

func _on_menu() -> void:
	get_tree().reload_current_scene()

func _on_host() -> void:
	game.start_host(_port())

func _on_join() -> void:
	game.join_host(address_input.text.strip_edges(), _port())

func _port() -> int:
	return clampi(int(port_input.text), 1, 65535)

func _on_lives_changed(value: float) -> void:
	game.set_initial_lives(int(value))

func _on_ready() -> void:
	game.set_ready(not game.is_ready())

func _on_start() -> void:
	game.request_start()

func _on_return() -> void:
	if game.role == "local":
		game.start_local_test(local_player_count, local_initial_lives)
	else:
		game.request_return_lobby()

func _refresh() -> void:
	var disconnected: bool = game.role == "none" and game.phase == "offline"
	var in_match: bool = game.phase in ["choosing", "revealing", "settlement", "result", "ended", "aborted"]
	mode_menu.visible = not mode_selected and disconnected
	game_margin.visible = not (mode_menu.visible or in_match)
	connection_row.visible = disconnected
	menu_button.visible = not auto_smoke and disconnected
	message_label.text = "角色: %s   |   本地 ID: %d   |   %s" % [game.role, game.local_id(), game.status]
	lobby_box.visible = game.phase == "lobby"
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
	elif game.phase == "settlement" and game.can_settle():
		game.submit_settlement(false)
	# 自动化结束由 _refresh 的事件驱动完成，避免 Host 断开时丢失终局状态。
