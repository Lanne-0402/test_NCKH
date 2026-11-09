extends Node

var observed_hold_progress: Array[float] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Global.selected_action = 3
	Global.speed_multiplier = 1.0
	Global.max_rom_angle = 90.0
	Global.unlocked_levels_by_action[3] = 1
	PoseInput.open_connection()
	PoseInput.set_tracking(true)

	var level: Node = load("res://maps/map_3/main_level.tscn").instantiate()
	level.set("countdown_step_seconds", 0.01)
	level.set("tracking_loss_grace_seconds", 0.05)
	var map3: Map3Controller = level.get_node("Map3Controller")
	map3.wall_close_speed = 8000.0
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame

	var session: ExerciseSession = level.get_node("ExerciseSession")
	var stability: Node = level.get_node("TrackingStability")
	session.hold_progress_changed.connect(func(progress: float, _elapsed: int, _target: int): observed_hold_progress.append(progress))
	assert(session.state == ExerciseSession.State.IDLE)
	level.get_node("UI/InstructionPanel/MarginContainer/VBoxContainer/StartExerciseButton").pressed.emit()
	await _wait_for_session_state(session, ExerciseSession.State.ACTIVE)
	assert(str(PoseInput.last_exercise_request.get("exercise_id", "")) == "horizontal_shoulder_adduction")
	assert(int(PoseInput.last_exercise_request.get("hold_duration_ms", 0)) == 5000)
	assert(int(session.config["repetitions_per_phase"]) == 5)
	assert(int(session.config["phase_count"]) == 2)
	for field in ["repetitions_per_phase", "phase_count", "rest_duration_ms"]:
		assert(not PoseInput.last_exercise_request.has(field))
	await _wait_for_action_window(map3)

	for _index in range(5):
		await _complete_one_hold(map3)
	assert(session.total_valid_reps == 5)
	assert(session.state == ExerciseSession.State.RESTING)
	assert(int(map3.pushes_completed) == 5)
	session.debug_skip_rest()
	await get_tree().process_frame
	assert(session.current_phase == 2)

	for _index in range(5):
		await _complete_one_hold(map3)
	assert(session.total_valid_reps == 10)
	assert(int(map3.pushes_completed) == 10)
	assert(session.state == ExerciseSession.State.COMPLETED)
	assert(observed_hold_progress.has(1.0))

	await get_tree().create_timer(1.1).timeout
	assert(level.get_node("UI/ResultPanel").visible)
	assert(Global.get_highest_unlocked_level(3) == 2)
	print("MAP_3_SMOKE_TEST: PASS")
	get_tree().quit(0)


func _complete_one_hold(map3: Map3Controller) -> void:
	await _wait_for_action_window(map3)
	await PoseInput.simulate_valid_hold(0.001)
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout


func _wait_for_action_window(map3: Map3Controller) -> void:
	for _frame in range(240):
		if map3.is_action_window_open():
			return
		await get_tree().process_frame
	assert(false, "Timed out waiting for the Map 3 action window.")


func _wait_for_session_state(session: ExerciseSession, expected_state: ExerciseSession.State) -> void:
	for _frame in range(60):
		if session.state == expected_state:
			return
		await get_tree().process_frame
	assert(false, "Timed out waiting for Map 3 session state.")
