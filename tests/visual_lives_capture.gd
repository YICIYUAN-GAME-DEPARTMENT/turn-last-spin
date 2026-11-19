extends "res://tests/network_smoke.gd"
## 已启动本地专服后，截取大厅生命设置。
func _run() -> void:
	if not await _open_client():
		return
	_game.create_room()
	if not await _until(func(): return _game.phase == "lobby", 4.0):
		_fail("截图前未创建房间")
		return
	_game.set_initial_lives(3)
	if not await _until(func(): return _game.initial_lives == 3, 4.0):
		_fail("截图前未同步生命设置")
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var snapshot: Image = root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://.godot/turn_lives_lobby.png")
	var err: Error = snapshot.save_png(path)
	print("TURN_LOBBY_LIVES_VISUAL=%s code=%d" % [path, err])
	quit(0 if err == OK else 2)
