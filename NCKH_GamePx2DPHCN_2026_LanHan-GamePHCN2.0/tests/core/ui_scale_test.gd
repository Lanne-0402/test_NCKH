extends Node
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")
func _run() -> void:
	assert(ProjectSettings.get_setting("display/window/size/viewport_width") == 1152)
	assert(ProjectSettings.get_setting("display/window/size/viewport_height") == 648)
	assert(ProjectSettings.get_setting("display/window/stretch/aspect") == "keep")
	var scenes := {
		"start/start_screen": ["CanvasLayer/StartButton","CanvasLayer/HistoryButton"],
		"map_selection/level_selection": ["MapRows","BackButton"],
		"level_selection/main_menu": ["VBoxContainer","BackButton"],
		"calibration/calibration_screen": ["Introduce","Label2","StartCalibButton","NextButton","PoseStatusPanel"],
		"history/history_screen": ["Margin"]
	}
	for resolution in [Vector2i(960,540), Vector2i(1366,768), Vector2i(1920,1080), Vector2i(1024,768)]:
		get_window().size = resolution
		for screen in scenes:
			var scene = load("res://ui/screens/"+screen+".tscn").instantiate()
			add_child(scene)
			for frame in range(4): await get_tree().process_frame
			var canvas := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
			assert(canvas.size.is_equal_approx(Vector2(1152,648)), str(canvas))
			for path in scenes[screen]:
				var control: Control = scene.get_node(path)
				assert(canvas.grow(1).encloses(control.get_global_rect()), screen + ":" + path)
			if screen.begins_with("calibration"):
				scene._show_warning("Kiểm tra chữ hướng dẫn dài: hãy trở lại đúng vị trí để tiếp tục.")
				assert(scene.introduce.get_theme_color("font_color").r > .8)
			if resolution == Vector2i(1024,768) and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("user://scale_"+screen.get_slice("/",0)+".png")
			scene.queue_free()
			await get_tree().process_frame
	print("UI_SCALE: PASS (5 screens x 4 window sizes, bounds, warning color)")
	get_tree().quit()
