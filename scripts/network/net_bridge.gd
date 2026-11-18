extends Node
## 固定 RPC NodePath：/root/Main/Net。唯一的 ENet 依赖入口。
signal host_command(peer_id: int, kind: String, payload: Dictionary)
signal client_event(kind: String, payload: Dictionary)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal connected_to_host()
signal connection_error(message: String)
signal host_lost()

const MAX_REMOTE_PEERS := 11

func _ready() -> void:
	multiplayer.peer_connected.connect(func(id: int): peer_joined.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int): peer_left.emit(id))
	multiplayer.connected_to_server.connect(func(): connected_to_host.emit())
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)

func start_host(port: int) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_REMOTE_PEERS)
	if err != OK:
		connection_error.emit("监听失败：%s" % error_string(err))
		return false
	multiplayer.multiplayer_peer = peer
	return true

func connect_to_host(address: String, port: int) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err != OK:
		connection_error.emit("连接初始化失败：%s" % error_string(err))
		return false
	multiplayer.multiplayer_peer = peer
	return true

func send_command(kind: String, payload: Dictionary) -> void:
	if multiplayer.is_server():
		host_command.emit(1, kind, payload)
	else:
		_receive_host_command.rpc_id(1, kind, payload)

func send_event(peer_id: int, kind: String, payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if peer_id == 1:
		client_event.emit(kind, payload)
	else:
		_receive_client_event.rpc_id(peer_id, kind, payload)

func close_connection() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

@rpc("any_peer", "call_remote", "reliable")
func _receive_host_command(kind: String, payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender > 1:
		host_command.emit(sender, kind, payload)

@rpc("authority", "call_remote", "reliable")
func _receive_client_event(kind: String, payload: Dictionary) -> void:
	if multiplayer.is_server():
		return
	client_event.emit(kind, payload)

func _connection_failed() -> void:
	connection_error.emit("连接失败，请确认 IP、端口和房主已启动")
	close_connection()

func _server_disconnected() -> void:
	host_lost.emit()
	close_connection()
