extends Node
## 权威对局：PR1 专服生命周期 + PR2 玩法、经济、承诺揭晓及结算。
signal room_update(kind: String, payload: Dictionary)
signal player_update(player_id: int, kind: String, payload: Dictionary)

const Rules = preload("res://scripts/core/game_rules.gd")
const Commit = preload("res://scripts/network/action_commit.gd")
const Economy = preload("res://scripts/core/economy.gd")
const Settings = preload("res://scripts/core/economy_settings.gd")
const PresentationTiming = preload("res://scripts/core/round_presentation_timing.gd")
const CHOOSE_SECONDS := 15.0
const NEXT_ROUND_DELAY := 2.5
const RESULT_SYNC_MARGIN := 0.15

var _presentation_timing = preload("res://ui/round_presentation_timing.tres")
var _match_id := 0
var _state: Dictionary = {}
var _commits: Dictionary = {}
var _actions: Dictionary = {}
var _settlement_choices: Dictionary = {}
var _offline: Dictionary = {}
var _last_result: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _timer := Timer.new()
var _deadline_ms := 0
var _local_player_id := 0

func _ready() -> void:
	_rng.randomize()
	_timer.one_shot = true
	add_child(_timer)
	_timer.timeout.connect(_on_timer)

func start(match_id: int, player_ids: Array, initial_lives: int, mode: Rules.Mode = Rules.Mode.CLASSIC, economy_values: Dictionary = {}, local_player_id: int = 0) -> void:
	_match_id = match_id
	_local_player_id = local_player_id
	_state = Rules.make_state(player_ids, initial_lives, economy_values, mode)
	_last_result.clear()
	room_update.emit("match_started", {
		"match_id": _match_id, "mode": mode, "card_prices": _state["economy"]["prices"].duplicate(),
		"super_steps": _state["economy"]["super_steps"], "batch_purchases": true
	})
	_sync_wallets()
	if _state["phase"] == "ended":
		room_update.emit("round_result", {"round": 0, "winner": _state["ranking"][0], "public": Rules.public_state(_state)})
		return
	_begin_intro()

func is_finished() -> bool:
	return _state.get("phase") in ["ended", "aborted"]

func submit_action(player_id: int, payload: Dictionary) -> void:
	# 旧 action RPC 不允许绕过权威提交阶段。
	_reject(player_id, payload, "请使用承诺提交协议。")

func submit_commit(player_id: int, payload: Dictionary) -> void:
	if _state.get("phase") != "choosing" or _expired() or not _allowed(player_id, payload) or _offline.has(player_id):
		return
	if _commits.has(player_id):
		_player(player_id, "commit_ack", {"round": _state["round"]})
		return
	var hash_text: Variant = payload.get("hash")
	var action: Variant = payload.get("action")
	var nonce: Variant = payload.get("nonce")
	if not hash_text is String or not action is Dictionary or not nonce is String:
		_reject(player_id, payload, "行动提交无效，请重试。")
		return
	if not hash_text.is_valid_hex_number() or not Rules.valid_action(_state, player_id, action) or not Commit.valid_reveal(hash_text, _match_id, int(_state["round"]), player_id, action, nonce):
		_reject(player_id, payload, "行动提交校验失败，请重试。")
		return
	# ACK 仅在服务器持有可结算的行动后发送；断线也不会丢失已锁定的出牌。
	_commits[player_id] = hash_text
	_actions[player_id] = action.duplicate(true)
	_player(player_id, "commit_ack", {"round": _state["round"]})
	_publish_commit_count(_commits.keys())
	_finish_if_ready()

func purchase(player_id: int, payload: Dictionary) -> void:
	if payload.get("match_id") != _match_id or _state.get("phase") not in ["choosing", "settlement", "result"]:
		return
	if _offline.has(player_id):
		return
	var success := false
	var order: Variant = payload.get("order")
	var kind: Variant = payload.get("kind")
	if order is Dictionary:
		success = Economy.purchase_many(_state, player_id, order)
	elif kind is String:
		success = Economy.purchase(_state, player_id, kind)
	_send_wallet(player_id, "已加入我的手牌。" if success else "购买失败：余额不足或不能购买。")
	if success:
		room_update.emit("hidden_cards", {"match_id": _match_id, "round": _state["round"],
			"counts": Economy.hidden_card_counts(_state), "balances": _state["balances"].duplicate()})

