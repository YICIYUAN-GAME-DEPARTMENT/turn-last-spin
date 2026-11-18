extends Node
## 房主型 TURN 会话；没有单独服务器进程，Host 与客人共用同一份 UI。
signal changed

const Rules = preload("res://scripts/core/game_rules.gd")
const Commit = preload("res://scripts/network/action_commit.gd")
const Economy = preload("res://scripts/core/economy.gd")
const EconomySettings = preload("res://scripts/core/economy_settings.gd")
const CHOOSE_SECONDS := 15.0
const REVEAL_SECONDS := 5.0
const NEXT_ROUND_DELAY := 2.5

@export var economy_settings: EconomySettings = EconomySettings.new()

@onready var net: Node = get_parent().get_node("Net")
var role: String = "none" # none / host / client / local
var phase: String = "offline" # offline / connecting / lobby / choosing / revealing / settlement / result / ended / aborted
var status: String = "尚未连接；Demo 通过 IP:端口直连，不具备公网短码发现。"
var members: Array = []
var initial_lives: int = 1
var public: Dictionary = {}
var last_result: Dictionary = {}
var match_id: int = 0
var commit_count: int = 0
var sealed_hash: String = ""
var sealed_nonce: String = ""
var sealed_action: Dictionary = {}
var deadline_ms: int = 0
var balance: int = 0
var special_cards: Dictionary = {}
var card_prices: Dictionary = {}
var economy_notice: String = ""
var super_steps: int = 1
var settlement_delta: int = 0
var settlement_submitted: bool = false

var _match: Dictionary = {}
var _commits: Dictionary = {}
var _reveals: Dictionary = {}
var _pending_actions: Dictionary = {}
var _settlement_choices: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _match_serial: int = 0
var _commit_timer: Timer
var _reveal_timer: Timer
var _settlement_timer: Timer
var _next_timer: Timer

func _ready() -> void:
	net.host_command.connect(_on_host_command)
	net.client_event.connect(_on_client_event)
	net.peer_joined.connect(_on_peer_joined)
	net.peer_left.connect(_on_peer_left)
	net.connected_to_host.connect(_on_connected)
	net.connection_error.connect(_on_connection_error)
	net.host_lost.connect(_on_host_lost)
	_commit_timer = _new_timer(_on_commit_deadline)
	_reveal_timer = _new_timer(_on_reveal_deadline)
	_settlement_timer = _new_timer(_finish_settlement)
	_next_timer = _new_timer(_on_next_round)

func _new_timer(callback: Callable) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(callback)
	return timer

func local_id() -> int:
	if role in ["host", "local"]:
		return 1
	if role == "client" and phase != "connecting":
		return multiplayer.get_unique_id()
	return 0

func am_host() -> bool:
	return role == "host"

func can_act() -> bool:
	return phase == "choosing" and sealed_hash.is_empty() and public.get("alive", []).has(local_id())

func is_ready() -> bool:
	for member in members:
		if int(member["id"]) == local_id():
			return bool(member["ready"])
	return false

func all_ready() -> bool:
	if members.size() < 2 or members.size() > 12:
		return false
	for member in members:
		if not bool(member["online"]) or not bool(member["ready"]):
			return false
	return true

func seconds_left() -> int:
	if phase not in ["choosing", "settlement"]:
		return 0
	return maxi(0, ceili(float(deadline_ms - Time.get_ticks_msec()) / 1000.0))

func can_buy_cards() -> bool:
	return _shop_open(phase) and public.get("alive", []).has(local_id())

func special_card_count(kind: String) -> int:
	var count: int = int(special_cards.get(kind, 0))
	# 锁定后即从可用库存扣除，正式消费在房主结算中完成。
	if phase in ["choosing", "revealing", "settlement"] and sealed_action.get("type") == kind:
		return maxi(0, count - 1)
	return count

func can_settle() -> bool:
	return phase == "settlement" and not settlement_submitted and public.get("alive", []).has(local_id())

func buy_special_card(kind: String) -> void:
	var price: int = int(card_prices.get(kind, -1))
	if not can_buy_cards() or price < 0 or balance < price:
		return
	var payload := {"match_id": match_id, "kind": kind}
	if role == "local":
		_host_purchase(local_id(), payload)
	else:
		net.send_command("buy_card", payload)

