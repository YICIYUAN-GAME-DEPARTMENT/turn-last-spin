extends SceneTree
## Dedicated Server + PR2 规则集的真实 WebSocket 双客户端测试。
const ClientScene = preload("res://scenes/main.tscn")
const NetBridge = preload("res://scripts/network/net_bridge.gd")
const Rules = preload("res://scripts/core/game_rules.gd")

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
	if not await _until(func(): return _game.phase == "lobby", 5.0):
		_fail("未进入房间")
		return
	if owner:
		var requested_lives := int(_option("turn-lives", "1"))
		_game.set_initial_lives(requested_lives)
		var target_mode := int(_option("turn-mode", str(Rules.Mode.CLASSIC)))
		_game.set_game_mode(target_mode)
		if not await _until(func(): return _game.game_mode == target_mode and _game.initial_lives == requested_lives, 5.0):
			_fail("房间配置未同步")
			return
		print("TURN_SMOKE_ROOM=%s" % _game.room_code)
	if not _in_room_as_expected(owner):
		_fail("房主/玩家身份不正确")
		return
	_game.set_ready(true)
	if not await _until(func(): return _game.members.size() == expected_players and _game.all_ready(), 25.0):
		_fail("未达到全员准备")
		return
	if owner:
		_game.request_start()
	if not await _until(func(): return _game.phase == "choosing", 7.0):
		_fail("未开始第一轮")
		return
	if _game.card_prices.is_empty() or _game.special_cards.size() > 0:
		_fail("对局价格/初始背包错误")
		return
	var last_submitted_round := -1
	var last_settlement_round := -1
	var requested_rounds := int(_option("turn-rounds", "0"))
	var test_special := "--turn-test-special" in OS.get_cmdline_user_args()
	var tested_special := false
	var deadline := Time.get_ticks_msec() + 150000
	while _game.phase not in ["ended", "aborted"] and Time.get_ticks_msec() < deadline:
		if requested_rounds > 0 and _game.phase == "result" and int(_game.last_result.get("round", 0)) >= requested_rounds:
			break
		if _game.phase == "choosing" and _game.can_act():
			var round_number: int = int(_game.public.get("round", 0))
			if round_number != last_submitted_round:
				last_submitted_round = round_number
				var action: Dictionary = {"type": "pass"}
				if owner and round_number == 1:
					if test_special:
						_game.buy_special_card("change")
						if not await _until(func(): return _game.special_card_count("change") == 1, 3.0):
							_fail("特殊牌购买或私人库存同步失败")
							return
						action = {"type": "change", "value": 1, "sign": 1}
						tested_special = true
					else:
						var hand: Array = _game.public["hands"][_game.local_id()]
						action = {"type": "play", "card_id": int(hand[0]["id"]), "sign": -1}
				_game.submit_action(action)
		if _game.phase == "settlement" and _game.can_settle():
			var round_number: int = int(_game.public["round"])
			if round_number != last_settlement_round:
				last_settlement_round = round_number
				_game.submit_settlement(false)
		await process_frame
	if requested_rounds > 0:
		if int(_game.last_result.get("round", 0)) < requested_rounds or not _game.last_result.get("stats_valid", false):
			_fail("指定回合的规则结算失败")
			return
		if tested_special:
			var used_change := false
			for item in _game.last_result.get("actions", []):
				if item.get("peer_id") == _game.local_id() and item.get("type") == "change":
					used_change = true
			if not used_change or _game.special_card_count("change") != 0:
				_fail("变化卡未正常消费或结算")
				return
		print("TURN_SMOKE_SPECIAL_OK round=%d mode=%d wallet=%d" % [_game.last_result["round"], _game.game_mode, _game.balance])
		quit()
		return
	if _game.phase != "ended" or not _game.last_result.get("stats_valid", false):
		_fail("专服未形成有效终局")
		return
	if _game.last_result.get("public", {}).get("mode") != _game.game_mode:
		_fail("最终模式状态不一致")
		return
	print("TURN_SMOKE_RESULT match=%d round=%d hit=%d winner=%d balance=%d" % [
		_game.match_id, _game.last_result["round"], _game.last_result["hit_peer"],
		_game.last_result["winner"], _game.balance
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
	if await _until(func(): return _game.phase == "connected", 10.0):
		return true
	_fail("专服连接失败")
	return false

func _in_room_as_expected(owner: bool) -> bool:
	return _game.local_id() > 0 and _game.is_room_owner() == owner

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
