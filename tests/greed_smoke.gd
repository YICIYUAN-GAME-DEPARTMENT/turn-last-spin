extends SceneTree

const Rules = preload("res://scripts/core/game_rules.gd")
const Economy = preload("res://scripts/core/economy.gd")
const Settings = preload("res://scripts/core/economy_settings.gd")
var failures: int = 0

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
		push_error(detail)

func _initialize() -> void:
	var settings := Settings.new()
	var values: Dictionary = settings.values()
	var game := Rules.make_state([4, 3, 2, 1], 3, values, Rules.Mode.GREED)
	check(game.lives.is_empty() and Rules.public_state(game).lives.is_empty(), "no HP in greed mode")
	check(game.economy.prices == {"change": 50, "defense": 50, "super": 250}, "discounted prices")
	check(values.prices.super == 500, "base configuration remains reusable")
	check(Economy.purchase(game, 4, "defense") and game.balances[4] == 0, "purchase at half price")
	check(not Economy.purchase(game, 4, "change"), "cannot overspend")
	game.initial_index = 0
	game.balances[4] = 800
	var result := Rules.finish_round(game, {4: {"type": "defense"}})
	check(result.defended and game.balances[4] == 800 and game.ranking.is_empty(), "shield protects wallet")
	check(not Economy.owns(game, 4, "defense"), "shield consumed")
	check(Economy.purchase(game, 4, "change"), "target owns a spare item")
	game.hands[4] = [{"id": 1, "value": 1}]
	game.issued = {1: 1}
	result = Rules.finish_round(game, {})
	check(game.balances[4] == 0 and game.alive.size() == 4, "unprotected hit resets balance, even with no card users")
	check(game.hands[4].size() == 1 and Economy.owns(game, 4, "change"), "hit keeps hand and items")

	# Seat 4 receives exactly 1000; seat 3 receives 999. The hit seat passes.
	game.balances = {4: 985, 3: 985, 2: 9, 1: 10}
	game.special_cards[4] = {"change": 1}
	game.special_cards[3] = {"change": 1}
	game.initial_index = 2
	var actions := {4: {"type": "change", "value": 1, "sign": 1}, 3: {"type": "change", "value": 1, "sign": -1}}
	result = Rules.finish_round(game, actions)
	check(game.balances == {4: 1000, 3: 999, 2: 0, 1: 10}, "reward and remainder paid before checking goal")
	check(result.winner == 0 and game.phase == "result" and game.ranking == [4], "early winner leaves; match continues")
	check(not Economy.purchase(game, 4, "change") and not Rules.valid_action(game, 4, {"type": "pass"}), "ranked seat can only watch")
	Rules.begin_round(game, RandomNumberGenerator.new())
	check(game.alive == [3, 2, 1] and game.hands[4].is_empty(), "next round only deals to remaining seats")
	game.initial_index = 0
	game.balances[2] = 999
	game.special_cards[3] = {"super": 1}
	game.special_cards[2] = {"super": 1}
	result = Rules.finish_round(game, {}, [2, 3])
	check(result.hit_peer == 1 and result.delta == 2, "super cards affect target and qualify for coins")
	check(game.ranking == [4, 3, 2, 1] and result.public.ranking == game.ranking, "simultaneous finishers ordered by seat, last seat ranked")
	check(game.alive.is_empty() and result.winner == 4 and result.stats_valid, "complete ranking preserves original winner and card counts")
	var round_number: int = game.round
	Rules.begin_round(game, RandomNumberGenerator.new())
	check(game.round == round_number, "no extra round for last seat")
	values.starting_balance = Rules.COIN_GOAL
	var finished := Rules.make_state([2, 1], 1, values, Rules.Mode.GREED)
	check(finished.phase == "ended" and finished.ranking == [2, 1], "starting balances can already reach the goal")
	if failures == 0:
		print("TURN_GREED_OK")
	quit(0 if failures == 0 else 2)
