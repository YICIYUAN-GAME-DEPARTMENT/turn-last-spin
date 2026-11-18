extends RefCounted
## TURN 的纯规则层。无节点、网络或动画依赖。
const MAX_PLAYERS := 12
const MAX_INITIAL_LIVES := 5

static func make_state(player_ids: Array, initial_lives: int = 1) -> Dictionary:
	var hands: Dictionary = {}
	var lives: Dictionary = {}
	var starting_lives: int = clampi(initial_lives, 1, MAX_INITIAL_LIVES)
	for raw_id in player_ids:
		hands[int(raw_id)] = []
		lives[int(raw_id)] = starting_lives
	return {
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

static func valid_action(state: Dictionary, peer_id: int, action: Dictionary) -> bool:
	var alive: Array = state.get("alive", [])
	if not alive.has(peer_id):
		return false
	var kind: String = str(action.get("type", ""))
	if kind == "pass":
		return true
	if kind != "play":
		return false
	var sign_value: int = int(action.get("sign", 0))
	if sign_value != 1 and sign_value != -1:
		return false
	var wanted_id: int = int(action.get("card_id", -1))
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

static func finish_round(state: Dictionary, actions: Dictionary) -> Dictionary:
	var alive: Array = state["alive"]
	var count: int = alive.size()
	if count < 2:
		return {"ok": false, "error": "人数不足"}
	var delta: int = 0
	var detail: Array = []
	# 先校验全部动作；校验完成之前不修改任何手牌。
	for peer_id in alive:
		var action: Dictionary = actions.get(peer_id, {"type": "pass"})
		if not valid_action(state, int(peer_id), action):
			return {"ok": false, "error": "非法行动: %s" % str(peer_id)}
		if str(action["type"]) == "pass":
			detail.append({"peer_id": peer_id, "type": "pass"})
			continue
		var card_value: int = -1
		for card in state["hands"][peer_id]:
			if int(card["id"]) == int(action["card_id"]):
				card_value = int(card["value"])
				break
		delta += card_value * int(action["sign"])
		detail.append({
			"peer_id": peer_id, "type": "play",
			"card_id": int(action["card_id"]), "value": card_value,
			"sign": int(action["sign"])
		})
	var initial_index: int = int(state["initial_index"])
	var target_index: int = posmod(initial_index + delta, count)
	var hit_peer: int = int(alive[target_index])
	var remaining_lives: int = maxi(0, int(state["lives"][hit_peer]) - 1)
	state["lives"][hit_peer] = remaining_lives
	var eliminated: int = hit_peer if remaining_lives == 0 else 0
	# 先把所有出牌计入 PLAYED；只有生命归零才弃掉其余手牌。
	for item in detail:
		if item["type"] != "play":
			continue
		var hand: Array = state["hands"][item["peer_id"]]
		for i in range(hand.size()):
			if int(hand[i]["id"]) == int(item["card_id"]):
				add_count(state["played"], int(hand[i]["value"]))
				hand.remove_at(i)
				break
	if eliminated != 0:
		var eliminated_hand: Array = state["hands"][eliminated]
		for card in eliminated_hand:
			add_count(state["discarded"], int(card["value"]))
		eliminated_hand.clear()
		alive.erase(eliminated)
	state["phase"] = "ended" if alive.size() == 1 else "result"
	return {
		"ok": true, "round": state["round"], "initial_index": initial_index,
		"target_index": target_index, "delta": delta,
		"hit_peer": hit_peer, "remaining_lives": remaining_lives,
		"eliminated": eliminated,
		"winner": int(alive[0]) if alive.size() == 1 else 0,
		"actions": detail, "public": public_state(state),
		"stats_valid": stats_hold(state)
	}