func submit_settlement(use_super: bool) -> void:
	if not can_settle() or (use_super and int(special_cards.get("super", 0)) < 1):
		return
	settlement_submitted = true
	_emit_changed()
	var payload := {"match_id": match_id, "round": public["round"], "use_super": use_super}
	if role == "local":
		_host_settlement_choice(local_id(), payload)
	else:
		net.send_command("settlement_choice", payload)

func _shop_open(current_phase: String) -> bool:
	return current_phase in ["choosing", "revealing", "settlement", "result"]

func start_local_test(player_count: int, lives: int) -> void:
	if role != "local" and (role != "none" or phase != "offline"):
		return
	_stop_timers()
	public = {}
	phase = "offline"
	role = "local"
	_rng.randomize()
	initial_lives = clampi(lives, 1, Rules.MAX_INITIAL_LIVES)
	members = [{"id": 1, "name": "本地玩家", "ready": true, "online": true}]
	for id in range(2, clampi(player_count, 2, Rules.MAX_PLAYERS) + 1):
		members.append({"id": id, "name": String.chr(95 + id), "ready": true, "online": true})
	_start_match()

func start_host(port: int = 24680) -> void:
	if role != "none":
		return
	if not net.start_host(port):
		return
	role = "host"
	phase = "lobby"
	_rng.randomize()
	members = [{"id": 1, "name": "a", "ready": false, "online": true}]
	_set_status("本机已建房。其他人请输入你的局域网 IP 加入。")
	_broadcast("lobby", {"members": members.duplicate(true), "initial_lives": initial_lives})

func join_host(address: String, port: int = 24680) -> void:
	if role != "none":
		return
	phase = "connecting"
	_set_status("正在连接 %s:%d ..." % [address, port])
	if net.connect_to_host(address, port):
		role = "client"
	else:
		phase = "offline"
		_emit_changed()

func _on_connected() -> void:
	_set_status("已连接房主，正在同步房间...")
	_emit_changed()

func _on_connection_error(message: String) -> void:
	role = "none"
	phase = "offline"
	_set_status(message)

func _on_host_lost() -> void:
	role = "none"
	phase = "offline"
	members.clear()
	public.clear()
	_set_status("Host 已断开，当前房间结束。本 Demo 不实现主机迁移。")

func _on_peer_joined(peer_id: int) -> void:
	if role != "host":
		return
	if phase != "lobby" or members.size() >= 12:
		net.send_event(peer_id, "error", {"message": "房间已开始或人数已满"})
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	var letter: String = "abcdefghijkl".substr(members.size(), 1)
	members.append({"id": peer_id, "name": letter, "ready": false, "online": true})
	_broadcast("lobby", {"members": members.duplicate(true), "initial_lives": initial_lives})
	_set_status("成员已加入：%s" % letter)

func _on_peer_left(peer_id: int) -> void:
	if role != "host":
		return
	if phase == "lobby":
		for index in range(members.size() - 1, -1, -1):
			if int(members[index]["id"]) == peer_id:
				members.remove_at(index)
		_broadcast("lobby", {"members": members.duplicate(true), "initial_lives": initial_lives})
		return
	for member in members:
		if int(member["id"]) == peer_id:
			member["online"] = false
	_broadcast("members", {"members": members.duplicate(true)})
	if phase == "choosing":
		if _commits.has(peer_id):
			_abort_match("玩家已承诺但未揭晓就离线，Demo 不擅自改判 PASS。")
		elif _all_committed():
			_freeze_commits()
	elif phase == "revealing" and _commits.has(peer_id) and not _reveals.has(peer_id):
		_abort_match("玩家在揭晓前离线，无法从哈希还原行动。")
	elif phase == "settlement" and _all_settlement_decided():
		_finish_settlement()

func set_initial_lives(amount: int) -> void:
	if role != "host" or phase != "lobby":
		return
	var next_value: int = clampi(amount, 1, Rules.MAX_INITIAL_LIVES)
	if initial_lives == next_value:
		return
	initial_lives = next_value
	_broadcast("lobby", {"members": members.duplicate(true), "initial_lives": initial_lives})

func set_ready(ready: bool) -> void:
	if phase != "lobby":
		return
	net.send_command("ready", {"ready": ready})