func submit_settlement(player_id: int, payload: Dictionary) -> void:
	if _state.get("phase") != "settlement" or not _allowed(player_id, payload) or _settlement_choices.has(player_id):
		return
	var use_super: Variant = payload.get("use_super")
	if not use_super is bool or (use_super and not Economy.owns(_state, player_id, "super")):
		_player(player_id, "settlement_rejected", {})
		return
	_settlement_choices[player_id] = use_super
	room_update.emit("settlement_confirmed", {"match_id": _match_id, "round": _state["round"],
		"ids": _settlement_choices.keys()})
	_finish_settlement_if_ready()

func submit_local_action(player_id: int, action: Dictionary) -> void:
	if _local_player_id != player_id or _state.get("phase") != "choosing" or not Rules.valid_action(_state, player_id, action):
		return
	_actions[player_id] = action.duplicate(true)
	_timer.stop()
	_begin_settlement()

func submit_local_settlement(player_id: int, use_super: bool) -> void:
	if _local_player_id != player_id:
		return
	submit_settlement(player_id, {"match_id": _match_id, "round": _state["round"], "use_super": use_super})

func player_disconnected(player_id: int) -> void:
	_offline[player_id] = true
	if _state.get("phase") == "choosing":
		_finish_if_ready()
	elif _state.get("phase") == "settlement":
		_finish_settlement_if_ready()

func player_reconnected(player_id: int) -> void:
	_offline.erase(player_id)

func snapshot_for(player_id: int) -> Dictionary:
	return {"match_id": _match_id, "phase": _state["phase"], "public": Rules.public_state(_state),
		"mode": _state["mode"], "card_prices": _state["economy"]["prices"].duplicate(), "batch_purchases": true,
		"super_steps": _state["economy"]["super_steps"], "wallet": Economy.wallet(_state, player_id),
		"remaining_ms": maxi(0, _deadline_ms - Time.get_ticks_msec()),
		"confirmed_count": _commits.size(), "locked": _commits.has(player_id),
		"committed_ids": _commits.keys(), "settlement_ids": _settlement_choices.keys(),
		"settlement_submitted": _settlement_choices.has(player_id),
		"settlement_delta": Rules.preview_delta(_state, _actions) if _state["phase"] == "settlement" else 0,
		"last_result": _last_result.duplicate(true)}

func _allowed(player_id: int, payload: Dictionary) -> bool:
	return payload.get("match_id") == _match_id and payload.get("round") == _state.get("round") and _state.get("alive", []).has(player_id)

func _expired() -> bool:
	return Time.get_ticks_msec() >= _deadline_ms

func _player(id: int, kind: String, payload: Dictionary) -> void:
	player_update.emit(id, kind, payload)

func _reject(id: int, payload: Dictionary, message: String) -> void:
	_player(id, "action_rejected", {"match_id": payload.get("match_id"), "round": payload.get("round"), "message": message})

func _send_wallet(id: int, notice: String = "") -> void:
	var data: Dictionary = Economy.wallet(_state, id)
	data["match_id"] = _match_id
	data["notice"] = notice
	_player(id, "wallet", data)

func _sync_wallets() -> void:
	for id in _state["balances"]:
		_send_wallet(int(id))

func _begin_intro() -> void:
	if _state["alive"].size() < 2:
		return
	_state["phase"] = "round_intro"
	var duration: float = _presentation_timing.turn_intro_seconds
	_deadline_ms = Time.get_ticks_msec() + roundi(duration * 1000.0)
	_timer.start(duration)
	room_update.emit("round_intro", {"match_id": _match_id,
		"public": Rules.public_state(_state), "duration": duration})

