extends SceneTree
## 集成回归：本地测试仍通过共用 MatchSession 使用同一规则与经济实现。
const ClientScene = preload("res://scenes/main.tscn")
const Rules = preload("res://scripts/core/game_rules.gd")
var game

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Engine.max_fps = 60
	var scene := ClientScene.instantiate()
	root.add_child(scene)
	game = scene.get_node("Session")
	game.start_local_test(4, 1, Rules.Mode.GREED)
	if not await _until(func(): return game.phase == "choosing", 5.0):
		_fail("本地贪婪模式未发牌")
		return
	if game.game_mode != Rules.Mode.GREED or game.card_prices.get("change") != 50:
		_fail("本地贪婪模式价格错误")
		return
	game.buy_special_card("change")
	if game.special_card_count("change") != 1:
		_fail("本地商店未购买变化卡")
		return
	game.submit_action({"type": "change", "value": 1, "sign": 1})
	if not await _until(func(): return game.phase == "settlement", 3.0):
		_fail("本地变化卡未进入结算")
		return
	game.submit_settlement(false)
	if not await _until(func(): return game.phase in ["result", "ended"], 5.0):
		_fail("本地贪婪模式未完成结算")
		return
	if game.special_card_count("change") != 0 or not game.last_result.get("stats_valid", false):
		_fail("本地变化卡库存/统计异常")
		return
	print("TURN_LOCAL_GREED_OK wallet=%d" % game.balance)
	game.start_local_test(2, 1, Rules.Mode.CLASSIC)
	if not await _until(func(): return game.phase == "choosing", 5.0):
		_fail("经典模式重启后未发牌")
		return
	game.submit_action({"type": "pass"})
	if not await _until(func(): return game.phase == "settlement", 3.0):
		_fail("本地经典模式未进入结算")
		return
	game.submit_settlement(false)
	if not await _until(func(): return game.phase == "ended", 5.0):
		_fail("本地经典模式未结束")
		return
	if game.last_result.get("winner", 0) == 0 or not game.last_result.get("stats_valid", false):
		_fail("本地经典模式结果异常")
		return
	print("TURN_LOCAL_CLASSIC_OK winner=%d" % game.last_result["winner"])
	quit()

func _until(condition: Callable, max_seconds: float) -> bool:
	var timer := create_timer(max_seconds)
	while not condition.call() and timer.time_left > 0.0:
		await process_frame
	return condition.call()

func _fail(reason: String) -> void:
	push_error("TURN_LOCAL_FAIL " + reason)
	quit(2)