func request_start() -> void:
	if role == "host" and phase == "lobby":
		_host_start()

func request_return_lobby() -> void:
	if role == "host" and phase in ["ended", "aborted"]:
		_return_to_lobby()

func submit_action(action: Dictionary) -> void:
	if not can_act():
		return
	if not Rules.valid_action(public, local_id(), action, special_cards):
		_set_status("行动无效：请检查手牌或变化卡点数。")
		return
	sealed_action = action.duplicate(true)
	if role == "local":
		_finish_local_round(action)
		return
	sealed_nonce = Commit.create_nonce()
	sealed_hash = Commit.compute(match_id, int(public["round"]), local_id(), action, sealed_nonce)
	net.send_command("commit", {"match_id": match_id, "round": public["round"], "hash": sealed_hash})
	_set_status("已经锁定承诺，等待所有人确认（未发送行动明文）。")

func _on_host_command(peer_id: int, kind: String, payload: Dictionary) -> void:
	if role != "host" or not _is_member(peer_id):
		return
	match kind:
		"ready":
			if phase == "lobby":
				for member in members:
					if int(member["id"]) == peer_id:
						member["ready"] = bool(payload.get("ready", false))
				_broadcast("lobby", {"members": members.duplicate(true), "initial_lives": initial_lives})
		"commit":
			_host_commit(peer_id, payload)
		"reveal":
			_host_reveal(peer_id, payload)
		"buy_card":
			_host_purchase(peer_id, payload)
		"settlement_choice":
			_host_settlement_choice(peer_id, payload)

func _is_member(peer_id: int) -> bool:
	for member in members:
		if int(member["id"]) == peer_id:
			return true
	return false

func _is_online(peer_id: int) -> bool:
	for member in members:
		if int(member["id"]) == peer_id:
			return bool(member["online"])
	return false

func _broadcast(kind: String, payload: Dictionary) -> void:
	if role == "local":
		_on_client_event(kind, payload)
		return
	# 先向客户端排队发送，再处理本机事件，避免本机揭晓推进阶段时乱序。
	for member in members:
		var id: int = int(member["id"])
		if bool(member["online"]) and id != local_id():
			net.send_event(id, kind, payload)
	_on_client_event(kind, payload)

func _send_private(peer_id: int, kind: String, payload: Dictionary) -> void:
	if role == "local":
		if peer_id == local_id():
			_on_client_event(kind, payload)
	elif _is_online(peer_id):
		net.send_event(peer_id, kind, payload)

func _send_wallet(peer_id: int, notice: String = "") -> void:
	var payload: Dictionary = Economy.wallet(_match, peer_id)
	payload["match_id"] = match_id
	payload["notice"] = notice
	_send_private(peer_id, "wallet", payload)

func _sync_wallets() -> void:
	for member in members:
		if bool(member["online"]):
			_send_wallet(int(member["id"]))

func _host_purchase(peer_id: int, payload: Dictionary) -> void:
	if payload.get("match_id") != match_id or not _shop_open(phase) or not _is_online(peer_id):
		return
	var kind: Variant = payload.get("kind")
	if not kind is String:
		return
	if Economy.purchase(_match, peer_id, kind):
		_send_wallet(peer_id, "已加入我的手牌。")
		_broadcast("hidden_cards", {"match_id": match_id, "round": _match["round"],
			"counts": Economy.hidden_card_counts(_match)})
	else:
		_send_wallet(peer_id, "购买失败：请检查余额或存活状态。")

func _host_start() -> void:
	if role != "host" or not all_ready():
		_set_status("开始条件不满足：至少两人且全员准备，房主才可开始。")
		return
	_start_match()

func _start_match() -> void:
	var ids: Array = []
	for member in members:
		ids.append(int(member["id"]))
	var active_economy: Resource = economy_settings if economy_settings != null else EconomySettings.new()
	var values: Dictionary = active_economy.values()
	_match = Rules.make_state(ids, initial_lives, values)
	_match_serial += 1
	match_id = _match_serial
	last_result.clear()
	_broadcast("match_started", {"match_id": match_id, "card_prices": values["prices"], "super_steps": values["super_steps"]})
	_sync_wallets()
	_host_begin_round()

