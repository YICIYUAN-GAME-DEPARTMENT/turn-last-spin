extends RefCounted
## 对局货币与暗牌库存。钱包只存在于权威状态。

const Settings = preload("res://scripts/core/economy_settings.gd")

static func initialize(state: Dictionary, values: Dictionary) -> void:
	state["economy"] = Settings.new().values() if values.is_empty() else values.duplicate(true)
	state["balances"] = {}
	state["special_cards"] = {}
	for id in state["alive"]:
		state["balances"][id] = state["economy"]["starting_balance"]
		state["special_cards"][id] = {}

static func wallet(state: Dictionary, id: int) -> Dictionary:
	return {
		"balance": state["balances"].get(id, 0),
		"cards": state["special_cards"].get(id, {}).duplicate()
	}

static func owns(state: Dictionary, id: int, kind: String) -> bool:
	return int(state["special_cards"].get(id, {}).get(kind, 0)) > 0

static func hidden_card_counts(state: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for id in state["alive"]:
		var total: int = 0
		for amount in state["special_cards"].get(id, {}).values():
			total += int(amount)
		counts[id] = total
	return counts

static func purchase(state: Dictionary, id: int, kind: String) -> bool:
	if not state.get("alive", []).has(id):
		return false
	var price: int = int(state["economy"]["prices"].get(kind, -1))
	if price < 0 or int(state["balances"][id]) < price:
		return false
	state["balances"][id] -= price
	var cards: Dictionary = state["special_cards"][id]
	cards[kind] = int(cards.get(kind, 0)) + 1
	return true

static func consume(state: Dictionary, id: int, kind: String) -> void:
	state["special_cards"][id][kind] -= 1

static func rotation_steps(delta: int, player_count: int) -> int:
	# 完整一圈按 n 计，零位移按最低一格奖励档计。
	return 1 if delta == 0 else posmod(absi(delta) - 1, player_count) + 1

static func pay_round(state: Dictionary, card_players: Dictionary, eliminated: int, steps: int) -> int:
	if eliminated == 0:
		return 0
	var balances: Dictionary = state["balances"]
	var reward: int = 0 if card_players.is_empty() else int(state["economy"]["play_reward_rate"]) * steps
	for id in card_players:
		balances[id] += reward

	var recipients: Array = []
	for id in state["alive"]:
		if card_players.has(id):
			recipients.append(id)
	if not recipients.is_empty():
		@warning_ignore("integer_division")
		var inheritance: int = int(balances[eliminated]) * int(state["economy"]["inheritance_percent"]) / 100
		@warning_ignore("integer_division")
		var share: int = inheritance / recipients.size()
		var remainder: int = inheritance % recipients.size()
		for index in range(recipients.size()):
			balances[recipients[index]] += share + int(index < remainder)
	balances.erase(eliminated)
	state["special_cards"].erase(eliminated)
	return reward
