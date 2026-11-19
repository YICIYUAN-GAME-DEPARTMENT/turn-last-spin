extends Node

signal room_event(player_id: int, kind: String, payload: Dictionary)

const Rules = preload("res://scripts/core/game_rules.gd")
const MatchSession = preload("res://scripts/server/match_session.gd")
const CODE_LENGTH := 6
const CODE_ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"

class Room:
	var code: String
	var owner_id: int
	var members: Dictionary = {}
	var initial_lives := 1
	var game_mode: Rules.Mode = Rules.Mode.CLASSIC
	var match_session: MatchSession

var _rooms: Dictionary = {}
var _player_rooms: Dictionary = {}
var _next_match_id := 1

func handle_command(player_id: int, kind: String, payload: Dictionary) -> void:
	var room: Room = _player_rooms.get(player_id)
	if kind in ["create_room", "join_room"]:
		if room != null:
			_error(player_id, "你已经在房间中。")
		else:
			_enter_room(player_id, kind, payload.get("code"))
		return
	if room == null or payload.get("code") != room.code:
		_error(player_id, "你不在此房间。")
		return
	match kind:
		"ready":
			if room.match_session == null and payload.get("ready") is bool:
				room.members[player_id]["ready"] = payload["ready"]
				_publish_lobby(room)
		"initial_lives":
			if room.match_session == null and player_id == room.owner_id and payload.get("lives") is int:
				room.initial_lives = clampi(payload["lives"], 1, Rules.MAX_INITIAL_LIVES)
				_publish_lobby(room)
		"game_mode":
			if room.match_session == null and player_id == room.owner_id and payload.get("mode") is int and payload["mode"] in Rules.Mode.values():
				room.game_mode = payload["mode"]
				_publish_lobby(room)
		"start":
			_start_match(room, player_id)
		"commit", "reveal", "buy_card", "settlement_choice":
			if room.match_session == null:
				_error(player_id, "当前没有进行中的对局。")
				return
			match kind:
				"commit":
					room.match_session.submit_commit(player_id, payload)
				"reveal":
					room.match_session.submit_reveal(player_id, payload)
				"buy_card":
					room.match_session.purchase(player_id, payload)
				"settlement_choice":
					room.match_session.submit_settlement(player_id, payload)
		"return_lobby":
			if player_id != room.owner_id or room.match_session == null or not room.match_session.is_finished():
				_error(player_id, "只有房主可以在结束后返回大厅。")
				return
			_return_to_lobby(room)
		"leave":
			_remove_member(room, player_id, "已离开房间。")
		"transfer_owner", "remove_member":
			_manage_member(room, player_id, kind, payload.get("target_id"))

func _enter_room(player_id: int, kind: String, raw_code: Variant) -> void:
	var room: Room
	if kind == "create_room":
		room = Room.new()
		room.code = _new_room_code()
		room.owner_id = player_id
		_rooms[room.code] = room
	else:
		if raw_code is String and raw_code.length() == CODE_LENGTH:
			room = _rooms.get(raw_code.to_upper())
		if room == null:
			_error(player_id, "找不到这个房间，请确认房间码。")
			return
		if room.match_session != null:
			_error(player_id, "房间已开局。")
			return
		if room.members.size() >= Rules.MAX_PLAYERS:
			_error(player_id, "房间人数已满。")
			return
	var used_names: Array = []
	for member in room.members.values():
		used_names.append(member["name"])
	var name: String
	for letter in "abcdefghijkl":
		if letter not in used_names:
			name = letter
			break
	room.members[player_id] = {"id": player_id, "name": name, "ready": false, "online": true, "can_resume": true}
	_player_rooms[player_id] = room
	_publish_lobby(room)
	print("TURN_ROOM_JOIN code=%s player=%d players=%d" % [room.code, player_id, room.members.size()])

func _new_room_code() -> String:
	var code := ""
	while code.is_empty() or _rooms.has(code):
		code = ""
		for i in range(CODE_LENGTH):
			code += CODE_ALPHABET[randi_range(0, CODE_ALPHABET.length() - 1)]
	return code

