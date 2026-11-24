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
	return purchase_many(state, id, {kind: 1})

static func purchase_many(state: Dictionary, id: int, order: Dictionary) -> bool:
	if not state.get("alive", []).has(id) or order.is_empty():
		return false
	var prices: Dictionary = state["economy"]["prices"]
	var cards: Dictionary = state["special_cards"][id]
	var capacity := 0x7fff_ffff_ffff_ffff
	for held in cards.values():
		capacity -= int(held)
	var balance: int = state["balances"][id]
	for kind in order:
		var quantity: Variant = order[kind]
		var price: int = prices.get(kind, -1)
		if not quantity is int or quantity <= 0 or price < 0:
			return false
		if quantity > capacity:
			return false
		capacity -= quantity
		@warning_ignore("integer_division")
		if price > balance / quantity:
			return false
		balance -= price * quantity
	state["balances"][id] = balance
	for kind in order:
		cards[kind] = int(cards.get(kind, 0)) + order[kind]
	return true

static func consume(state: Dictionary, id: int, kind: String) -> void:
	state["special_cards"][id][kind] -= 1

static func rotation_steps(delta: int, player_count: int) -> int:
	# 完整一圈按 n 计，零位移按最低一格奖励档计。
	return 1 if delta == 0 else posmod(absi(delta) - 1, player_count) + 1

static func pay_round(state: Dictionary, card_players: Dictionary, hit_peer: int, steps: int, keep_seat: bool = false) -> int:
	if hit_peer == 0:
		return 0
	var balances: Dictionary = state["balances"]
	var reward: int = 0 if card_players.is_empty() else int(state["economy"]["play_reward_rate"]) * steps
	for id in card_players:
		balances[id] += reward

	var recipients: Array = []
	for id in state["alive"]:
		if id != hit_peer and card_players.has(id):
			recipients.append(id)
	if not recipients.is_empty():
		@warning_ignore("integer_division")
		var inheritance: int = int(balances[hit_peer]) * int(state["economy"]["inheritance_percent"]) / 100
		@warning_ignore("integer_division")
		var share: int = inheritance / recipients.size()
		var remainder: int = inheritance % recipients.size()
		for index in range(recipients.size()):
			balances[recipients[index]] += share + int(index < remainder)
	if keep_seat:
		balances[hit_peer] = 0
	else:
		balances.erase(hit_peer)
		state["special_cards"].erase(hit_peer)
	return reward
