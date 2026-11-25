extends "res://tests/network_smoke.gd"
## 已启动本地专服后运行，另一客户端可用输出的房间码加入。
func _run() -> void:
	if not await _open_client():
		return
	_game.create_room()
	if not await _until(func(): return _game.phase == "lobby", 4.0):
		_fail("截图前未创建房间")
		return
	print("TURN_SMOKE_ROOM=%s" % _game.room_code)
	_game.set_initial_lives(3)
	_game.set_ready(true)
	if not await _until(func(): return _game.all_ready(), 30.0):
		_fail("截图前未全员准备")
		return
	_game.request_start()
	if not await _until(func(): return _game.phase == "choosing", 4.0):
		_fail("截图前未开局")
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	var file_path := ProjectSettings.globalize_path("res://.godot/turn_demo_inmatch.png")
	var err: Error = frame.save_png(file_path)
	print("TURN_GAME_VISUAL=%s status=%d" % [file_path, err])
	quit(0 if err == OK else 4)
