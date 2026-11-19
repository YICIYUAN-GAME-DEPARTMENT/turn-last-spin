extends Node

func _ready() -> void:
	_start.call_deferred()

func _start() -> void:
	var server := OS.has_feature("dedicated_server") or "--turn-server" in OS.get_cmdline_user_args()
	var path := "res://scenes/server.tscn" if server else "res://scenes/main.tscn"
	var result := get_tree().change_scene_to_file(path)
	if result != OK:
		push_error("无法启动场景 %s：%s" % [path, error_string(result)])
		get_tree().quit(1)
