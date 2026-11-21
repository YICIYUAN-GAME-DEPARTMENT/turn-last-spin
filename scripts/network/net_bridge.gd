extends Node
## 共用 RPC 入口。开发机使用本地 WS，公网启用 WSS。
signal server_command(peer_id: int, kind: String, payload: Dictionary)
signal client_event(kind: String, payload: Dictionary)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal connected_to_server()
signal connection_error(message: String)
signal server_lost()

const DEFAULT_PORT := 24680
const SERVER_PEER_ID := 1
const PROTOCOL_VERSION := 4

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(func(id: int): peer_left.emit(id))
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)

func start_server(port: int, tls: TLSOptions) -> Error:
	var transport := WebSocketMultiplayerPeer.new()
	transport.inbound_buffer_size = 8192
	transport.max_queued_packets = 128
	var bind_address := "127.0.0.1" if tls == null else "*"
	var result := transport.create_server(port, bind_address, tls)
	if result == OK:
		var scene_multiplayer := multiplayer as SceneMultiplayer
		scene_multiplayer.server_relay = false
		multiplayer.multiplayer_peer = transport
	return result

func connect_to_server(address: String, port: int, trusted_ca: X509Certificate = null) -> void:
	var url := address
	if address in ["127.0.0.1", "localhost"]:
		url = "ws://%s:%d" % [address, port]
	elif not address.begins_with("wss://"):
		# 远程客户端只用加密连接，重连凭证不会经过公网明文。
		url = "wss://%s:%d" % [address, port]
	var transport := WebSocketMultiplayerPeer.new()
	var tls := TLSOptions.client(trusted_ca) if trusted_ca != null else null
	var result := transport.create_client(url, tls)
	if result != OK:
		connection_error.emit("连接初始化失败：%s" % error_string(result))
		return
	multiplayer.multiplayer_peer = transport

func send_command(kind: String, payload: Dictionary) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_receive_server_command.rpc_id(SERVER_PEER_ID, kind, payload)

func send_event(peer_id: int, kind: String, payload: Dictionary) -> void:
	if not multiplayer.is_server() or not multiplayer.get_peers().has(peer_id):
		return
	var transport := multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	var socket := transport.get_peer(peer_id)
	if socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_receive_client_event.rpc_id(peer_id, kind, payload)

func close_connection() -> void:
	var previous := multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if previous != null:
		previous.close()

func disconnect_peer(peer_id: int) -> void:
	multiplayer.multiplayer_peer.disconnect_peer(peer_id)

@rpc("any_peer", "call_remote", "reliable")
func _receive_server_command(kind: String, payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender > SERVER_PEER_ID:
		server_command.emit(sender, kind, payload)

@rpc("authority", "call_remote", "reliable")
func _receive_client_event(kind: String, payload: Dictionary) -> void:
	if not multiplayer.is_server():
		client_event.emit(kind, payload)

func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		_enable_heartbeat(peer_id)
		peer_joined.emit(peer_id)

func _on_connected_to_server() -> void:
	_enable_heartbeat(SERVER_PEER_ID)
	connected_to_server.emit()

func _enable_heartbeat(peer_id: int) -> void:
	var transport := multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	var socket := transport.get_peer(peer_id)
	if socket != null:
		socket.heartbeat_interval = 5.0

func _connection_failed() -> void:
	close_connection()
	connection_error.emit("连接失败，请确认服务器地址、端口及安全证书。")

func _server_disconnected() -> void:
	close_connection()
	server_lost.emit()
