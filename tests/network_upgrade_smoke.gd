extends "res://tests/network_smoke.gd"
## 两端执行同一个脚本，依次覆盖大厅权限、断线恢复和显式离房。

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
	if not await _until(func(): return _game.members.size() == 2 and _game.members[1]["ready"], 12.0):
		_fail("未等到客人")
		return
	var guest_id: int = _game.members[1]["id"]
	_game.manage_member("transfer_owner", guest_id)
	if not await _until(func(): return _game.owner_id == guest_id, 4.0):
		_fail("未转交房主")
		return
	if not await _until(func(): return _game.is_room_owner(), 4.0):
		_fail("房主未转回")
		return
	_game.manage_member("remove_member", guest_id)
	_game.set_ready(true)
	if not await _until(func(): return _game.all_ready(), 8.0):
		_fail("客人未重新入房并准备")
		return
	_game.request_start()
	if not await _until(func(): return _game.phase == "choosing", 4.0):
		_fail("未开局")
		return
	if not await _until(func(): return not _is_online(guest_id), 6.0):
		_fail("服务端未标记断线")
		return
	if not await _until(func(): return _is_online(guest_id), 6.0):
		_fail("原席位未恢复在线")
		return
	_game.submit_action({"type": "pass"})
	if not await _until(func(): return _game.phase == "ended", 4.0):
		_fail("未完成结算")
		return
	if not _report_result(guest_id):
		return
	if not await _until(func(): return not _is_online(guest_id), 6.0):
		_fail("客人未主动离房")
		return
	_game.request_return_lobby()
	if not await _until(func(): return _game.phase == "lobby" and _game.members.size() == 1, 4.0):
		_fail("返回大厅后仍保留已退出的成员")
		return
	print("TURN_UPGRADE_LOBBY_OK")
	quit()

func _run_guest(code: String) -> void:
	_game.join_room(code)
	if not await _until(func(): return _game.phase == "lobby", 4.0):
		_fail("未加入房间")
		return
	var player_id: int = _game.local_id()
	var original_owner: int = _game.owner_id
	# 直接经真实 RPC 请求，验证服务端检查，而非只看界面有没有按钮。
	root.get_node("Main/Net").send_command("remove_member", {"code": code, "target_id": original_owner})
	if not await _until(func(): return _game.status.begins_with("只有房主"), 4.0):
		_fail("未经授权的成员管理未被拒绝")
		return
	_game.set_ready(true)
	if not await _until(func(): return _game.is_room_owner(), 4.0):
		_fail("未收到房主身份")
		return
	_game.manage_member("transfer_owner", original_owner)
	if not await _until(func(): return _game.phase == "connected" and _game.status.contains("移出"), 4.0):
		_fail("未收到移出房间通知")
		return
	_game.join_room(code)
	if not await _until(func(): return _game.phase == "lobby", 4.0):
		_fail("未重新入房")
		return
	_game.set_ready(true)
	if not await _until(func(): return _game.phase == "choosing", 6.0):
		_fail("未开局")
		return
	var hand: Array = _game.public["hands"][player_id].duplicate(true)
	_game.submit_action({"type": "play", "card_id": hand[0]["id"], "sign": -1})
	if not await _until(func(): return _game.status.begins_with("行动已锁定"), 4.0):
		_fail("未收到行动回执")
		return
	var client = root.get_node("Main")
	for button in client.action_buttons:
		if not button.disabled:
			_fail("提交后仍有动作控件可操作")
			return
	var old_peer: int = client.multiplayer.get_unique_id()
	# 触发客户端失联处理，关闭旧 socket 并经新 socket 连接真实服务端。
	root.get_node("Main/Net").server_lost.emit()
	if not await _until(func(): return _game.phase == "choosing", 7.0):
		_fail("未恢复选择阶段")
		return
	if _game.local_id() != player_id or client.multiplayer.get_unique_id() == old_peer \
			or _game.can_act() or _game.public["hands"][player_id] != hand:
		_fail("恢复后原身份、手牌或已锁定行动有变化")
		return
	print("TURN_UPGRADE_RESUME_OK player=%d round=%d locked=true" % [player_id, _game.public["round"]])
	if not await _until(func(): return _game.phase == "ended", 5.0):
		_fail("重连后未收到终局")
		return
	if not _report_result(player_id):
		return
	_game.leave_room()
	if not await _until(func(): return _game.phase == "connected" and _game.room_code.is_empty(), 4.0):
		_fail("主动离房未返回建房入口")
		return
	print("TURN_UPGRADE_LEAVE_OK")
	quit()

func _is_online(player_id: int) -> bool:
	for member in _game.members:
		if member["id"] == player_id:
			return member["online"]
	return false

func _report_result(player_id: int) -> bool:
	var result: Dictionary = _game.last_result
	var plays := 0
	for action in result["actions"]:
		if action["peer_id"] == player_id and action["type"] == "play":
			plays += 1
	if plays != 1 or not _game.status.contains("已淘汰") or result["wheel"]["target_index"] != result["target_index"]:
		_fail("重连行动重复结算，或缺少淘汰提示及落点")
		return false
	print("TURN_SMOKE_RESULT match=%d winner=%d played=%d target=%d" % [
		result["match_id"], result["winner"], plays, result["target_index"]
	])
	return true
