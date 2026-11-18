extends RefCounted
## TURN 的纯规则层。无节点、网络或动画依赖。
const Economy = preload("res://scripts/core/economy.gd")
const MAX_PLAYERS := 12
const MAX_INITIAL_LIVES := 5

static func make_state(player_ids: Array, initial_lives: int = 1, economy: Dictionary = {}) -> Dictionary:
	var hands: Dictionary = {}
	var lives: Dictionary = {}
	var starting_lives: int = clampi(initial_lives, 1, MAX_INITIAL_LIVES)
	for raw_id in player_ids:
		hands[int(raw_id)] = []
		lives[int(raw_id)] = starting_lives
	var state: Dictionary = {
		"alive": player_ids.duplicate(),
		"hands": hands,
		"lives": lives,
		"initial_lives": starting_lives,
		"round": 0,
		"initial_index": -1,
		"next_card_id": 1,
		"issued": {},
		"played": {},
		"discarded": {},
		"phase": "waiting"
	}
	Economy.initialize(state, economy)
	return state

static func add_count(counts: Dictionary, value: int, amount: int = 1) -> void:
	counts[value] = int(counts.get(value, 0)) + amount

static func begin_round(state: Dictionary, rng: RandomNumberGenerator) -> void:
	var alive: Array = state["alive"]
	var count: int = alive.size()
	if count < 2:
		return
	state["round"] = int(state["round"]) + 1
	for peer_id in alive:
		var value: int = rng.randi_range(1, count)
		var card_id: int = int(state["next_card_id"])
		state["next_card_id"] = card_id + 1
		var hand: Array = state["hands"][peer_id]
		hand.append({"id": card_id, "value": value})
		add_count(state["issued"], value)
	state["initial_index"] = rng.randi_range(0, count - 1)
	state["phase"] = "choosing"

static func valid_action(state: Dictionary, peer_id: int, action: Dictionary, private_cards: Dictionary = {}) -> bool:
	var alive: Array = state.get("alive", [])
	if not alive.has(peer_id):
		return false
	var kind: String = str(action.get("type", ""))
	if kind == "pass":
		return true
	if kind in ["defense", "change"]:
		var inventory: Dictionary = state.get("special_cards", {}).get(peer_id, private_cards)
		if int(inventory.get(kind, 0)) < 1:
			return false
		if kind == "defense":
			return true
		var value: Variant = action.get("value")
		var direction: Variant = action.get("sign", 1)
		return value is int and value >= 1 and value <= alive.size() and direction is int and direction in [1, -1]
	if kind != "play":
		return false
	var sign_value: Variant = action.get("sign")
	var wanted_id: Variant = action.get("card_id")
	if not sign_value is int or sign_value not in [1, -1] or not wanted_id is int:
		return false
	var hand: Array = state["hands"].get(peer_id, [])
	for card in hand:
		if int(card["id"]) == wanted_id:
			return true
	return false

static func public_state(state: Dictionary) -> Dictionary:
	var hands: Dictionary = {}
	var lives: Dictionary = {}
	for peer_id in state["alive"]:
		hands[peer_id] = state["hands"][peer_id].duplicate(true)
		lives[peer_id] = int(state["lives"][peer_id])
	return {
		"alive": state["alive"].duplicate(),
		"hands": hands,
		"lives": lives,
		"initial_lives": state["initial_lives"],
		"hidden_card_counts": Economy.hidden_card_counts(state),
		"round": state["round"],
		"initial_index": state["initial_index"],
		"stats": statistics(state),
		"phase": state["phase"]
	}

static func statistics(state: Dictionary) -> Dictionary:
	var held: Dictionary = {}
	for peer_id in state["alive"]:
		for card in state["hands"][peer_id]:
			add_count(held, int(card["value"]))
	var by_value: Dictionary = {}
	var total_issued := 0
	var total_played := 0
	var total_discarded := 0
	var total_held := 0
	for value in state["issued"].keys():
		var i: int = int(state["issued"][value])
		var p: int = int(state["played"].get(value, 0))
		var d: int = int(state["discarded"].get(value, 0))
		var h: int = int(held.get(value, 0))
		by_value[int(value)] = {"issued": i, "played": p, "discarded": d, "held": h}
		total_issued += i
		total_played += p
		total_discarded += d
		total_held += h
	return {
		"issued": total_issued, "played": total_played,
		"discarded": total_discarded, "held": total_held, "by_value": by_value
	}

