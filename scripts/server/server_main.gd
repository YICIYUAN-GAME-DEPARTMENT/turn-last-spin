extends Node

const NetBridge = preload("res://scripts/network/net_bridge.gd")
const PlayerSessions = preload("res://scripts/server/player_session_manager.gd")
const MAX_CLIENTS := 32
const HELLO_TIMEOUT := 5.0

@onready var _net = $Net
@onready var _rooms = $Rooms
var _sessions := PlayerSessions.new()
var _connected_peers: Dictionary = {}

func _ready() -> void:
	var options := _read_options()
	if options.is_empty():
		get_tree().quit(1)
		return
	add_child(_sessions)
	_sessions.player_expired.connect(_rooms.player_expired)
	_rooms.room_event.connect(_send_room_event)
	_net.server_command.connect(_handle_command)
	_net.peer_joined.connect(_handle_connected)
	_net.peer_left.connect(_handle_disconnect)
	var result: Error = _net.start_server(options["port"], options["tls"])
	if result != OK:
		push_error("专服无法监听 TCP %d：%s" % [options["port"], error_string(result)])
		get_tree().quit(1)
		return
	print("TURN_SERVER_READY port=%d protocol=%d transport=%s" % [
		options["port"], NetBridge.PROTOCOL_VERSION, "WSS" if options["tls"] != null else "WS"
	])

func _read_options() -> Dictionary:
	var port := NetBridge.DEFAULT_PORT
	var cert_path := ""
	var key_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--turn-port="):
			port = int(arg.trim_prefix("--turn-port="))
		elif arg.begins_with("--turn-wss-cert="):
			cert_path = arg.trim_prefix("--turn-wss-cert=")
		elif arg.begins_with("--turn-wss-key="):
			key_path = arg.trim_prefix("--turn-wss-key=")
	if port < 1 or port > 65535:
		push_error("专服端口必须在 1～65535。")
		return {}
	if cert_path.is_empty() and key_path.is_empty():
		return {"port": port, "tls": null}
	var certificate := X509Certificate.new()
	var key := CryptoKey.new()
	if cert_path.is_empty() or key_path.is_empty() or certificate.load(cert_path) != OK or key.load(key_path) != OK:
		push_error("启动 WSS 需要有效的证书和私钥。")
		return {}
	return {"port": port, "tls": TLSOptions.server(key, certificate)}

func _handle_connected(peer_id: int) -> void:
	if _connected_peers.size() >= MAX_CLIENTS:
		_net.disconnect_peer(peer_id)
		return
	_connected_peers[peer_id] = true
	get_tree().create_timer(HELLO_TIMEOUT).timeout.connect(func():
		if _connected_peers.has(peer_id) and _sessions.player_for(peer_id) == 0:
			_connected_peers.erase(peer_id)
			_net.disconnect_peer(peer_id)
	)

func _handle_command(peer_id: int, kind: String, payload: Dictionary) -> void:
	if not _connected_peers.has(peer_id):
		return
	var player_id := _sessions.player_for(peer_id)
	if player_id == 0:
		if kind == "hello":
			_open_session(peer_id, payload)
		return
	if kind in ["create_room", "join_room"] and not _sessions.allow_room_request(player_id):
		_net.send_event(peer_id, "error", {"message": "房间操作太频繁，请稍后再试。"})
		return
	_rooms.handle_command(player_id, kind, payload)

func _open_session(peer_id: int, payload: Dictionary) -> void:
	if payload.get("version") != NetBridge.PROTOCOL_VERSION:
		_net.send_event(peer_id, "incompatible", {})
		return
	var token = payload.get("resume_token", "")
	if not token is String:
		return
	var session := _sessions.open(peer_id, token)
	if session.is_empty():
		_net.send_event(peer_id, "resume_rejected", {})
		return
	if session.has("busy"):
		_net.send_event(peer_id, "resume_busy", {})
		return
	_net.send_event(peer_id, "server_ready", session)
	if not token.is_empty():
		_rooms.player_reconnected(session["player_id"])

func _handle_disconnect(peer_id: int) -> void:
	_connected_peers.erase(peer_id)
	var player_id := _sessions.detach_peer(peer_id)
	if player_id != 0:
		_rooms.player_disconnected(player_id)

func _send_room_event(player_id: int, kind: String, payload: Dictionary) -> void:
	var peer_id := _sessions.peer_for(player_id)
	if peer_id != 0:
		_net.send_event(peer_id, kind, payload)
