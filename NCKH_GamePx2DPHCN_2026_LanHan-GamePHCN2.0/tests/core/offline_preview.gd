extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(not Global.persistence_enabled)
	get_tree().current_scene = null # Keep this runner across scene transitions.
	var history_before := Global.session_history.duplicate(true)
	var outbox_before := Global.cloud_outbox.duplicate(true)
	var levels_before := Global.unlocked_levels_by_action.duplicate(true)
	var rom_before: float = Global.max_rom_angle
	var calibration = load("res://ui/screens/calibration/calibration_screen.tscn").instantiate()
	get_tree().root.add_child(calibration)
	get_tree().current_scene = calibration
	await get_tree().process_frame
	assert(calibration.next_button.disabled)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_P
	key.keycode = KEY_P
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().create_timer(0.3).timeout
	assert(PoseInput.offline_preview_enabled)
	assert(get_tree().current_scene.scene_file_path.ends_with("map_selection/level_selection.tscn"))
	assert(PoseInput.provider_connected and not PoseInput.auto_reconnect)
	assert(Global.max_rom_angle == rom_before)
	assert(not Global.record_calibration_rom(75.0))
	Global.record_session({"session_id":"offline-test"})
	Global.unlock_level_for_action(1, 3)
	assert(Global.session_history == history_before)
	assert(Global.cloud_outbox == outbox_before)
	assert(Global.unlocked_levels_by_action == levels_before)
	for id in range(1, 6):
		Global.selected_action = id
		var map = load("res://maps/map_%d/main_level.tscn" % id).instantiate()
		add_child(map)
		await get_tree().process_frame
		assert(map.exercise_session.start_session(map._session_config))
		assert(map.exercise_session.state == ExerciseSession.State.ACTIVE)
		map.exercise_session.set_repetition_input_enabled(true)
		PoseInput.simulate_valid_hold(0.0)
		assert(map.exercise_session.total_valid_reps == 1)
		map.exercise_session.stop_session("scene_changed")
		map.queue_free()
		await get_tree().process_frame
	assert(Global.session_history == history_before)
	assert(Global.cloud_outbox == outbox_before)
	assert(Global.max_rom_angle == rom_before)
	get_tree().change_scene_to_file("res://ui/screens/calibration/calibration_screen.tscn")
	await get_tree().create_timer(0.2).timeout
	assert(not PoseInput.offline_preview_enabled)
	assert(not PoseInput.provider_connected)
	assert(PoseInput.last_tracking_status.is_empty())
	assert(get_tree().current_scene.next_button.disabled)
	print("OFFLINE_PREVIEW_PASS: P navigation, five maps/reps, no history/ROM/unlocks, camera restored")
	get_tree().quit()