static func stats_hold(state: Dictionary) -> bool:
	var stats: Dictionary = statistics(state)
	if int(stats["issued"]) != int(stats["played"]) + int(stats["discarded"]) + int(stats["held"]):
		return false
	for entry in stats["by_value"].values():
		if int(entry["issued"]) != int(entry["played"]) + int(entry["discarded"]) + int(entry["held"]):
			return false
	return true

static func preview_delta(state: Dictionary, actions: Dictionary) -> int:
	return _movement(_round_actions(state, actions))

static func _movement(detail: Array) -> int:
	var delta: int = 0
	for item in detail:
		delta += int(item.get("value", 0)) * int(item.get("sign", 0))
	return delta

static func _round_actions(state: Dictionary, actions: Dictionary) -> Array:
	var detail: Array = []
	for id in state["alive"]:
		var action: Dictionary = actions.get(id, {"type": "pass"})
		if not valid_action(state, id, action):
			return []
		var kind: String = action["type"]
		if kind == "play":
			var card_id: int = int(action["card_id"])
			for card in state["hands"][id]:
				if int(card["id"]) == card_id:
					detail.append({"peer_id": id, "type": kind, "card_id": card_id,
						"value": card["value"], "sign": action["sign"]})
					break
		elif kind == "change":
			detail.append({"peer_id": id, "type": kind, "value": action["value"], "sign": action.get("sign", 1)})
		else:
			detail.append({"peer_id": id, "type": kind})
	return detail

static func _consume_played_cards(state: Dictionary, detail: Array) -> void:
	for item in detail:
		var id: int = int(item["peer_id"])
		var kind: String = item["type"]
		if kind == "play":
			var hand: Array = state["hands"][id]
			for index in range(hand.size()):
				if int(hand[index]["id"]) == int(item["card_id"]):
					add_count(state["played"], int(item["value"]))
					hand.remove_at(index)
					break
		elif kind in ["defense", "change"]:
			Economy.consume(state, id, kind)

static func finish_round(state: Dictionary, actions: Dictionary, super_players: Array = []) -> Dictionary:
	var alive: Array = state["alive"]
	var count: int = alive.size()
	if count < 2:
		return {"ok": false, "error": "人数不足"}
	var detail: Array = _round_actions(state, actions)
	if detail.is_empty():
		return {"ok": false, "error": "行动或特殊牌无效"}

	var card_players: Dictionary = {}
	for item in detail:
		if item["type"] != "pass":
			card_players[item["peer_id"]] = true
	var used_super: Dictionary = {}
	for id in super_players:
		if used_super.has(id) or not alive.has(id) or not Economy.owns(state, id, "super"):
			return {"ok": false, "error": "超级卡无效"}
		used_super[id] = true
		card_players[id] = true

	var delta: int = _movement(detail) + used_super.size() * int(state["economy"]["super_steps"])
	var initial_index: int = int(state["initial_index"])
	var target_index: int = posmod(initial_index + delta, count)
	var hit_peer: int = int(alive[target_index])
	var previous_lives: int = int(state["lives"][hit_peer])
	var defended: bool = previous_lives == 1 and detail[target_index]["type"] == "defense"
	var remaining_lives: int = previous_lives - int(not defended)
	state["lives"][hit_peer] = remaining_lives
	var eliminated: int = hit_peer if remaining_lives == 0 else 0

	_consume_played_cards(state, detail)
	for id in used_super:
		Economy.consume(state, id, "super")
	if eliminated != 0:
		var eliminated_hand: Array = state["hands"][eliminated]
		for card in eliminated_hand:
			add_count(state["discarded"], int(card["value"]))
		eliminated_hand.clear()
		alive.erase(eliminated)
	var reward_steps: int = Economy.rotation_steps(delta, count)
	var reward: int = Economy.pay_round(state, card_players, eliminated, reward_steps)
	state["phase"] = "ended" if alive.size() == 1 else "result"
	return {
		"ok": true, "round": state["round"], "initial_index": initial_index,
		"target_index": target_index, "delta": delta,
		"hit_peer": hit_peer, "remaining_lives": remaining_lives, "defended": defended,
		"eliminated": eliminated, "super_count": used_super.size(), "super_users": used_super.keys(),
		"reward_steps": reward_steps, "play_reward": reward,
		"winner": int(alive[0]) if alive.size() == 1 else 0,
		"actions": detail, "public": public_state(state),
		"stats_valid": stats_hold(state)
	}
