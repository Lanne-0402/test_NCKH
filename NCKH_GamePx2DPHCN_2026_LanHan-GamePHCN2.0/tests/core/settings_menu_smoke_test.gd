extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_db := AudioServer.get_bus_volume_db(0)
	var original_mute := AudioServer.is_bus_mute(0)
	for map_id in range(1, 6):
		Global.selected_action = map_id
		var level: Node = load("res://maps/map_%d/main_level.tscn" % map_id).instantiate()
		level.process_mode = Node.PROCESS_MODE_PAUSABLE
		level.countdown_step_seconds = 0.03
		add_child(level)
		await get_tree().process_frame
		var menu: CanvasLayer = level.get_node("SettingsMenu")
		var button: Button = level.get_node("UI/SettingsButton")
		var state: Label = level.get_node("UI/ScoreLabel" if map_id == 1 else "UI/StateLabel")
		var hearts: Label = level.get_node("UI/HeartsLabel")
		assert(state.position.y >= 366 and state.position.x < 576)
		assert(hearts.position.x >= 864 and hearts.position.y < 100)
		assert(button.icon != null and not button.disabled)
		if map_id == 5:
			var bonus: Label = level.get_node("UI/BonusLabel")
			var bonus_panel: Control = level.get_node("UI/BonusPanel")
			assert(bonus.position.y >= 366 and bonus.position.x < 576)
			assert(not bonus_panel.visible)
		level.get_node("UI/InstructionPanel/MarginContainer/VBoxContainer/StartExerciseButton").pressed.emit()
		button.pressed.emit()
		assert(get_tree().paused and menu.overlay.visible)
		var countdown: String = level.get_node("UI/CountdownLabel").text
		await get_tree().create_timer(0.15).timeout
		assert(level.get_node("UI/CountdownLabel").text == countdown)
		menu.volume.value = 35
		assert(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.35))
		menu.mute.button_pressed = true
		assert(AudioServer.is_bus_mute(0))
		menu._request_navigation(menu.HOME_SCENE)
		assert(menu.confirm.visible and get_tree().paused)
		menu.confirm.hide()
		menu._request_navigation(menu.CAMERA_SCENE)
		assert(menu.confirm.visible)
		menu.confirm.hide()
		menu.get_node("Overlay/Center/Panel/Margin/Contents/MapSelection").pressed.emit()
		assert(menu.confirm.visible and menu._pending_scene == menu.MAP_SELECTION_SCENE)
		menu.close_menu()
		assert(not get_tree().paused and not menu.overlay.visible)
		await get_tree().create_timer(0.3).timeout
		var session: ExerciseSession = level.get_node("ExerciseSession")
		assert(session.state == ExerciseSession.State.ACTIVE)
		menu.open_menu()
		var phase_before := session.current_phase
		var reps_before := session.total_valid_reps
		await get_tree().create_timer(0.1).timeout
		assert(session.current_phase == phase_before and session.total_valid_reps == reps_before)
		menu.close_menu()
		level.queue_free()
		await get_tree().process_frame
	AudioServer.set_bus_volume_db(0, original_db)
	AudioServer.set_bus_mute(0, original_mute)
	# Keep this test as a root sibling while actual map scenes navigate away.
	for destination in ["res://ui/screens/start/start_screen.tscn", "res://ui/screens/calibration/calibration_screen.tscn", "res://ui/screens/map_selection/level_selection.tscn"]:
		var level: Node = load("res://maps/map_2/main_level.tscn").instantiate()
		get_tree().root.add_child(level)
		get_tree().current_scene = level
		var menu: CanvasLayer = level.get_node("SettingsMenu")
		menu.open_menu()
		menu._request_navigation(destination)
		menu.confirm.confirmed.emit()
		await get_tree().scene_changed
		assert(not get_tree().paused)
		assert(get_tree().current_scene.scene_file_path == destination)
		get_tree().current_scene.queue_free()
		get_tree().current_scene = null
		await get_tree().process_frame
	print("SETTINGS_MENU_SMOKE_TEST: PASS (5 maps)")
	get_tree().quit()
