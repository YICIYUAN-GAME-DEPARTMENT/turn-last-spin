extends Node
## 客户端只保存服务端公开给自己的房间与对局状态。
signal changed

const NetBridge = preload("res://scripts/network/net_bridge.gd")
const Rules = preload("res://scripts/core/game_rules.gd")
const CONNECT_TIMEOUT := 8.0
const RETRY_SECONDS := 1.0
const RESUME_WINDOW_MS := 60000

@onready var _net = $"../Net"
var phase := "offline"
var status := "等待连接专服。"
var room_code := ""
var owner_id := 0
var members: Array = []
var initial_lives := 1
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
	return _player_id

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
	return maxi(0, ceili(float(_deadline_ms - Time.get_ticks_msec()) / 1000.0))

func connect_server(address: String, port: int, trusted_ca: X509Certificate = null) -> void:
	if phase != "offline":
		return
	if address.is_empty() or port < 1 or port > 65535:
		_set_status("请输入有效的服务器地址和端口。")
		return
	_address = address
	_port = port
	_trusted_ca = trusted_ca
	phase = "connecting"
	_set_status("正在连接专服…")
	_start_connection()

func disconnect_server() -> void:
	_reset_connection("已退出服务器。")

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
	if not Rules.valid_action(public, local_id(), action):
		_set_status("请选择自己仍持有的牌。")
		return
	_submitting = true
	_net.send_command("action", {
		"code": room_code, "match_id": match_id, "round": public["round"], "action": action
	})
	_set_status("正在确认行动…")

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
	_submitting = false
	_locked = false

func _on_client_event(kind: String, payload: Dictionary) -> void:
	if phase in ["connecting", "reconnecting"]:
		match kind:
			"server_ready":
				_connection_timer.stop()
				_retry_timer.stop()
				_player_id = payload["player_id"]
				_resume_token = payload.get("resume_token", _resume_token)
				phase = "connected"
				_clear_room()
				_set_status("专服已连接。可以创建房间或输入房间码。")
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
			_set_status(payload["message"])
		"round_started":
			_apply_snapshot({
				"match_id": payload["match_id"], "phase": "choosing", "public": payload["public"],
				"remaining_ms": int(payload["duration"] * 1000.0),
				"confirmed_count": 0, "locked": false, "last_result": {}
			})
		"match_snapshot":
			_apply_snapshot(payload)
		"action_ack", "action_rejected":
			if phase == "choosing" and payload.get("match_id") == match_id and payload.get("round") == public["round"]:
				_submitting = false
				if kind == "action_ack":
					_locked = true
					_set_status("行动已锁定，等待统一揭晓。")
				elif not _locked:
					_set_status(payload["message"])
		"confirmed_count":
			confirmed_count = payload["count"]
			changed.emit()
		"round_result":
			last_result = payload
			public = payload["public"]
			phase = "ended" if payload["winner"] != 0 else "result"
			_show_round_result()
		"aborted":
			phase = "aborted"
			_set_status(payload["message"])
		"error":
			_set_status(payload["message"])

func _apply_snapshot(payload: Dictionary) -> void:
	match_id = payload["match_id"]
	phase = payload["phase"]
	public = payload["public"]
	last_result = payload["last_result"]
	confirmed_count = payload["confirmed_count"]
	_locked = payload["locked"]
	_submitting = false
	_deadline_ms = Time.get_ticks_msec() + int(payload["remaining_ms"])
	if not last_result.is_empty():
		_show_round_result()
	elif _locked:
		_set_status("行动已锁定，等待统一揭晓。")
	elif phase == "aborted":
		_set_status("结算异常，本局结束。")
	else:
		_set_status("选择一张牌加减，或 PASS。")

func _show_round_result() -> void:
	var hit := name_for(last_result["hit_peer"])
	if last_result["eliminated"] != 0:
		_set_status("第 %d 轮命中 %s，生命归零，已淘汰。位移 %+d。" % [
			last_result["round"], hit, last_result["delta"]
		])
	else:
		_set_status("第 %d 轮命中 %s，剩余生命 %d。位移 %+d。" % [
			last_result["round"], hit, last_result["remaining_lives"], last_result["delta"]
		])

func _read_roster(payload: Dictionary) -> void:
	room_code = payload["code"]
	owner_id = payload["owner_id"]
	members = payload["members"]
	initial_lives = payload["initial_lives"]

func name_for(player_id: int) -> String:
	for member in members:
		if member["id"] == player_id:
			return member["name"]
	return str(player_id)

func _set_status(message: String) -> void:
	status = message
	changed.emit()
