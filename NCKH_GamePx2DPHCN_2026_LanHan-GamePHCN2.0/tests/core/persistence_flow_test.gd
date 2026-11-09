extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	assert(Global.save_path.begins_with("res://tests/"), "Use an isolated --save-path for this test")
	if "--verify-restart" in OS.get_cmdline_user_args():
		assert(Global.get_highest_unlocked_level(5) == 2)
		assert(Global.get_highest_unlocked_level(1) == 1)
		assert(is_equal_approx(Global.volume_percent, 37.0))
		assert(Global.audio_muted and AudioServer.is_bus_mute(0))
		assert(Global.session_history.size() == 1)
		assert(Global.session_history[0].bonus_points == 100)
		assert(Global.session_history[0].valid_reps == 2)
		# A corrupt primary file recovers the last valid backup.
		assert(Global.save_progress())
		var file := FileAccess.open(Global.save_path, FileAccess.WRITE)
		file.store_string("{broken")
		file.close()
		Global.session_history.clear()
		assert(Global.load_progress())
		assert(Global.session_history.size() == 1)
		assert(Global.save_progress())
		print("PERSISTENCE_RESTART_AND_RECOVERY: PASS")
		get_tree().quit()
		return
	Global.session_history.clear()
	for action in range(1, 6):
		Global.unlocked_levels_by_action[action] = 1
	Global.selected_action = 5
	Global.speed_multiplier = 1.0
	Global.set_audio_settings(37.0, true)
	var level: Node = load("res://maps/map_5/main_level.tscn").instantiate()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	level.countdown_step_seconds = 0.01
	add_child(level)
	var session: ExerciseSession = level.get_node("ExerciseSession")
	var menu: CanvasLayer = level.get_node("SettingsMenu")
	level.get_node("UI/InstructionPanel/MarginContainer/VBoxContainer/StartExerciseButton").pressed.emit()
	for frame in range(120):
		if session.state == ExerciseSession.State.ACTIVE:
			break
		await get_tree().process_frame
	assert(session.state == ExerciseSession.State.ACTIVE)
	PoseInput.simulate_valid_hold(0.02)
	await get_tree().create_timer(0.025).timeout
	menu.open_menu()
	await get_tree().create_timer(0.12).timeout
	assert(session.total_valid_reps == 0)
	menu.close_menu()
	await get_tree().create_timer(0.15).timeout
	assert(session.total_valid_reps == 0, "Interrupted hold must not finish after resume")
	PoseInput.simulate_valid_hold(0.02)
	await get_tree().create_timer(0.025).timeout
	PoseInput.set_tracking(false)
	assert(session.state == ExerciseSession.State.TRACKING_LOST)
	PoseInput.set_tracking(true)
	await get_tree().create_timer(0.15).timeout
	assert(session.total_valid_reps == 0)
	await PoseInput.simulate_valid_hold(0.0)
	assert(session.state == ExerciseSession.State.RESTING)
	menu.open_menu()
	var remaining := session.rest_seconds_remaining
	await get_tree().create_timer(0.15).timeout
	assert(is_equal_approx(remaining, session.rest_seconds_remaining))
	menu.close_menu()
	PoseInput.close_connection()
	await get_tree().create_timer(0.05).timeout
	PoseInput.open_connection()
	assert(session.state == ExerciseSession.State.RESTING)
	session.debug_skip_rest()
	await PoseInput.simulate_valid_hold(0.0)
	assert(session.state == ExerciseSession.State.COMPLETED)
	assert(Global.session_history.size() == 1, "Result must persist before finish animation")
	assert(Global.get_highest_unlocked_level(5) == 2)
	Global.record_session(Global.session_history[0])
	assert(Global.session_history.size() == 1, "Duplicate completion must not duplicate history")
	level.queue_free()
	await get_tree().process_frame
	# An old mock coroutine must not inject a rep into a newly started session.
	PoseInput.start_exercise({"session_id": "old", "exercise_id": "hands_behind_head", "hold_duration_ms": 5000})
	PoseInput.simulate_valid_hold(0.02)
	PoseInput.stop_exercise()
	PoseInput.start_exercise({"session_id": "new", "exercise_id": "hands_behind_head", "hold_duration_ms": 5000})
	var events: Array = []
	PoseInput.exercise_event_received.connect(func(data: Dictionary): events.append(data))
	await get_tree().create_timer(0.2).timeout
	assert(events.is_empty())
	PoseInput.stop_exercise()
	assert(Global.last_save_error.is_empty(), Global.last_save_error)
	print("PERSISTENCE_AND_INTERRUPTION_FLOW: PASS")
	get_tree().quit()