func _host_begin_round() -> void:
	if role not in ["host", "local"] or _match.is_empty() or _match["alive"].size() < 2:
		return
	Rules.begin_round(_match, _rng)
	_commits.clear()
	_reveals.clear()
	phase = "choosing"
	var duration := CHOOSE_SECONDS
	if role == "local" and not _match["alive"].has(local_id()):
		duration = 1.0
	_commit_timer.start(duration)
	var payload := {
		"match_id": match_id,
		"public": Rules.public_state(_match),
		"duration": duration
	}
	_broadcast("round_started", payload)
	var round_number: int = int(_match["round"])
	if role != "local":
		_set_status("第 %d 轮：选择一张牌加减，或 PASS。确认只发送哈希。" % round_number)
	elif _match["alive"].has(local_id()):
		_set_status("第 %d 轮：测试玩家自动 PASS。选牌并确认，或等待倒计时结束。" % round_number)
	else:
		_set_status("第 %d 轮：观战中，测试玩家自动 PASS。" % round_number)

func _host_commit(peer_id: int, payload: Dictionary) -> void:
	if phase != "choosing" or not _match["alive"].has(peer_id) or not _is_online(peer_id):
		return
	if int(payload.get("match_id", -1)) != match_id or int(payload.get("round", -1)) != int(_match["round"]):
		return
	var hash_text: String = str(payload.get("hash", ""))
	if hash_text.length() != 64 or _commits.has(peer_id):
		return
	_commits[peer_id] = hash_text
	net.send_event(peer_id, "commit_ack", {"round": _match["round"]})
	_broadcast("commit_count", {"count": _commits.size()})
	if _all_committed():
		_freeze_commits()

func _all_committed() -> bool:
	for raw_id in _match.get("alive", []):
		var peer_id: int = int(raw_id)
		if _is_online(peer_id) and not _commits.has(peer_id):
			return false
	return true

func _freeze_commits() -> void:
	if phase != "choosing":
		return
	_commit_timer.stop()
	phase = "revealing"
	var entries: Array = []
	for raw_id in _match["alive"]:
		var peer_id: int = int(raw_id)
		if _commits.has(peer_id):
			entries.append({"peer_id": peer_id, "status": "commit", "hash": _commits[peer_id]})
		else:
			entries.append({"peer_id": peer_id, "status": "auto_pass"})
	_reveal_timer.start(REVEAL_SECONDS)
	_broadcast("manifest", {"match_id": match_id, "round": _match["round"], "entries": entries})
	if _commits.is_empty():
		_finish_reveals()

func _host_reveal(peer_id: int, payload: Dictionary) -> void:
	if phase != "revealing" or not _commits.has(peer_id) or _reveals.has(peer_id):
		return
	if int(payload.get("match_id", -1)) != match_id or int(payload.get("round", -1)) != int(_match["round"]):
		return
	var action: Variant = payload.get("action")
	if not action is Dictionary or not Rules.valid_action(_match, peer_id, action):
		_abort_match("揭晓的卡牌不合法，已终止当前 Demo 测试。")
		return
	var nonce: String = str(payload.get("nonce", ""))
	if not Commit.valid_reveal(str(_commits[peer_id]), match_id, int(_match["round"]), peer_id, action, nonce):
		_abort_match("揭晓与承诺不一致，已终止当前 Demo 测试。")
		return
	_reveals[peer_id] = action.duplicate(true)
	for committed_peer in _commits.keys():
		if not _reveals.has(committed_peer):
			return
	_finish_reveals()

func _finish_reveals() -> void:
	if phase != "revealing":
		return
	_reveal_timer.stop()
	var actions: Dictionary = {}
	for raw_id in _match["alive"]:
		var peer_id: int = int(raw_id)
		actions[peer_id] = _reveals.get(peer_id, {"type": "pass"})
	_begin_settlement(actions)

func _finish_local_round(action: Dictionary) -> void:
	if phase != "choosing":
		return
	_commit_timer.stop()
	var actions: Dictionary = {}
	if _match["alive"].has(local_id()):
		actions[local_id()] = action
	_begin_settlement(actions)

