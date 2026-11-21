extends Node
## 客户端只保存服务端公开给自己的房间与对局状态。
signal changed

const NetBridge = preload("res://scripts/network/net_bridge.gd")
const Rules = preload("res://scripts/core/game_rules.gd")
const Commit = preload("res://scripts/network/action_commit.gd")
const MatchSession = preload("res://scripts/server/match_session.gd")
const EconomySettings = preload("res://scripts/core/economy_settings.gd")
const INTRO_SECONDS := MatchSession.INTRO_SECONDS
@export var economy_settings: EconomySettings = EconomySettings.new()
const CONNECT_TIMEOUT := 8.0
const RETRY_SECONDS := 1.0
const RESUME_WINDOW_MS := 60000

@onready var _net = $"../Net"
var role := "none" # none / client / local
var phase := "offline"
var status := "等待连接专服。"
var room_code := ""
var owner_id := 0
var members: Array = []
var initial_lives := 1
var game_mode: Rules.Mode = Rules.Mode.CLASSIC
var balance := 0
var special_cards: Dictionary = {}
var card_prices: Dictionary = {}
var economy_notice := ""
var super_steps := 1
var settlement_delta := 0
var settlement_submitted := false
var sealed_action: Dictionary = {}
var sealed_hash := ""
var sealed_nonce := ""
var commit_count := 0
var _local_match: MatchSession
var _local_serial := 0
var public: Dictionary = {}
var last_result: Dictionary = {}
var match_id := 0
var confirmed_count := 0
var _player_id := 0
var _resume_token := ""
var _address := ""
var _port := NetBridge.DEFAULT_PORT
var _trusted_ca: X509Certificate
var _resume_deadline_ms := 0
var _submitting := false
var _locked := false
var _deadline_ms := 0
var _connection_timer := Timer.new()
var _retry_timer := Timer.new()

func _ready() -> void:
	_net.connected_to_server.connect(_on_connected)
	_net.connection_error.connect(_on_connection_error)
	_net.server_lost.connect(_on_server_lost)
	_net.client_event.connect(_on_client_event)
	add_child(_connection_timer)
	add_child(_retry_timer)
	_connection_timer.one_shot = true
	_retry_timer.one_shot = true
	_connection_timer.timeout.connect(func(): _on_connection_error("连接超时，请确认地址、端口或版本。"))
	_retry_timer.timeout.connect(_retry_connection)

func local_id() -> int:
	return 1 if role == "local" else _player_id

func am_host() -> bool:
	return is_room_owner()

func start_local_test(player_count: int, lives: int, mode: Rules.Mode = Rules.Mode.CLASSIC) -> void:
	if role == "client":
		return
	if _local_match != null:
		_local_match.queue_free()
		_local_match = null
	role = "local"
	phase = "offline"
	_clear_room()
	game_mode = mode
	initial_lives = clampi(lives, 1, Rules.MAX_INITIAL_LIVES)
	members = [{"id": 1, "name": "本地玩家", "ready": true, "online": true}]
	var ids: Array = [1]
	for id in range(2, clampi(player_count, 2, Rules.MAX_PLAYERS) + 1):
		ids.append(id)
		members.append({"id": id, "name": String.chr(95 + id), "ready": true, "online": true})
	owner_id = 1
	_local_match = MatchSession.new()
	add_child(_local_match)
	_local_match.room_update.connect(_on_client_event)
	_local_match.player_update.connect(func(id: int, kind: String, payload: Dictionary):
		if id == 1:
			_on_client_event(kind, payload))
	_local_serial += 1
	_local_match.start(_local_serial, ids, initial_lives, mode, economy_settings.values(), 1)

func is_room_owner() -> bool:
	return owner_id != 0 and owner_id == local_id()

func can_act() -> bool:
	return phase == "choosing" and not _submitting and not _locked and public.get("alive", []).has(local_id())

func is_ready() -> bool:
	for member in members:
		if member["id"] == local_id():
			return member["ready"]
	return false

func all_ready() -> bool:
	if members.size() < 2:
		return false
	for member in members:
		if not member["ready"] or not member["online"]:
			return false
	return true

func seconds_left() -> int:
	if phase not in ["choosing", "settlement"]:
		return 0
	return maxi(0, ceili(float(_deadline_ms - Time.get_ticks_msec()) / 1000.0))

