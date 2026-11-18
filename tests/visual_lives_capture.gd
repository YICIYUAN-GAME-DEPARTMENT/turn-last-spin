extends SceneTree
## 初始生命设置 UI 的图形快照：只运行测试进程，不改实际游戏场景。
func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node = scene.instantiate()
	root.add_child(main)
	main.game.start_host(24680)
	main.game.set_initial_lives(3)
	await process_frame
	await RenderingServer.frame_post_draw
	var snapshot: Image = root.get_texture().get_image()
	var path: String = OS.get_environment("TEMP").path_join("turn_lives_lobby.png")
	var err: Error = snapshot.save_png(path)
	print("TURN_LOBBY_LIVES_VISUAL=%s code=%d" % [path, err])
	quit(0 if err == OK else 2)
