extends SceneTree
## 离线规则与承诺协议冒烟测试（不用安装第三方测试框架）。
const Rules = preload("res://scripts/core/game_rules.gd")
const Commit = preload("res://scripts/network/action_commit.gd")

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> bool:
	if not condition:
		push_error("TURN_TEST_FAIL: " + description)
		return false
	return true

func _run() -> void:
	var ok: bool = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261118
	var ids: Array = []
	for p in range(1, 13):
		ids.append(p)
	var state: Dictionary = Rules.make_state(ids)
	for current_n in range(12, 1, -1):
		Rules.begin_round(state, rng)
		ok = _check(state["alive"].size() == current_n, "alive before resolve") and ok
		for p in state["alive"]:
			var hand: Array = state["hands"][p]
			ok = _check(hand.size() >= 1, "everyone got a card") and ok
			var fresh: Dictionary = hand[hand.size() - 1]
			ok = _check(int(fresh["value"]) >= 1 and int(fresh["value"]) <= current_n, "card numeric range") and ok
		var outcome: Dictionary = Rules.finish_round(state, {})
		ok = _check(bool(outcome.get("ok", false)), "PASS round resolves") and ok
		ok = _check(int(outcome.get("delta", 123)) == 0, "PASS movement zero") and ok
		ok = _check(bool(outcome.get("stats_valid", false)), "card conservation") and ok
	ok = _check(state["alive"].size() == 1, "one survivor") and ok
	var totals: Dictionary = Rules.statistics(state)
	ok = _check(int(totals["issued"]) == 77, "12 players total 77 issued cards") and ok
	ok = _check(int(totals["played"]) == 0, "all PASS no played cards") and ok
	# 独立验证相同数字卡牌、负位移与本轮打出后被淘汰。
	var state2: Dictionary = Rules.make_state([1, 2, 3])
	state2["round"] = 1
	state2["initial_index"] = 0
	state2["hands"][1] = [{"id": 11, "value": 3}, {"id": 12, "value": 3}]
	state2["hands"][2] = [{"id": 21, "value": 1}]
	state2["hands"][3] = [{"id": 31, "value": 2}]
	state2["issued"] = {3: 2, 1: 1, 2: 1}
	var r: Dictionary = Rules.finish_round(state2, {
		1: {"type": "play", "card_id": 12, "sign": -1},
		2: {"type": "pass"},
		3: {"type": "pass"}
	})
	ok = _check(bool(r.get("ok", false)), "one card played") and ok
	ok = _check(int(r["delta"]) == -3 and int(r["target_index"]) == 0, "negative and wrap") and ok
	ok = _check(int(r["eliminated"]) == 1, "played player eliminated") and ok
	ok = _check(int(state2["played"].get(3, 0)) == 1, "one 3 consumed") and ok
	ok = _check(int(state2["discarded"].get(3, 0)) == 1, "other 3 discarded") and ok
	ok = _check(bool(r["stats_valid"]), "statistics preserved") and ok
	var act: Dictionary = {"type": "play", "card_id": 12, "sign": -1}
	var nonce: String = Commit.create_nonce()
	var hash_value: String = Commit.compute(11, 1, 1, act, nonce)
	ok = _check(nonce.length() == 64 and hash_value.length() == 64, "nonce and SHA256") and ok
	ok = _check(Commit.valid_reveal(hash_value, 11, 1, 1, act, nonce), "valid reveal") and ok
	ok = _check(not Commit.valid_reveal(hash_value, 11, 1, 1, {"type": "pass"}, nonce), "cannot change action after commit") and ok
	if ok:
		print("TURN_RULES_OK rounds=11 issued=77 repeated_values=pass negative=pass commitments=pass")
		quit(0)
	else:
		quit(2)