func can_buy_cards() -> bool:
	return phase in ["choosing", "settlement", "result"] and public.get("alive", []).has(local_id())

func special_card_count(kind: String) -> int:
	var owned: int = int(special_cards.get(kind, 0))
	if sealed_action.get("type") == kind and phase in ["choosing", "settlement"]:
		return maxi(0, owned - 1)
	return owned

func can_settle() -> bool:
	return phase == "settlement" and not settlement_submitted and public.get("alive", []).has(local_id())

func buy_special_card(kind: String) -> void:
	var price: int = int(card_prices.get(kind, -1))
	if not can_buy_cards() or price < 0 or price > balance:
		return
	var payload := {"match_id": match_id, "kind": kind}
	if role == "local":
		_local_match.purchase(1, payload)
	else:
		_net.send_command("buy_card", payload.merged({"code": room_code}))

func submit_settlement(use_super: bool) -> void:
	if not can_settle() or (use_super and special_card_count("super") < 1):
		return
	settlement_submitted = true
	changed.emit()
	var payload := {"match_id": match_id, "round": public["round"], "use_super": use_super}
	if role == "local":
		_local_match.submit_local_settlement(1, use_super)
	else:
		_net.send_command("settlement_choice", payload.merged({"code": room_code}))

func set_game_mode(mode: Rules.Mode) -> void:
	if phase == "lobby" and is_room_owner() and mode in Rules.Mode.values():
		_net.send_command("game_mode", {"code": room_code, "mode": mode})

func connect_server(address: String, port: int, trusted_ca: X509Certificate = null) -> void:
	if phase != "offline":
		return
	if address.is_empty() or port < 1 or port > 65535:
		_set_status("请输入有效的服务器地址和端口。")
		return
	role = "client"
	_address = address
	_port = port
	_trusted_ca = trusted_ca
	phase = "connecting"
	_set_status("正在连接专服…")
	_start_connection()

func disconnect_server() -> void:
	_reset_connection("已退出服务器.")

func create_room() -> void:
	if phase == "connected":
		_net.send_command("create_room", {})

func join_room(code: String) -> void:
	if phase == "connected":
		_net.send_command("join_room", {"code": code.strip_edges().to_upper()})

func leave_room() -> void:
	if not room_code.is_empty() and phase not in ["connecting", "reconnecting"]:
		_net.send_command("leave", {"code": room_code})

func manage_member(command: String, target_id: int) -> void:
	if phase == "lobby" and is_room_owner():
		_net.send_command(command, {"code": room_code, "target_id": target_id})

func set_initial_lives(amount: int) -> void:
	if phase == "lobby" and is_room_owner():
		_net.send_command("initial_lives", {"code": room_code, "lives": amount})

func set_ready(ready: bool) -> void:
	if phase == "lobby":
		_net.send_command("ready", {"code": room_code, "ready": ready})

func request_start() -> void:
	if phase == "lobby" and is_room_owner():
		_net.send_command("start", {"code": room_code})

func request_return_lobby() -> void:
	if phase in ["ended", "aborted"] and is_room_owner():
		_net.send_command("return_lobby", {"code": room_code})

func submit_action(action: Dictionary) -> void:
	if not can_act():
		return
	if not Rules.valid_action(public, local_id(), action, special_cards):
		_set_status("请选择合法的手牌或特殊牌。")
		return
	sealed_action = action.duplicate(true)
	_submitting = true
	if role == "local":
		_locked = true
		_local_match.submit_local_action(1, action)
	else:
		sealed_nonce = Commit.create_nonce()
		sealed_hash = Commit.compute(match_id, int(public["round"]), local_id(), action, sealed_nonce)
		_net.send_command("commit", {"code": room_code, "match_id": match_id,
			"round": public["round"], "hash": sealed_hash,
			"action": sealed_action.duplicate(true), "nonce": sealed_nonce})
	_set_status("行动提交中，等待专服确认。")

func _start_connection() -> void:
	_connection_timer.start(CONNECT_TIMEOUT)
	_net.connect_to_server(_address, _port, _trusted_ca)

func _on_connected() -> void:
	_net.send_command("hello", {"version": NetBridge.PROTOCOL_VERSION, "resume_token": _resume_token})

