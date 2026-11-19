extends SceneTree
## 运行于独立客户端进程，使用游戏本身的场景、会话和 RPC。
const ClientScene = preload("res://scenes/main.tscn")
const NetBridge = preload("res://scripts/network/net_bridge.gd")

var _game

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not await _open_client():
		return
	var code := _option("turn-room", "")
	var owner := code.is_empty()
	var expected_players := clampi(int(_option("turn-players", "2")), 2, 12)
	if owner:
		_game.create_room()
	else:
		_game.join_room("OOOOOO")
		if not await _until(func(): return _game.status.begins_with("找不到这个房间"), 4.0):
			_fail("无效房间码未被拒绝")
			return
		_game.join_room(code)
	if not await _until(func(): return _game.phase == "lobby", 4.0):
		_fail("未进入房间")
		return
	if owner:
		var lives := int(_option("turn-lives", "1"))
		if lives != _game.initial_lives:
			_game.set_initial_lives(lives)
			if not await _until(func(): return _game.initial_lives == lives, 4.0):
				_fail("未同步生命设置")
				return
		print("TURN_SMOKE_ROOM=%s" % _game.room_code)
	if not _in_room_as_expected(owner):
		_fail("房间身份不正确")
		return
	_game.set_ready(true)
	if not await _until(func(): return _game.members.size() == expected_players and _game.all_ready(), 20.0):
		_fail("未达到全员准备")
		return
	if owner:
		_game.request_start()
	if not await _until(func(): return _game.phase == "choosing", 4.0):
		_fail("未开局")
		return
	var silent := "--turn-silent" in OS.get_cmdline_user_args()
	while _game.phase == "choosing":
		var round_number: int = _game.public["round"]
		var started_at := Time.get_ticks_msec()
		if not owner and round_number == 1:
			if not await _until(func(): return _game.confirmed_count >= 1, 4.0):
				_fail("未收到另一玩家的确认人数")
				return
			if not _game.last_result.is_empty() or _game.phase != "choosing":
				_fail("另一玩家确认后提前公开了行动")
				return
			print("TURN_SMOKE_SECRET round=1 confirmed=%d phase=choosing" % _game.confirmed_count)
		if not silent:
			var action := {"type": "pass"}
			if owner and round_number == 1:
				var hand: Array = _game.public["hands"][_game.local_id()]
				action = {"type": "play", "card_id": hand[0]["id"], "sign": -1}
			_game.submit_action(action)
		if not await _until(func(): return _game.phase != "choosing", 17.0):
			_fail("回合未在预期时间内结算")
			return
		if silent:
			var elapsed := Time.get_ticks_msec() - started_at
			if elapsed < 14000 or not _got_pass():
				_fail("未提交的玩家未在超时后按 PASS 结算")
				return
			print("TURN_SMOKE_TIMEOUT elapsed_ms=%d action=pass" % elapsed)
		if _game.phase == "result" and not await _until(func(): return _game.phase != "result", 5.0):
			_fail("未自动开始下一轮")
			return
	if _game.phase != "ended" or not _game.last_result.get("stats_valid", false):
		_fail("未得到有效终局")
		return
	var outcome: Dictionary = _game.last_result
	print("TURN_SMOKE_RESULT match=%d round=%d hit=%d eliminated=%d winner=%d issued=%d played=%d" % [
		outcome["match_id"], outcome["round"], outcome["hit_peer"], outcome["eliminated"],
		outcome["winner"], outcome["public"]["stats"]["issued"], outcome["public"]["stats"]["played"]
	])
	print("TURN_SMOKE_FINAL phase=ended")
	quit()

func _open_client() -> bool:
	Engine.max_fps = 60
	var scene := ClientScene.instantiate()
	root.add_child(scene)
	_game = scene.get_node("Session")
	var address := _option("turn-address", "127.0.0.1")
	var port := int(_option("turn-port", str(NetBridge.DEFAULT_PORT)))
	var ca_path := _option("turn-ca", "")
	var ca: X509Certificate
	if not ca_path.is_empty():
		ca = X509Certificate.new()
		if ca.load(ca_path) != OK:
			_fail("测试证书无法读取")
			return false
	_game.connect_server(address, port, ca)
	if await _until(func(): return _game.phase == "connected", 9.0):
		return true
	_fail("专服连接失败")
	return false

func _in_room_as_expected(owner: bool) -> bool:
	return _game.local_id() > 0 and _game.is_room_owner() == owner

func _got_pass() -> bool:
	for action in _game.last_result.get("actions", []):
		if action["peer_id"] == _game.local_id():
			return action["type"] == "pass"
	return false

func _until(condition: Callable, max_seconds: float) -> bool:
	var timer := create_timer(max_seconds)
	while not condition.call() and timer.time_left > 0.0:
		await process_frame
	return condition.call()

func _option(name: String, fallback: String) -> String:
	var prefix := "--" + name + "="
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback

func _fail(message: String) -> void:
	push_error("TURN_SMOKE_FAIL %s，当前状态：%s" % [message, _game.status])
	quit(2)
