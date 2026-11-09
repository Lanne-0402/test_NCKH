extends Node

var observed_hold_progress: Array[float] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Global.selected_action = 2
	Global.speed_multiplier = 1.0
	Global.max_rom_angle = 90.0
	Global.unlocked_levels_by_action[1] = 1
	Global.unlocked_levels_by_action[2] = 1
	PoseInput.open_connection()
	PoseInput.set_tracking(true)

	var level: Node = load("res://maps/map_2/main_level.tscn").instantiate()
	level.set("countdown_step_seconds", 0.01)
	level.set("tracking_loss_grace_seconds", 0.05)
	var map2: Node = level.get_node("Map2Controller")
	map2.slab_descent_speed = 20.0
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame

	var session: ExerciseSession = level.get_node("ExerciseSession")
	var stability: Node = level.get_node("TrackingStability")
	session.hold_progress_changed.connect(func(progress: float, _elapsed: int, _target: int): observed_hold_progress.append(progress))
	assert(session.state == ExerciseSession.State.IDLE)
	assert(level.get_node("UI/InstructionPanel").visible)
	assert(level.has_node("UI/InstructionPanel/MarginContainer/VBoxContainer/Map2PoseGuide"))
	level.get_node("UI/InstructionPanel/MarginContainer/VBoxContainer/StartExerciseButton").pressed.emit()
	await _wait_for_session_state(session, ExerciseSession.State.ACTIVE)
	assert(str(PoseInput.last_exercise_request.get("exercise_id", "")) == "wall_abduction_external_rotation")
	assert(int(PoseInput.last_exercise_request.get("hold_duration_ms", 0)) == 5000)
	assert(int(session.config["repetitions_per_phase"]) == 5)
	assert(int(session.config["phase_count"]) == 2)
	for field in ["repetitions_per_phase", "phase_count", "rest_duration_ms"]:
		assert(not PoseInput.last_exercise_request.has(field))
	assert(is_equal_approx(float(PoseInput.last_exercise_request.get("target_rom_value", 0.0)), 63.0))
	assert(not map2.is_action_window_open())
	assert(int(stability.stability) == 3)

	# The mock cannot start a hold while the slab is still descending.
	await PoseInput.simulate_valid_hold(0.0)
	assert(session.total_valid_reps == 0)
	map2.slab_descent_speed = 100000.0
	await _wait_for_action_window(map2)
	assert(is_equal_approx(level.get_node("Map2Slab").position.y, 200.0))

	# Interrupted hold keeps the same slab and does not add a valid repetition.
	PoseInput.simulate_rejected_hold()
	await get_tree().process_frame
	assert(session.total_rejected_reps == 1)
	assert(session.total_valid_reps == 0)
	assert(map2.is_action_window_open())
	assert(is_equal_approx(level.get_node("UI/HoldPanel/HoldBar").value, 0.0))

	# Stability rules are identical to Map 1.
	PoseInput.set_tracking(false)
	await get_tree().create_timer(0.01).timeout
	PoseInput.set_tracking(true)
	await get_tree().process_frame
	assert(int(stability.stability) == 3)
	PoseInput.set_tracking(false)
	await get_tree().create_timer(0.08).timeout
	assert(int(stability.stability) == (2 if TrackingStability.ENABLED else 3))
	await get_tree().create_timer(0.08).timeout
	assert(int(stability.stability) == (2 if TrackingStability.ENABLED else 3))
	PoseInput.set_tracking(true)
	await get_tree().process_frame
	assert(session.state == ExerciseSession.State.ACTIVE)
	assert(map2.is_action_window_open())
	PoseInput.close_connection()
	await get_tree().create_timer(0.08).timeout
	assert(session.state == ExerciseSession.State.TRACKING_LOST)
	assert(int(stability.stability) == (2 if TrackingStability.ENABLED else 3))
	PoseInput.open_connection()
	await get_tree().process_frame
	assert(session.state == ExerciseSession.State.ACTIVE)
	assert(int(stability.stability) == (2 if TrackingStability.ENABLED else 3))
	assert(map2.is_action_window_open())

	# Complete 2 phases x 5 holds. Only rep_completed advances progress.
	for _index in range(5):
		await _complete_one_hold(map2)
	assert(session.total_valid_reps == 5)
	assert(session.state == ExerciseSession.State.RESTING)
	assert(int(map2.lifts_completed) == 5)
	await get_tree().create_timer(0.4).timeout
	session.debug_skip_rest()
	await get_tree().process_frame
	assert(session.current_phase == 2)
	for _index in range(5):
		await _complete_one_hold(map2)
	assert(session.total_valid_reps == 10)
	assert(int(map2.lifts_completed) == 10)
	assert(session.state == ExerciseSession.State.COMPLETED)
	assert(observed_hold_progress.has(0.2))
	assert(observed_hold_progress.has(1.0))
	assert(int(stability.stability) == (2 if TrackingStability.ENABLED else 3))

	await get_tree().create_timer(1.1).timeout
	assert(level.get_node("UI/ResultPanel").visible)
	assert(Global.get_highest_unlocked_level(2) == 2)
	assert(Global.get_highest_unlocked_level(1) == 1)
	assert("Đánh giá: HOÀN THÀNH" in level.get_node("UI/ResultPanel/MarginContainer/VBoxContainer/ResultLabel").text)
	print("MAP_2_SMOKE_TEST: PASS")
	get_tree().quit(0)


func _complete_one_hold(map2: Node) -> void:
	await _wait_for_action_window(map2)
	await PoseInput.simulate_valid_hold(0.001)
	await get_tree().process_frame


func _wait_for_action_window(map2: Node) -> void:
	for _frame in range(180):
		if map2.is_action_window_open():
			return
		await get_tree().process_frame
	assert(false, "Timed out waiting for the Map 2 action window.")


func _wait_for_session_state(session: ExerciseSession, expected_state: ExerciseSession.State) -> void:
	for _frame in range(60):
		if session.state == expected_state:
			return
		await get_tree().process_frame
	assert(false, "Timed out waiting for Map 2 session state.")
