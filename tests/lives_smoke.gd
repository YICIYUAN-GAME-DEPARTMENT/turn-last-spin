extends SceneTree
## 可调整初始生命的纯规则验证：不需要第三方测试框架。
const Rules = preload("res://scripts/core/game_rules.gd")

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> bool:
	if not condition:
		push_error("TURN_LIVES_FAIL: " + label)
		return false
	return true

func _run() -> void:
	var ok: bool = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261118
	var state: Dictionary = Rules.make_state([1, 2], 3)
	ok = _check(int(state["initial_lives"]) == 3, "initial_lives must be 3") and ok
	ok = _check(int(state["lives"][1]) == 3 and int(state["lives"][2]) == 3, "all start with equal lives") and ok
	for turn in range(3):
		Rules.begin_round(state, rng)
		state["initial_index"] = 0
		var before: int = state["hands"][1].size()
		var result: Dictionary = Rules.finish_round(state, {})
		ok = _check(bool(result.get("ok", false)), "PASS round must resolve") and ok
		ok = _check(int(result.get("hit_peer", 0)) == 1, "target is player 1") and ok
		ok = _check(int(result.get("remaining_lives", -1)) == 2 - turn, "damage exactly 1") and ok
		ok = _check(bool(result.get("stats_valid", false)), "stats hold after hit") and ok
		if turn < 2:
			ok = _check(int(result["eliminated"]) == 0, "no elimination while lives remain") and ok
			ok = _check(state["alive"].size() == 2, "wheel unchanged before death") and ok
			ok = _check(state["hands"][1].size() == before, "hand retained after nonfatal hit") and ok
		else:
			ok = _check(int(result["eliminated"]) == 1, "zero lives eliminates player 1") and ok
			ok = _check(int(result["winner"]) == 2, "player 2 wins") and ok
	var stats: Dictionary = Rules.statistics(state)
	ok = _check(int(stats["issued"]) == 6, "2 players x 3 rounds = 6 dealt") and ok
	ok = _check(int(stats["discarded"]) == 3 and int(stats["held"]) == 3, "dead player discarded; winner kept cards") and ok
	ok = _check(int(Rules.make_state([1, 2], 99)["initial_lives"]) == 5, "initial lives clamp to 5") and ok
	ok = _check(int(Rules.make_state([1, 2], -3)["initial_lives"]) == 1, "initial lives clamp to 1") and ok
	var ids: Array = []
	for i in range(1, 13):
		ids.append(i)
	var long_game: Dictionary = Rules.make_state(ids, 5)
	var rounds: int = 0
	while long_game["alive"].size() > 1 and rounds < 60:
		Rules.begin_round(long_game, rng)
		long_game["initial_index"] = 0
		var result: Dictionary = Rules.finish_round(long_game, {})
		ok = _check(bool(result.get("ok", false)) and bool(result.get("stats_valid", false)), "12-player 5-life round valid") and ok
		rounds += 1
	ok = _check(rounds == 55, "12 players x 5 hits on earliest surviving player = 55 rounds") and ok
	ok = _check(long_game["alive"].size() == 1, "12-player game ends with a winner") and ok
	ok = _check(int(Rules.statistics(long_game)["issued"]) == 385, "55 rounds, total 385 dealt") and ok
	if ok:
		print("TURN_LIVES_OK two_players=3_rounds twelve_players=55_rounds issued=385")
		quit(0)
	else:
		quit(2)
