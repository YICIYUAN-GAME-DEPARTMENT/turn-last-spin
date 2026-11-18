extends SceneTree
## 货币守恒边界、暗牌消费与两阶段轮盘动作。

const Rules = preload("res://scripts/core/game_rules.gd")
const Economy = preload("res://scripts/core/economy.gd")
const Settings = preload("res://scripts/core/economy_settings.gd")
const Commit = preload("res://scripts/network/action_commit.gd")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error("TURN_ECONOMY_FAIL: " + description)

func _run() -> void:
	var state: Dictionary = Rules.make_state([1, 2])
	_check(Economy.wallet(state, 1)["balance"] == 50, "default starting balance")
	_check(not Economy.purchase(state, 1, "defense"), "insufficient funds")
	_check(not Economy.purchase(state, 1, "unknown"), "unknown card")
	_check(not Economy.purchase(state, 55, "change"), "non-member cannot buy")
	_check(not Rules.public_state(state).has("balances"), "wallet stays private")
	_check(not Rules.public_state(state).has("special_cards"), "inventory stays private")

	var settings = Settings.new()
	settings.starting_balance = 600
	var shield: Dictionary = Rules.make_state([1, 2], 2, settings.values())
	shield["initial_index"] = 0
	_check(Economy.purchase(shield, 1, "defense"), "buy defense")
	var damage: Dictionary = Rules.finish_round(shield, {1: {"type": "defense"}})
	_check(damage["remaining_lives"] == 1 and not damage["defended"], "defense still allows nonfatal hit")
	_check(not Economy.owns(shield, 1, "defense"), "defense single use")
	_check(Economy.purchase(shield, 1, "defense"), "buy another defense")
	var saved: Dictionary = Rules.finish_round(shield, {1: {"type": "defense"}})
	_check(saved["defended"] and saved["eliminated"] == 0 and saved["remaining_lives"] == 1, "defense protects the last HP")
	_check(saved["play_reward"] == 0 and Economy.wallet(shield, 1)["balance"] == 400, "no reward without elimination")
	_check(not Economy.owns(shield, 1, "defense"), "used defense was consumed")

	var split: Dictionary = Rules.make_state([1, 2, 3, 4], 1, settings.values())
	split["initial_index"] = 2
	split["balances"][3] = 52
	split["hands"][2] = [{"id": 21, "value": 1}]
	split["hands"][3] = [{"id": 31, "value": 2}]
	split["issued"] = {1: 1, 2: 1}
	_check(Economy.purchase(split, 1, "change") and Economy.purchase(split, 4, "super"), "buy change and super")
	var public: Dictionary = Rules.public_state(split)
	_check(public["hidden_card_counts"] == {1: 1, 2: 0, 3: 0, 4: 1}, "public backs only show totals")
	var actions: Dictionary = {1: {"type": "change", "value": 2}, 2: {"type": "play", "card_id": 21, "sign": 1}}
	_check(not Rules.valid_action(split, 1, {"type": "change", "value": 5}), "change bounded by live player count")
	_check(not Rules.valid_action(split, 1, {"type": "change", "value": 2.5}), "change requires integer points")
	_check(Rules.preview_delta(split, actions) == 3, "preview excludes super")
	var signed_actions: Dictionary = actions.duplicate(true)
	signed_actions[1]["sign"] = -1
	_check(Rules.preview_delta(split, signed_actions) == -1, "change can subtract points")
	_check(not Rules.valid_action(split, 1, {"type": "change", "value": 2, "sign": 0}), "change requires a valid direction")
	_check(not Rules.finish_round(split, actions, [4, 4])["ok"], "duplicate super rejected before consumption")
	_check(Economy.owns(split, 1, "change") and Economy.owns(split, 4, "super"), "failed validation changes nothing")
	var result: Dictionary = Rules.finish_round(split, actions, [4])
	_check(result["ok"] and result["stats_valid"], "special cards preserve normal hand statistics")
	_check(result["delta"] == 4 and result["super_count"] == 1 and result["eliminated"] == 3, "super changes final target")
	_check(result["super_users"] == [4] and result["public"]["hidden_card_counts"] == {1: 0, 2: 0, 4: 0},
		"settlement reveals the super user and updates hidden counts")
	_check(result["reward_steps"] == 4 and result["play_reward"] == 40, "full rotations use n reward steps")
	_check(split["balances"] == {1: 558, 2: 657, 4: 157}, "three surviving card users split 52r with deterministic remainder")
	_check(not Economy.owns(split, 1, "change") and not Economy.owns(split, 4, "super"), "change and super consumed")

	var dead_player: Dictionary = Rules.make_state([1, 2, 3])
	dead_player["initial_index"] = 0
	dead_player["hands"][1] = [{"id": 11, "value": 2}]
	dead_player["hands"][2] = [{"id": 21, "value": 1}]
	dead_player["issued"] = {1: 1, 2: 1}
	result = Rules.finish_round(dead_player, {1: {"type": "play", "card_id": 11, "sign": 1},
		2: {"type": "play", "card_id": 21, "sign": 1}})
	_check(result["eliminated"] == 1 and dead_player["balances"] == {2: 160, 3: 50}, "eliminated card user shares balance including earned reward")
	_check(Economy.rotation_steps(-5, 4) == 1 and Economy.rotation_steps(0, 4) == 1, "signed and zero rotation reward tiers")

	var nonce: String = Commit.create_nonce()
	var commitment: String = Commit.compute(1, 1, 2, {"type": "change", "value": 2}, nonce)
	_check(Commit.valid_reveal(commitment, 1, 1, 2, {"type": "change", "value": 2}, nonce), "change action validates")
	_check(not Commit.valid_reveal(commitment, 1, 1, 2, {"type": "change", "value": 3}, nonce), "change points are committed")
	_check(not Commit.valid_reveal(commitment, 1, 1, 2, {"type": "change", "value": 2, "sign": -1}, nonce), "change direction is committed")
	if failures == 0:
		print("TURN_ECONOMY_OK")
	quit(0 if failures == 0 else 2)