func _begin_settlement(actions: Dictionary) -> void:
	_pending_actions = actions
	_settlement_choices.clear()
	phase = "settlement"
	var duration: float = float(_match["economy"]["settlement_seconds"])
	_settlement_timer.start(duration)
	_broadcast("settlement_started", {"duration": duration, "delta": Rules.preview_delta(_match, actions)})
	if _all_settlement_decided():
		_finish_settlement()

func _host_settlement_choice(peer_id: int, payload: Dictionary) -> void:
	if phase != "settlement" or payload.get("match_id") != match_id or payload.get("round") != _match["round"]:
		return
	if not _is_online(peer_id) or not _match["alive"].has(peer_id) or _settlement_choices.has(peer_id):
		return
	var use_super: Variant = payload.get("use_super")
	if not use_super is bool or (use_super and not Economy.owns(_match, peer_id, "super")):
		_send_private(peer_id, "settlement_rejected", {})
		return
	_settlement_choices[peer_id] = use_super
	if _all_settlement_decided():
		_finish_settlement()

func _all_settlement_decided() -> bool:
	for id in _match["alive"]:
		if role == "local" and id != local_id():
			continue
		if _is_online(id) and not _settlement_choices.has(id):
			return false
	return true

func _finish_settlement() -> void:
	if phase != "settlement":
		return
	_settlement_timer.stop()
	var super_players: Array = _settlement_choices.keys().filter(func(id): return _settlement_choices[id])
	var outcome: Dictionary = Rules.finish_round(_match, _pending_actions, super_players)
	_pending_actions.clear()
	_settlement_choices.clear()
	if not bool(outcome.get("ok", false)) or not bool(outcome.get("stats_valid", false)):
		_abort_match("规则校验失败，已停止推进。")
		return
	phase = "ended" if int(outcome["winner"]) != 0 else "result"
	_broadcast("round_result", outcome)
	_sync_wallets()
	print("TURN_ROUND peer=%d round=%d hit=%d hp=%d eliminated=%d stats_ok=%s" % [
		local_id(), int(outcome["round"]), int(outcome["hit_peer"]),
		int(outcome["remaining_lives"]), int(outcome["eliminated"]), str(outcome["stats_valid"])
	])
	if phase == "result":
		_next_timer.start(NEXT_ROUND_DELAY)

func _on_next_round() -> void:
	if phase == "result":
		_host_begin_round()

func _on_commit_deadline() -> void:
	if role == "local":
		_finish_local_round({"type": "pass"})
	else:
		_freeze_commits()

func _on_reveal_deadline() -> void:
	if phase == "revealing":
		_abort_match("部分已承诺玩家未完成揭晓，Demo 不擅自当作 PASS。")

func _stop_timers() -> void:
	_commit_timer.stop()
	_reveal_timer.stop()
	_settlement_timer.stop()
	_next_timer.stop()
	_pending_actions.clear()
	_settlement_choices.clear()

func _abort_match(message: String) -> void:
	_stop_timers()
	phase = "aborted"
	_broadcast("aborted", {"message": message})
	print("TURN_ABORT: " + message)

func _return_to_lobby() -> void:
	_stop_timers()
	_match.clear()
	_commits.clear()
	_reveals.clear()
	for index in range(members.size() - 1, -1, -1):
		if not bool(members[index]["online"]):
			members.remove_at(index)
		else:
			members[index]["ready"] = false
	phase = "lobby"
	_broadcast("lobby", {"members": members.duplicate(true), "initial_lives": initial_lives})