func _begin_round() -> void:
	Rules.begin_round(_state, _rng)
	_commits.clear()
	_actions.clear()
	_settlement_choices.clear()
	_last_result.clear()
	var duration: float = CHOOSE_SECONDS + _presentation_timing.wheel_stop_hold + PresentationTiming.INITIAL_CAMERA_RETURN_SECONDS
	_timer.start(duration)
	_deadline_ms = Time.get_ticks_msec() + int(duration * 1000)
	room_update.emit("round_started", {"match_id": _match_id, "public": Rules.public_state(_state), "duration": duration})
	if _local_player_id != 0:
		for id in _state["alive"]:
			if id == _local_player_id:
				continue
			var action: Dictionary = {"type": "pass"}
			if _state["mode"] == Rules.Mode.GREED:
				var hand: Array = _state["hands"][id]
				action = {"type": "play", "card_id": hand.back()["id"], "sign": 1 if _rng.randi_range(0, 1) == 1 else -1}
			_actions[id] = action
		_publish_commit_count(_actions.keys())
		if not _state["alive"].has(_local_player_id):
			_begin_settlement()
	else:
		_finish_if_ready()

func _publish_commit_count(ids: Array) -> void:
	room_update.emit("commit_count", {"match_id": _match_id, "round": _state["round"],
		"count": ids.size(), "ids": ids})

func _finish_if_ready() -> void:
	if _state.get("phase") != "choosing":
		return
	for id in _state["alive"]:
		if not _offline.has(id) and not _commits.has(id):
			return
	_begin_settlement()

func _begin_settlement() -> void:
	if _state.get("phase") != "choosing":
		return
	_timer.stop()
	if _local_player_id == 0:
		for id in _state["alive"]:
			if not _actions.has(id):
				_actions[id] = {"type": "pass"}
	_state["phase"] = "settlement"
	_settlement_choices.clear()
	var duration: float = float(_state["economy"]["settlement_seconds"])
	_timer.start(duration)
	_deadline_ms = Time.get_ticks_msec() + int(duration * 1000)
	room_update.emit("settlement_started", {"duration": duration, "delta": Rules.preview_delta(_state, _actions)})
	_finish_settlement_if_ready()

func _finish_settlement_if_ready() -> void:
	if _state.get("phase") != "settlement":
		return
	for id in _state["alive"]:
		if _local_player_id != 0 and id != _local_player_id:
			continue
		if not _offline.has(id) and not _settlement_choices.has(id):
			return
	_finish_settlement()

func _finish_settlement() -> void:
	if _state.get("phase") != "settlement":
		return
	_timer.stop()
	var super_players: Array = []
	for id in _settlement_choices:
		if _settlement_choices[id]:
			super_players.append(id)
	var before: Dictionary = _state["balances"].duplicate()
	var outcome: Dictionary = Rules.finish_round(_state, _actions, super_players)
	_settlement_choices.clear()
	_actions.clear()
	if not outcome.get("ok", false) or not outcome.get("stats_valid", false):
		_abort("规则结算失败，对局已中止。")
		return
	outcome["match_id"] = _match_id
	_last_result = outcome.duplicate(true)
	room_update.emit("round_result", outcome)
	_sync_wallets()
	print("TURN_ROUND match=%d round=%d hit=%d eliminated=%d winner=%d stats_ok=true" % [
		_match_id, outcome["round"], outcome["hit_peer"], outcome["eliminated"], outcome["winner"]])
	if _state["phase"] == "result":
		var paid := false
		for id in _state["balances"]:
			if int(_state["balances"][id]) > int(before.get(id, 0)):
				paid = true
				break
		var delay: float = NEXT_ROUND_DELAY + _presentation_timing.wheel_stop_hold
		if paid:
			delay = (_presentation_timing.wheel_stop_hold + PresentationTiming.RESULT_WHEEL_SECONDS
				+ PresentationTiming.REWARD_SEQUENCE_SECONDS + RESULT_SYNC_MARGIN)
		if int(outcome.get("eliminated", 0)) != 0:
			delay += PresentationTiming.TOMBSTONE_FALL_SECONDS + PresentationTiming.TOMBSTONE_IMPACT_SECONDS
		_timer.start(delay)
		_deadline_ms = Time.get_ticks_msec() + int(delay * 1000)

func _abort(message: String) -> void:
	_timer.stop()
	_state["phase"] = "aborted"
	room_update.emit("aborted", {"message": message})
	push_error("TURN_MATCH_ABORT match=%d: %s" % [_match_id, message])

func _on_timer() -> void:
	match _state.get("phase"):
		"round_intro":
			_begin_round()
		"choosing":
			if _local_player_id != 0:
				_actions[_local_player_id] = {"type": "pass"}
			_begin_settlement()
		"settlement":
			_finish_settlement()
		"result":
			_begin_intro()
