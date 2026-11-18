extends SceneTree
## GUI 版实际画面截图检查，不修改游戏资源。
func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		push_error("VISUAL_FAIL: main scene missing")
		quit(2)
		return
	var instance: Node = scene.instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image_data: Image = root.get_texture().get_image()
	if image_data == null or image_data.is_empty():
		push_error("VISUAL_FAIL: frame image unavailable")
		quit(2)
		return
	var output: String = OS.get_environment("TEMP").path_join("turn_demo_visual.png")
	var result: Error = image_data.save_png(output)
	print("TURN_VISUAL_SAVED=%s code=%s" % [output, str(result)])
	quit(0 if result == OK else 2)
