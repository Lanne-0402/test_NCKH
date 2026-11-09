extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://ui/screens/start/start_screen.tscn")
	await get_tree().scene_changed
	get_tree().current_scene.get_node("CanvasLayer/HistoryButton").pressed.emit()
	await get_tree().scene_changed
	assert(get_tree().current_scene.name == "History")
	get_tree().current_scene.get_node("BackButton").pressed.emit()
	await get_tree().scene_changed
	get_tree().current_scene.get_node("CanvasLayer/StartButton").pressed.emit()
	await get_tree().scene_changed
	var calibration := get_tree().current_scene
	for attempt in range(100):
		if not calibration.get_node("StartCalibButton").disabled:
			break
		await get_tree().create_timer(0.02).timeout
	assert(not calibration.get_node("StartCalibButton").disabled)
	calibration.get_node("StartCalibButton").pressed.emit()
	PoseInput._calibration_duration_ms = 30.0
	for attempt in range(100):
		if not calibration.get_node("NextButton").disabled:
			break
		await get_tree().create_timer(0.02).timeout
	assert(Global.max_rom_angle > 0)
	assert(not calibration.get_node("NextButton").disabled)
	calibration.get_node("NextButton").pressed.emit()
	await get_tree().scene_changed
	for action in range(1, 6):
		var map_button := "Button" if action == 1 else "Button%d" % action
		get_tree().current_scene.get_node("MapRows/" + ("TopRow/" if action <= 3 else "BottomRow/") + map_button).pressed.emit()
		await get_tree().scene_changed
		assert(Global.selected_action == action)
		assert(get_tree().current_scene.get_node("VBoxContainer/Button2").disabled)
		get_tree().current_scene.get_node("VBoxContainer/Button").pressed.emit()
		await get_tree().scene_changed
		var level := get_tree().current_scene
		level.countdown_step_seconds = 0.01
		level.tracking_stability.grace_seconds = 0.05
		level.get_node("UI/InstructionPanel/MarginContainer/VBoxContainer/StartExerciseButton").pressed.emit()
		var session: ExerciseSession = level.get_node("ExerciseSession")
		for frame in range(120):
			if session.state == ExerciseSession.State.ACTIVE:
				break
			await get_tree().process_frame
		assert(session.state == ExerciseSession.State.ACTIVE)
		PoseInput.set_tracking(false)
		await get_tree().create_timer(0.08).timeout
		assert(session.state == ExerciseSession.State.TRACKING_LOST)
		assert(level.tracking_stability.stability == (2 if TrackingStability.ENABLED else 3))
		await get_tree().create_timer(0.08).timeout
		assert(level.tracking_stability.stability == (2 if TrackingStability.ENABLED else 3))
		var menu := level.get_node("SettingsMenu")
		menu.open_menu()
		menu.close_menu()
		assert(session.state == ExerciseSession.State.TRACKING_LOST)
		PoseInput.set_tracking(true)
		assert(session.state == ExerciseSession.State.ACTIVE)
		PoseInput.close_connection()
		await get_tree().create_timer(0.08).timeout
		assert(level.tracking_stability.stability == (2 if TrackingStability.ENABLED else 3))
		PoseInput.open_connection()
		assert(session.state == ExerciseSession.State.ACTIVE)
		menu.open_menu()
		menu.get_node("Overlay/Center/Panel/Margin/Contents/MapSelection").pressed.emit()
		menu.confirm.confirmed.emit()
		await get_tree().scene_changed
		assert(not get_tree().paused)
		assert(PoseInput.active_session_id.is_empty())
		assert(Global.session_history.is_empty(), "Abandoned sessions are not completed results")
	print("NAVIGATION_CALIBRATION_TRACKING_ALL_MAPS: PASS")
	get_tree().quit()