func _on_client_event(kind: String, payload: Dictionary) -> void:
	match kind:
		"lobby":
			phase = "lobby"
			members = payload.get("members", []).duplicate(true)
			initial_lives = clampi(int(payload.get("initial_lives", 1)), 1, Rules.MAX_INITIAL_LIVES)
			public.clear()
			last_result.clear()
			sealed_hash = ""
			sealed_action.clear()
			balance = 0
			special_cards.clear()
			card_prices.clear()
			economy_notice = ""
			_set_status("房间已同步，等待全员准备。")
		"members":
			members = payload.get("members", []).duplicate(true)
			_emit_changed()
		"match_started":
			match_id = int(payload.get("match_id", 0))
			last_result.clear()
			card_prices = payload.get("card_prices", {}).duplicate()
			super_steps = int(payload.get("super_steps", 1))
			balance = 0
			special_cards.clear()
			economy_notice = ""
			_set_status("游戏开始，等待发牌...")
		"hidden_cards":
			if payload.get("match_id") != match_id or payload.get("round") != public.get("round"):
				return
			public["hidden_card_counts"] = payload.get("counts", {}).duplicate()
			_emit_changed()
		"wallet":
			if payload.get("match_id") != match_id:
				return
			var next_balance: int = int(payload.get("balance", 0))
			special_cards = payload.get("cards", {}).duplicate()
			economy_notice = str(payload.get("notice", ""))
			if phase in ["result", "ended"] and next_balance > balance and economy_notice.is_empty():
				economy_notice = "本轮获币 +%dr" % (next_balance - balance)
			balance = next_balance
			_emit_changed()
		"round_started":
			match_id = int(payload.get("match_id", 0))
			public = payload.get("public", {}).duplicate(true)
			initial_lives = int(public.get("initial_lives", initial_lives))
			phase = "choosing"
			commit_count = 0
			sealed_hash = ""
			sealed_nonce = ""
			sealed_action.clear()
			deadline_ms = Time.get_ticks_msec() + int(float(payload.get("duration", 15.0)) * 1000.0)
			_emit_changed()
		"commit_ack":
			_set_status("Host 已收到本轮承诺；等待统一揭晓。")
		"commit_count":
			commit_count = int(payload.get("count", 0))
			_emit_changed()
		"manifest":
			phase = "revealing"
			_set_status("承诺名单已冻结，正在自动揭晓...")
			_process_manifest(payload)
		"settlement_started":
			phase = "settlement"
			settlement_delta = int(payload.get("delta", 0))
			settlement_submitted = false
			deadline_ms = Time.get_ticks_msec() + int(float(payload.get("duration", 5.0)) * 1000.0)
			_set_status("结算阶段，可使用超级卡。")
		"settlement_rejected":
			if phase == "settlement":
				settlement_submitted = false
				_set_status("超级卡确认失败，请重新选择。")
		"round_result":
			last_result = payload.duplicate(true)
			public = payload.get("public", {}).duplicate(true)
			phase = "ended" if int(payload.get("winner", 0)) != 0 else "result"
			var hit_name: String = name_for(int(payload.get("hit_peer", payload.get("eliminated", 0))))
			if bool(payload.get("defended", false)):
				_set_status("第 %d 轮：%s 用防御卡保住最后 1 点生命；位移 %+d" % [
					int(payload["round"]), hit_name, int(payload["delta"])
				])
			elif int(payload.get("eliminated", 0)) != 0:
				_set_status("第 %d 轮：%s 生命归零，已淘汰；位移 %+d" % [
					int(payload["round"]), hit_name, int(payload["delta"])
				])
			else:
				_set_status("第 %d 轮：命中 %s，剩余生命 %d；位移 %+d" % [
					int(payload["round"]), hit_name, int(payload.get("remaining_lives", 0)), int(payload["delta"])
				])
			if phase == "ended":
				print("TURN_SMOKE_RESULT peer=%d winner=%d" % [local_id(), int(payload["winner"])])
		"aborted":
			phase = "aborted"
			_set_status(str(payload.get("message", "本局协议异常")))
		"error":
			_set_status(str(payload.get("message", "网络错误")))

func _process_manifest(payload: Dictionary) -> void:
	if int(payload.get("round", -1)) != int(public.get("round", -1)):
		return
	var committed: Dictionary = {}
	for entry in payload.get("entries", []):
		if str(entry.get("status", "")) == "commit":
			committed[int(entry["peer_id"])] = str(entry["hash"])
	if sealed_hash.is_empty():
		return # 没提交的人已经 AUTO_PASS，无需 Reveal。
	if str(committed.get(local_id(), "")) != sealed_hash:
		_set_status("承诺列表缺少本机的有效哈希，已拒绝揭晓。")
		return
	net.send_command("reveal", {
		"match_id": match_id, "round": public["round"],
		"action": sealed_action.duplicate(true), "nonce": sealed_nonce
	})

func name_for(peer_id: int) -> String:
	for member in members:
		if int(member["id"]) == peer_id:
			return str(member["name"])
	return str(peer_id)

func _set_status(message: String) -> void:
	status = message
	_emit_changed()

func _emit_changed() -> void:
	changed.emit()
