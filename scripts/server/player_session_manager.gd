extends Node

signal player_expired(player_id: int)

const RESUME_SECONDS := 60
const ROOM_REQUEST_LIMIT := 8
const ROOM_REQUEST_WINDOW_MS := 5000

class Session:
	var player_id: int
	var peer_id: int
	var token_digest: String
	var expires_at_ms: int
	var room_window_ms: int
	var room_requests: int

var _crypto := Crypto.new()
var _next_player_id := 1
var _by_player: Dictionary = {}
var _by_peer: Dictionary = {}
var _by_token: Dictionary = {}

func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(_expire_sessions)

func open(peer_id: int, resume_token: String) -> Dictionary:
	if resume_token.is_empty():
		var token := _crypto.generate_random_bytes(32).hex_encode()
		if token.is_empty():
			return {}
		var session := Session.new()
		session.player_id = _next_player_id
		_next_player_id += 1
		session.token_digest = token.sha256_text()
		_by_player[session.player_id] = session
		_by_token[session.token_digest] = session
		_bind(session, peer_id)
		return {"player_id": session.player_id, "resume_token": token}
	if resume_token.length() != 64:
		return {}
	var existing: Session = _by_token.get(resume_token.sha256_text())
	# 不把一个仍在线的会话交给第二条连接。
	if existing == null:
		return {}
	if existing.peer_id != 0:
		return {"busy": true}
	if Time.get_ticks_msec() >= existing.expires_at_ms:
		return {}
	_bind(existing, peer_id)
	return {"player_id": existing.player_id}

func player_for(peer_id: int) -> int:
	var session: Session = _by_peer.get(peer_id)
	return 0 if session == null else session.player_id

func peer_for(player_id: int) -> int:
	var session: Session = _by_player.get(player_id)
	return 0 if session == null else session.peer_id

func detach_peer(peer_id: int) -> int:
	var session: Session = _by_peer.get(peer_id)
	if session == null:
		return 0
	_by_peer.erase(peer_id)
	session.peer_id = 0
	session.expires_at_ms = Time.get_ticks_msec() + RESUME_SECONDS * 1000
	return session.player_id

func allow_room_request(player_id: int) -> bool:
	var session: Session = _by_player[player_id]
	var now := Time.get_ticks_msec()
	if now >= session.room_window_ms:
		session.room_requests = 0
		session.room_window_ms = now + ROOM_REQUEST_WINDOW_MS
	session.room_requests += 1
	return session.room_requests <= ROOM_REQUEST_LIMIT

func _bind(session: Session, peer_id: int) -> void:
	session.peer_id = peer_id
	session.expires_at_ms = 0
	_by_peer[peer_id] = session

func _expire_sessions() -> void:
	var now := Time.get_ticks_msec()
	for player_id in _by_player.keys():
		var session: Session = _by_player[player_id]
		if session.peer_id == 0 and now >= session.expires_at_ms:
			_by_token.erase(session.token_digest)
			_by_player.erase(player_id)
			player_expired.emit(player_id)
