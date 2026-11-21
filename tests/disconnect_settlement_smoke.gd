extends SceneTree
## 回归：专服确认后玩家掉线，原行动仍可结算；未提交玩家自动 PASS。
const MatchSession = preload("res://scripts/server/match_session.gd")
const Rules = preload("res://scripts/core/game_rules.gd")
const Commit = preload("res://scripts/network/action_commit.gd")

var _events: Array = []
var _result: Dictionary = {}
var _aborted := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not await _locked_action_survives_disconnect():
		return
	if not await _uncommitted_player_auto_passes():
		return
	if not await _online_timeout_auto_passes():
		return
	print("TURN_DISCONNECT_SETTLEMENT_OK")
	quit()

func _new_match(match_id: int) -> Node:
	_events.clear()
	_result.clear()
	_aborted = false
	var session := MatchSession.new()
	root.add_child(session)
	session.player_update.connect(func(id: int, kind: String, payload: Dictionary):
		_events.append({"id": id, "kind": kind, "payload": payload}))
	session.room_update.connect(func(kind: String, payload: Dictionary):
		if kind == "round_result":
			_result = payload.duplicate(true)
		elif kind == "aborted":
			_aborted = true)
	session.start(match_id, [1, 2, 3], 5, Rules.Mode.CLASSIC)
	return session

func _locked_action_survives_disconnect() -> bool:
	var session := _new_match(101)
	if not await _until(func(): return session._state["phase"] == "choosing", 3.0):
		return _fail("测试对局未开始")
	# B 的牌调整为面值 1；同步发牌统计，确保完整统计守恒。
	var hand: Array = session._state["hands"][2]
	var old_value: int = int(hand[0]["value"])
	Rules.add_count(session._state["issued"], old_value, -1)
	hand[0]["value"] = 1
	Rules.add_count(session._state["issued"], 1)
	session._state["initial_index"] = 0
	var action := {"type": "play", "card_id": int(hand[0]["id"]), "sign": 1}
	var nonce: String = Commit.create_nonce()
	var hash_text: String = Commit.compute(101, 1, 2, action, nonce)
	var payload := {"match_id": 101, "round": 1, "hash": hash_text, "nonce": nonce, "action": action}
	var invalid_payload: Dictionary = payload.duplicate(true)
	invalid_payload["hash"] = "0".repeat(64) if hash_text != "0".repeat(64) else "1".repeat(64)
	session.submit_commit(2, invalid_payload)
	if session._commits.has(2) or session._actions.has(2) or not _received(2, "action_rejected"):
		return _fail("无效哈希未拒绝")
	_events.clear()
	session.submit_commit(2, payload)
	if not session._commits.has(2) or session._actions.get(2) != action or not _received(2, "commit_ack"):
		return _fail("B 未在服务端锁定完整行动")
	session.player_disconnected(2)
	session.submit_commit(1, _pass_payload(101, 1))
	session.submit_commit(3, _pass_payload(101, 3))
	if session._state["phase"] != "settlement" or Rules.preview_delta(session._state, session._actions) != 1:
		return _fail("B 掉线后行动未进入结算")
	session.submit_settlement(1, {"match_id": 101, "round": 1, "use_super": false})
	session.submit_settlement(3, {"match_id": 101, "round": 1, "use_super": false})
	if _aborted or not _result.get("stats_valid", false) or int(_result.get("delta", 0)) != 1:
		return _fail("已锁定玩家掉线导致结算中止或数值错误")
	if int(_result.get("hit_peer", 0)) != 2 or int(_result.get("remaining_lives", 0)) != 4:
		return _fail("B 的 +1 未按预期扣除目标生命")
	if not await _until(func(): return session._state["phase"] == "choosing" and session._state["round"] == 2, 5.0):
		return _fail("其他玩家未能继续下一轮")
	session.queue_free()
	return true

func _uncommitted_player_auto_passes() -> bool:
	var session := _new_match(102)
	if not await _until(func(): return session._state["phase"] == "choosing", 3.0):
		return _fail("第二场对局未开始")
	session.player_disconnected(2)
	session.submit_commit(1, _pass_payload(102, 1))
	session.submit_commit(3, _pass_payload(102, 3))
	if session._state["phase"] != "settlement" or session._actions.get(2, {}).get("type") != "pass":
		return _fail("未提交的掉线玩家未自动 PASS")
	session.submit_settlement(1, {"match_id": 102, "round": 1, "use_super": false})
	session.submit_settlement(3, {"match_id": 102, "round": 1, "use_super": false})
	if _aborted or not _result.get("stats_valid", false) or int(_result.get("delta", -1)) != 0:
		return _fail("自动 PASS 结算失败")
	session.queue_free()
	return true

func _online_timeout_auto_passes() -> bool:
	var session := _new_match(103)
	if not await _until(func(): return session._state["phase"] == "choosing", 3.0):
		return _fail("第三场对局未开始")
	session.submit_commit(2, _pass_payload(103, 2))
	# 模拟 15 秒倒计时结束：未提交的在线玩家也必须进入结算，而非卡在 choosing。
	session._on_timer()
	if session._state["phase"] != "settlement" or session._actions.get(1, {}).get("type") != "pass" or session._actions.get(3, {}).get("type") != "pass":
		return _fail("在线玩家超时未自动 PASS")
	for id in [1, 2, 3]:
		session.submit_settlement(id, {"match_id": 103, "round": 1, "use_super": false})
	if _aborted or not _result.get("stats_valid", false):
		return _fail("在线玩家超时后结算失败")
	session.queue_free()
	return true

func _pass_payload(match_id: int, id: int) -> Dictionary:
	var action := {"type": "pass"}
	var nonce := Commit.create_nonce()
	return {"match_id": match_id, "round": 1, "action": action, "nonce": nonce,
		"hash": Commit.compute(match_id, 1, id, action, nonce)}

func _received(id: int, kind: String) -> bool:
	for item in _events:
		if item["id"] == id and item["kind"] == kind:
			return true
	return false

func _until(condition: Callable, seconds: float) -> bool:
	var timer := create_timer(seconds)
	while not condition.call() and timer.time_left > 0:
		await process_frame
	return condition.call()

func _fail(message: String) -> bool:
	push_error("TURN_DISCONNECT_SETTLEMENT_FAIL " + message)
	quit(2)
	return false