func _on_server_lost() -> void:
	if phase == "reconnecting":
		_on_connection_error("等待重新连接…")
	elif not room_code.is_empty() and not _resume_token.is_empty():
		phase = "reconnecting"
		_resume_deadline_ms = Time.get_ticks_msec() + RESUME_WINDOW_MS
		_on_connection_error("连接中断，正在恢复席位…")
	else:
		_reset_connection("服务器已断开，可以重新连接。")

func _on_connection_error(message: String) -> void:
	_connection_timer.stop()
	_net.close_connection()
	if phase == "reconnecting":
		_retry_timer.start(RETRY_SECONDS)
		_set_status(message)
	else:
		_reset_connection(message)

func _retry_connection() -> void:
	if Time.get_ticks_msec() >= _resume_deadline_ms:
		_reset_connection("重连窗口已结束，可以重新连接服务器。")
		return
	_start_connection()

func _reset_connection(message: String) -> void:
	_connection_timer.stop()
	_retry_timer.stop()
	_net.close_connection()
	phase = "offline"
	role = "none"
	_player_id = 0
	_resume_token = ""
	_clear_room()
	_set_status(message)

func _clear_room() -> void:
	room_code = ""
	owner_id = 0
	members = []
	_clear_match()

func _clear_match() -> void:
	match_id = 0
	public = {}
	last_result = {}
	confirmed_count = 0
	commit_count = 0
	_submitting = false
	_locked = false
	sealed_hash = ""
	sealed_nonce = ""
	sealed_action.clear()
	balance = 0
	special_cards.clear()
	card_prices.clear()
	economy_notice = ""
	settlement_delta = 0
	settlement_submitted = false

func _on_client_event(kind: String, payload: Dictionary) -> void:
	if phase in ["connecting", "reconnecting"]:
		match kind:
			"server_ready":
				var resuming: bool = phase == "reconnecting"
				_connection_timer.stop()
				_retry_timer.stop()
				_player_id = payload["player_id"]
				_resume_token = payload.get("resume_token", _resume_token)
				phase = "connected"
				if not resuming:
					_clear_room()
				_set_status("席位已恢复，正在同步对局。" if resuming else "专服已连接。可以创建房间或输入房间码。")
			"resume_busy":
				_on_connection_error("等待旧连接释放席位…")
			"resume_rejected":
				_reset_connection("会话已失效，可以重新连接服务器。")
			"incompatible":
				_reset_connection("客户端与服务器版本不匹配。")
		return
	match kind:
		"lobby":
			phase = "lobby"
			_clear_match()
			_read_roster(payload)
			_set_status("等待房间成员准备。")
		"members":
			_read_roster(payload)
			changed.emit()
		"room_left":
			phase = "connected"
			_clear_room()
			_set_status(payload.get("message", "已离开房间"))
		"match_started":
			match_id = int(payload["match_id"])
			last_result.clear()
			game_mode = payload.get("mode", Rules.Mode.CLASSIC)
			card_prices = payload.get("card_prices", {}).duplicate()
			super_steps = int(payload.get("super_steps", 1))
			balance = 0
			special_cards.clear()
			economy_notice = ""
			_set_status("游戏开始，等待发牌...")
		"wallet":
			if payload.get("match_id") != match_id:
				return
			var next_balance: int = int(payload.get("balance", 0))
			special_cards = payload.get("cards", {}).duplicate()
			economy_notice = str(payload.get("notice", ""))
			if phase in ["result", "ended"] and next_balance > balance and economy_notice.is_empty():
				economy_notice = "本轮获币 +%dr" % (next_balance - balance)
			balance = next_balance
			changed.emit()
		"hidden_cards":
			if payload.get("match_id") != match_id or payload.get("round") != public.get("round"):
				return
			public["hidden_card_counts"] = payload.get("counts", {}).duplicate()
			public["balances"] = payload.get("balances", {}).duplicate()
			changed.emit()
		"round_intro":
			if payload.get("match_id") != match_id:
				return
			phase = "round_intro"
			public = payload.get("public", {}).duplicate(true)
			_set_status("准备发牌")
		"round_started":
			match_id = int(payload["match_id"])
			public = payload["public"].duplicate(true)
			game_mode = public.get("mode", game_mode)
			initial_lives = int(public.get("initial_lives", initial_lives))
			phase = "choosing"
			commit_count = 0
			_submitting = false
			_locked = false
			sealed_hash = ""
			sealed_nonce = ""
			sealed_action.clear()
			_deadline_ms = Time.get_ticks_msec() + int(float(payload["duration"]) * 1000.0)
			changed.emit()
		"commit_ack":
			_submitting = false
			_locked = true
			_set_status("服务端已锁定本轮行动。")
		"commit_count", "confirmed_count":
			commit_count = int(payload.get("count", 0))
			confirmed_count = commit_count
			changed.emit()
		"settlement_started":
			phase = "settlement"
			settlement_delta = int(payload.get("delta", 0))
			settlement_submitted = false
			_deadline_ms = Time.get_ticks_msec() + int(float(payload.get("duration", 5.0)) * 1000.0)
			_set_status("结算阶段，可使用超级卡。")
		"settlement_rejected":
			settlement_submitted = false
			_set_status("超级卡确认失败，请重新选择。")
		"match_snapshot":
			_apply_snapshot(payload)
		"action_rejected":
			if payload.get("match_id") == match_id and payload.get("round") == public.get("round"):
				_submitting = false
				if not _locked:
					sealed_hash = ""
					sealed_nonce = ""
					sealed_action.clear()
				_set_status(str(payload.get("message", "操作被拒绝")))
		"round_result":
			last_result = payload.duplicate(true)
			public = payload.get("public", {}).duplicate(true)
			game_mode = public.get("mode", game_mode)
			phase = "ended" if int(payload.get("winner", 0)) != 0 else "result"
			_show_round_result()
		"aborted":
			phase = "aborted"
			_set_status(str(payload.get("message", "对局已中止")))
		"error":
			_set_status(str(payload.get("message", "网络错误")))

