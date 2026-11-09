extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(not TrackingStability.ENABLED)
	assert(not Global.persistence_enabled)
	get_tree().current_scene = null
	for action in range(1, 6):
		Global.selected_action = action
		Global.speed_multiplier = 1.0
		Global.unlocked_levels_by_action[action] = 1
		get_tree().change_scene_to_file("res://maps/map_%d/main_level.tscn" % action)
		await get_tree().scene_changed
		await get_tree().process_frame
		var level = get_tree().current_scene
		assert(not level.hearts_label.visible)
		level.instruction_panel.hide()
		level.tracking_stability.grace_seconds = 0.03
		level._start_new_session_attempt()
		assert(level.exercise_session.state == ExerciseSession.State.ACTIVE)
		PoseInput.set_tracking(false)
		await get_tree().create_timer(0.08).timeout
		assert(level.exercise_session.state == ExerciseSession.State.TRACKING_LOST)
		assert(level.tracking_stability.stability == 3)
		assert(level.tracking_stability.penalize_tracking_loss() == 3)
		PoseInput.set_tracking(true)
		assert(level.exercise_session.state == ExerciseSession.State.ACTIVE)
		PoseInput.close_connection()
		await get_tree().create_timer(0.08).timeout
		assert(level.tracking_stability.stability == 3)
		PoseInput.open_connection()
		# Even a stale zero score must not affect disabled-mode completion.
		level.tracking_stability.stability = 0
		level.exercise_session._complete_session()
		await get_tree().create_timer(2.5).timeout
		assert(level.result_panel.visible)
		assert(not level.result_label.text.contains("Ổn định"))
		assert(not level.result_label.text.contains("HOÀN HẢO"))
		assert(level.result_label.text.contains("Cấp độ tiếp theo đã sẵn sàng"))
		assert(Global.get_highest_unlocked_level(action) == 2)
		var entry: Dictionary = Global.session_history.back()
		assert(entry.stability_enabled == false)
		assert(entry.evaluation == "HOÀN THÀNH")
		print("PASS stability disabled map ", action)
	get_tree().change_scene_to_file("res://ui/screens/history/history_screen.tscn")
	await get_tree().scene_changed
	for child in get_tree().current_scene.get_node("Margin/Column/Scroll/List").get_children():
		if child is Label:
			assert(not child.text.contains("Ổn định"))
	print("PASS stability disabled results and history")
	get_tree().quit()
