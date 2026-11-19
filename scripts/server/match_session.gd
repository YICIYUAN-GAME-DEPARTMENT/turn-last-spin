extends Node

signal room_update(kind: String, payload: Dictionary)
signal player_update(peer_id: int, kind: String, payload: Dictionary)

const Rules = preload("res://scripts/core/game_rules.gd")
const CHOOSE_SECONDS := 15.0
const NEXT_ROUND_DELAY := 2.5

var _match_id := 0
var _state: Dictionary = {}
var _actions: Dictionary = {}
var _offline: Dictionary = {}
var _round_public: Dictionary = {}
var _last_result: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _timer := Timer.new()
var _deadline_ms := 0

func _ready() -> void:
	_rng.randomize()
	_timer.one_shot = true
	add_child(_timer)
	_timer.timeout.connect(_on_timer)

func start(match_id: int, player_ids: Array, initial_lives: int) -> void:
	_match_id = match_id
	_state = Rules.make_state(player_ids, initial_lives)
	_begin_round()

func is_finished() -> bool:
	return _state.get("phase") in ["ended", "aborted"]

func submit_action(peer_id: int, payload: Dictionary) -> void:
	var round_id = payload.get("round")
	var match_id = payload.get("match_id")
	var action = payload.get("action")
	if _state.get("phase") != "choosing" or Time.get_ticks_msec() >= _deadline_ms \
			or match_id != _match_id or round_id != _state["round"] or _offline.has(peer_id):
		_reject(peer_id, payload, "此回合已结束或不可操作。")
		return
	if _actions.has(peer_id):
		_acknowledge(peer_id)
		return
	if not action is Dictionary or not _has_action_fields(action) or not Rules.valid_action(_state, peer_id, action):
		_reject(peer_id, payload, "行动无效，请选择自己持有的牌。")
		return
	if action["type"] == "play":
		_actions[peer_id] = {"type": "play", "card_id": action["card_id"], "sign": action["sign"]}
	else:
		_actions[peer_id] = {"type": "pass"}
	_acknowledge(peer_id)
	room_update.emit("confirmed_count", {"count": _actions.size()})
	_finish_if_ready()

func player_disconnected(peer_id: int) -> void:
	_offline[peer_id] = true
	if _state["phase"] == "choosing":
		_finish_if_ready()

func player_reconnected(player_id: int) -> void:
	_offline.erase(player_id)

func snapshot_for(player_id: int) -> Dictionary:
	return {
		"match_id": _match_id, "phase": _state["phase"], "public": Rules.public_state(_state),
		"remaining_ms": maxi(0, _deadline_ms - Time.get_ticks_msec()),
		"confirmed_count": _actions.size(), "locked": _actions.has(player_id),
		"last_result": _last_result
	}

func _has_action_fields(action: Dictionary) -> bool:
	return action.get("type") == "pass" or (
		action.get("type") == "play" and action.get("card_id") is int and action.get("sign") is int
	)

func _acknowledge(peer_id: int) -> void:
	player_update.emit(peer_id, "action_ack", {"match_id": _match_id, "round": _state["round"]})

func _reject(peer_id: int, payload: Dictionary, message: String) -> void:
	player_update.emit(peer_id, "action_rejected", {
		"match_id": payload.get("match_id"), "round": payload.get("round"), "message": message
	})

func _begin_round() -> void:
	Rules.begin_round(_state, _rng)
	_actions.clear()
	_last_result = {}
	_round_public = Rules.public_state(_state)
	_deadline_ms = Time.get_ticks_msec() + int(CHOOSE_SECONDS * 1000.0)
	_timer.start(CHOOSE_SECONDS)
	room_update.emit("round_started", {
		"match_id": _match_id, "public": _round_public, "duration": CHOOSE_SECONDS
	})
	_finish_if_ready()

func _finish_if_ready() -> void:
	for peer_id in _state["alive"]:
		if not _offline.has(peer_id) and not _actions.has(peer_id):
			return
	_finish_round()

func _finish_round() -> void:
	if _state["phase"] != "choosing":
		return
	_timer.stop()
	# 规则层会把缺席的行动视为 PASS。
	var outcome := Rules.finish_round(_state, _actions)
	if not outcome.get("ok", false) or not outcome.get("stats_valid", false):
		_state["phase"] = "aborted"
		push_error("TURN_MATCH_ABORT match=%d round=%d" % [_match_id, _state["round"]])
		room_update.emit("aborted", {"message": "结算异常，本局结束。"})
		return
	outcome["match_id"] = _match_id
	var played_cards: Dictionary = {}
	for action in outcome["actions"]:
		if action["type"] == "play":
			played_cards[action["card_id"]] = true
	_round_public["played_cards"] = played_cards
	_round_public["lives"][outcome["hit_peer"]] = outcome["remaining_lives"]
	_round_public["target_index"] = outcome["target_index"]
	outcome["wheel"] = _round_public
	_last_result = outcome
	room_update.emit("round_result", outcome)
	print("TURN_ROUND match=%d round=%d hit=%d eliminated=%d winner=%d stats_ok=true" % [
		_match_id, outcome["round"], outcome["hit_peer"], outcome["eliminated"], outcome["winner"]
	])
	if _state["phase"] == "result":
		_timer.start(NEXT_ROUND_DELAY)

func _on_timer() -> void:
	if _state["phase"] == "choosing":
		_finish_round()
	elif _state["phase"] == "result":
		_begin_round()