func _apply_snapshot(payload: Dictionary) -> void:
	var same_round: bool = match_id == payload["match_id"] and public.get("round") == payload["public"].get("round")
	match_id = payload["match_id"]
	phase = payload["phase"]
	public = payload["public"].duplicate(true)
	game_mode = payload.get("mode", game_mode)
	card_prices = payload.get("card_prices", {}).duplicate()
	super_steps = int(payload.get("super_steps", super_steps))
	var wallet: Dictionary = payload.get("wallet", {})
	balance = int(wallet.get("balance", 0))
	special_cards = wallet.get("cards", {}).duplicate()
	last_result = payload.get("last_result", {}).duplicate(true)
	commit_count = int(payload.get("confirmed_count", 0))
	confirmed_count = commit_count
	_locked = bool(payload.get("locked", false))
	_submitting = false
	settlement_delta = int(payload.get("settlement_delta", 0))
	settlement_submitted = bool(payload.get("settlement_submitted", false))
	_deadline_ms = Time.get_ticks_msec() + int(payload.get("remaining_ms", 0))
	if not same_round:
		sealed_action.clear()
		sealed_hash = ""
		sealed_nonce = ""
	if not last_result.is_empty() and phase in ["result", "ended"]:
		_show_round_result()
	else:
		_set_status("对局状态已恢复。")

func _show_round_result() -> void:
	if last_result.has("hit_peer"):
		var hit: String = name_for(int(last_result["hit_peer"]))
		if game_mode == Rules.Mode.GREED:
			_set_status("%s %s" % [hit, "保住金币" if last_result.get("defended", false) else "被命中，金币清零"])
		elif last_result.get("defended", false):
			_set_status("%s 使用防御卡保护了最后一点生命。" % hit)
		elif int(last_result.get("eliminated", 0)) != 0:
			_set_status("%s 生命归零，已淘汰。" % hit)
		else:
			_set_status("%s 剩余生命 %d。" % [hit, last_result.get("remaining_lives", 0)])
	else:
		_set_status("本局已结束。")

func _read_roster(payload: Dictionary) -> void:
	room_code = payload["code"]
	owner_id = payload["owner_id"]
	members = payload["members"]
	initial_lives = payload["initial_lives"]
	game_mode = payload.get("mode", game_mode)

func name_for(player_id: int) -> String:
	for member in members:
		if member["id"] == player_id:
			return member["name"]
	return str(player_id)

func _set_status(message: String) -> void:
	status = message
	changed.emit()
