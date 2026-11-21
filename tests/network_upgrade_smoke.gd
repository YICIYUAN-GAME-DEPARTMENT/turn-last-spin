extends "res://tests/network_smoke.gd"
## 专服升级回归：房主权限、提交后断线、原玩家身份及承诺状态恢复。

func _run() -> void:
	if not await _open_client():
		return
	var code := _option("turn-room", "")
	if code.is_empty():
		await _run_owner()
	else:
		await _run_guest(code)

func _run_owner() -> void:
	_game.create_room()
	if not await _until(func(): return _game.phase == "lobby", 4.0):
		_fail("未创建房间")
		return
	print("TURN_SMOKE_ROOM=%s" % _game.room_code)
	if not await _until(func(): return _game.members.size() == 2, 15.0):
		_fail("未收到客人")
		return
	_game.set_ready(true)
	if not await _until(func(): return _game.all_ready(), 8.0):
		_fail("客人未准备")
		return
	_game.request_start()
	if not await _until(func(): return _game.phase == "choosing", 6.0):
		_fail("未开始回合")
		return
	var guest_id: int = 0
	for member in _game.members:
		if member["id"] != _game.local_id():
			guest_id = member["id"]
	if not await _until(func(): return not _is_online(guest_id), 8.0):
		_fail("未发现客人断线")
		return
	if not await _until(func(): return _is_online(guest_id), 8.0):
		_fail("原席位未重新上线")
		return
	if not _game.can_act():
		_fail("房主尚未提交却无法操作")
		return
	_game.submit_action({"type": "pass"})
	if not await _until(func(): return _game.phase == "settlement", 8.0):
		_fail("重连之后未正确进入结算阶段")
		return
	_game.submit_settlement(false)
	if not await _until(func(): return _game.phase == "ended", 9.0):
		_fail("结算后未结束")
		return
	if not _game.last_result.get("stats_valid", false):
		_fail("重连结算统计无效")
		return
	print("TURN_UPGRADE_OWNER_OK room=%s winner=%d" % [_game.room_code, _game.last_result["winner"]])
	quit()

func _run_guest(code: String) -> void:
	_game.join_room(code)
	if not await _until(func(): return _game.phase == "lobby", 4.0):
		_fail("未加入房间")
		return
	var player_id: int = _game.local_id()
	var owner_id: int = _game.owner_id
	root.get_node("Main/Net").send_command("remove_member", {"code": code, "target_id": owner_id})
	if not await _until(func(): return _game.status.begins_with("只有房主"), 4.0):
		_fail("越权管理未被拒绝")
		return
	_game.set_ready(true)
	if not await _until(func(): return _game.phase == "choosing", 8.0):
		_fail("未开局")
		return
	var original_hand: Array = _game.public["hands"][player_id].duplicate(true)
	_game.submit_action({"type": "pass"})
	if not await _until(func(): return _game._locked, 4.0):
		_fail("服务端未确认承诺")
		return
	var old_peer: int = root.get_node("Main").multiplayer.get_unique_id()
	root.get_node("Main/Net").server_lost.emit()
	if not await _until(func(): return _game.phase == "choosing" and _game._locked, 8.0):
		_fail("选择阶段和锁定状态未恢复")
		return
	if _game.local_id() != player_id or root.get_node("Main").multiplayer.get_unique_id() == old_peer or _game.can_act() or _game.public["hands"][player_id] != original_hand:
		_fail("重连后身份、手牌或锁定状态不一致")
		return
	if _game.card_prices.is_empty() or _game.balance != 50:
		_fail("重连后经济快照缺失")
		return
	print("TURN_UPGRADE_RESUME_OK player=%d round=%d locked=true" % [player_id, _game.public["round"]])
	if not await _until(func(): return _game.phase == "settlement", 9.0):
		_fail("恢复后未进入结算阶段")
		return
	_game.submit_settlement(false)
	if not await _until(func(): return _game.phase == "ended", 9.0):
		_fail("恢复后未完成对局")
		return
	print("TURN_UPGRADE_GUEST_OK player=%d" % player_id)
	quit()

func _is_online(id: int) -> bool:
	for member in _game.members:
		if member["id"] == id:
			return member["online"]
	return false
