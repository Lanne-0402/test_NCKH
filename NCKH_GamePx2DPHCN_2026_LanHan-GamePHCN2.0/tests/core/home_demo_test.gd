extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	assert(not Global.persistence_enabled)
	get_tree().current_scene = null
	var saved := JSON.stringify(Global.session_history)
	var action: int = Global.selected_action
	var session: String = PoseInput.active_session_id
	get_tree().change_scene_to_file("res://ui/screens/start/start_screen.tscn")
	await get_tree().scene_changed
	await get_tree().process_frame
	var home = get_tree().current_scene
	assert(home.demo_map == 1 and home.DEMO_SECONDS == 10.0)
	# Deterministic 50-second cycle without waiting on wall-clock time.
	home.set_process(false)
	for map_id in range(1,6):
		assert(home.demo_map == map_id)
		assert(home.demo.world.map_id == map_id and home.demo.active)
		var ground_in_viewport: Vector2 = home.demo.world.transform * Vector2(576,320)
		var ground_on_screen: float = ground_in_viewport.y / home.demo.viewport.size.y * 648.0
		assert(is_equal_approx(ground_on_screen,440.0))
		assert(ground_on_screen < home.get_node("CanvasLayer/StartButton").position.y)
		assert(is_equal_approx(home.demo.world.scale.x,592.0/1024.0))
		home.demo_elapsed = 0
		home._process(9.99)
		assert(home.demo_map == map_id)
		await get_tree().create_timer(0.25).timeout
		assert(home.demo.world.clock > 0)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://home_demo_map_%d.png" % map_id)
		home._process(0.02)
		await get_tree().process_frame
	assert(home.demo_map == 1)
	home.set_process(true)
	var menu = home.get_node("SettingsMenu")
	menu.open_menu()
	await get_tree().process_frame
	var elapsed: float = home.demo_elapsed
	var clock: float = home.demo.world.clock
	await get_tree().create_timer(0.12).timeout
	assert(home.demo_elapsed == elapsed and home.demo.world.clock == clock)
	menu.close_menu()
	await get_tree().create_timer(0.12).timeout
	assert(home.demo_elapsed > elapsed and home.demo.world.clock > clock)
	assert(Global.selected_action == action)
	assert(JSON.stringify(Global.session_history) == saved)
	assert(PoseInput.active_session_id == session)
	home.get_node("CanvasLayer/HistoryButton").pressed.emit()
	await get_tree().scene_changed
	assert(get_tree().current_scene.scene_file_path.ends_with("history_screen.tscn"))
	get_tree().change_scene_to_file("res://ui/screens/start/start_screen.tscn")
	await get_tree().scene_changed
	assert(get_tree().current_scene.demo_map == 1)
	get_tree().current_scene.get_node("CanvasLayer/StartButton").pressed.emit()
	await get_tree().scene_changed
	assert(get_tree().current_scene.scene_file_path.ends_with("calibration_screen.tscn"))
	print("HOME_DEMO_10S_LOOP_PAUSE_ISOLATION_NAVIGATION: PASS")
	get_tree().quit()
