extends SceneTree
## 暂时起一个可见 Host，等待一个客户端加入后截取轮盘的真实渲染。
func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var demo: Variant = scene.instantiate()
	root.add_child(demo)
	demo.auto_smoke = true
	demo.auto_silent = true
	demo.game.start_host(24680)
	demo.game.set_initial_lives(3)
	var begin_ms: int = Time.get_ticks_msec()
	while demo.game.phase != "choosing" and Time.get_ticks_msec() - begin_ms < 10000:
		await create_timer(0.2).timeout
	if demo.game.phase != "choosing":
		push_error("VISUAL_MATCH_NOT_STARTED")
		quit(4)
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	var file_path: String = OS.get_environment("TEMP").path_join("turn_demo_inmatch.png")
	var err: Error = frame.save_png(file_path)
	print("TURN_GAME_VISUAL=%s status=%d" % [file_path, err])
	quit(0 if err == OK else 4)