func _start_match(room: Room, player_id: int) -> void:
	if player_id != room.owner_id or room.match_session != null or room.members.size() < 2:
		_error(player_id, "至少两人在大厅，且只有房主能开局。")
		return
	for member in room.members.values():
		if not member["online"] or not member["ready"]:
			_error(player_id, "请等待所有成员在线并准备。")
			return
	var session := MatchSession.new()
	room.match_session = session
	add_child(session)
	session.room_update.connect(_broadcast.bind(room))
	session.player_update.connect(_send_to_player.bind(room))
	var match_id := _next_match_id
	_next_match_id += 1
	session.start(match_id, room.members.keys(), room.initial_lives, room.game_mode)

func player_disconnected(player_id: int) -> void:
	var room: Room = _player_rooms.get(player_id)
	if room == null:
		return
	room.members[player_id]["online"] = false
	room.members[player_id]["ready"] = false
	_update_owner(room)
	_publish_members(room)
	if room.match_session != null:
		room.match_session.player_disconnected(player_id)

func player_reconnected(player_id: int) -> void:
	var room: Room = _player_rooms.get(player_id)
	if room == null:
		return
	room.members[player_id]["online"] = true
	_update_owner(room)
	_publish_members(room)
	if room.match_session != null:
		_send_to_player(player_id, "match_snapshot", room.match_session.snapshot_for(player_id), room)
		room.match_session.player_reconnected(player_id)
	print("TURN_PLAYER_RESUMED player=%d" % player_id)

func player_expired(player_id: int) -> void:
	var room: Room = _player_rooms.get(player_id)
	if room != null:
		_remove_member(room, player_id, "")

func _manage_member(room: Room, player_id: int, kind: String, target: Variant) -> void:
	if player_id != room.owner_id or room.match_session != null:
		_error(player_id, "只有房主可以在大厅管理成员。")
		return
	if not target is int or target == player_id or not room.members.has(target):
		_error(player_id, "请选择房间中的其他成员。")
		return
	if kind == "transfer_owner":
		if not room.members[target]["online"]:
			_error(player_id, "只能将房主转交给在线成员。")
			return
		room.owner_id = target
		_publish_lobby(room)
	else:
		_remove_member(room, target, "你已被房主移出房间。")

func _remove_member(room: Room, player_id: int, message: String) -> void:
	if room.members[player_id]["online"]:
		_send_to_player(player_id, "room_left", {"message": message}, room)
	_player_rooms.erase(player_id)
	if room.match_session == null:
		room.members.erase(player_id)
	else:
		# 正在进行的牌局保留席位，显式离房后该席位不能重连。
		room.members[player_id]["online"] = false
		room.members[player_id]["can_resume"] = false
	_update_owner(room)
	for member in room.members.values():
		if member["online"] or member["can_resume"]:
			_publish_members(room)
			if room.match_session != null:
				room.match_session.player_disconnected(player_id)
			return
	_rooms.erase(room.code)
	if room.match_session != null:
		room.match_session.queue_free()
		room.match_session = null

func _update_owner(room: Room) -> void:
	if room.members.get(room.owner_id, {}).get("online", false):
		return
	for member in room.members.values():
		if member["online"]:
			room.owner_id = member["id"]
			return
	room.owner_id = 0

func _return_to_lobby(room: Room) -> void:
	room.match_session.queue_free()
	room.match_session = null
	for player_id in room.members.keys():
		if not room.members[player_id]["can_resume"]:
			room.members.erase(player_id)
		else:
			room.members[player_id]["ready"] = false
	_publish_lobby(room)

func _publish_members(room: Room) -> void:
	if room.match_session == null:
		_publish_lobby(room)
	else:
		_broadcast("members", _lobby_payload(room), room)

func _publish_lobby(room: Room) -> void:
	_broadcast("lobby", _lobby_payload(room), room)

func _lobby_payload(room: Room) -> Dictionary:
	var members: Array = []
	for member in room.members.values():
		members.append({"id": member["id"], "name": member["name"], "ready": member["ready"], "online": member["online"]})
	return {"code": room.code, "owner_id": room.owner_id, "members": members, "initial_lives": room.initial_lives, "mode": room.game_mode}

func _broadcast(kind: String, payload: Dictionary, room: Room) -> void:
	for player_id in room.members:
		_send_to_player(player_id, kind, payload, room)

func _send_to_player(player_id: int, kind: String, payload: Dictionary, room: Room) -> void:
	if room.members.has(player_id) and room.members[player_id]["online"]:
		room_event.emit(player_id, kind, payload)

func _error(player_id: int, message: String) -> void:
	room_event.emit(player_id, "error", {"message": message})
