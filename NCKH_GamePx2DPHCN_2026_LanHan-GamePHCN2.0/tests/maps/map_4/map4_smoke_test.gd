extends Node

var observed_hold_progress: Array[float] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Global.selected_action = 4
	Global.speed_multiplier = 1.0
	Global.max_rom_angle = 90.0
	Global.unlocked_levels_by_action[4] = 1
	PoseInput.open_connection()
	PoseInput.set_tracking(true)

	var level: Node = load("res://maps/map_4/main_level.tscn").instantiate()
	level.set("countdown_step_seconds", 0.01)
	level.set("tracking_loss_grace_seconds", 0.05)
	var map4: Map4Controller = level.get_node("Map4Controller")
	map4.ledge_approach_duration = 0.08
	map4.jump_duration = 0.05
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame

	var session: ExerciseSession = level.get_node("ExerciseSession")
	session.hold_progress_changed.connect(func(progress: float, _elapsed: int, _target: int): observed_hold_progress.append(progress))
	level.get_node("UI/InstructionPanel/MarginContainer/VBoxContainer/StartExerciseButton").pressed.emit()
	await _wait_for_session_state(session, ExerciseSession.State.ACTIVE)
	assert(str(PoseInput.last_exercise_request.get("exercise_id", "")) == "hands_behind_head")
	assert(int(PoseInput.last_exercise_request.get("hold_duration_ms", 0)) == 5000)
	assert(int(session.config["repetitions_per_phase"]) == 5)
	assert(int(session.config["phase_count"]) == 2)
	for field in ["repetitions_per_phase", "phase_count", "rest_duration_ms"]:
		assert(not PoseInput.last_exercise_request.has(field))

	for _index in range(5):
		await _complete_one_hold(map4)
	assert(session.total_valid_reps == 5)
	assert(session.state == ExerciseSession.State.RESTING)
	assert(int(map4.steps_completed) == 5)
	session.debug_skip_rest()
	await get_tree().process_frame
	assert(session.current_phase == 2)

	for _index in range(5):
		await _complete_one_hold(map4)
	assert(session.total_valid_reps == 10)
	assert(int(map4.steps_completed) == 10)
	assert(session.state == ExerciseSession.State.COMPLETED)
	assert(level.get_node("World/Map4ClimbTrack/Step_10/SummitVisual").visible)
	var player_y: float = level.get_node("Player").global_position.y
	var run_start_y: float = level.get_node("World/Map4ClimbTrack/Step_10/RunStart").global_position.y
	assert(absf(player_y - run_start_y) <= 2.0)
	assert(observed_hold_progress.has(1.0))

	await get_tree().create_timer(1.1).timeout
	assert(level.get_node("UI/ResultPanel").visible)
	assert(Global.get_highest_unlocked_level(4) == 2)
	print("MAP_4_SMOKE_TEST: PASS")
	get_tree().quit(0)


func _complete_one_hold(map4: Map4Controller) -> void:
	await _wait_for_action_window(map4)
	await PoseInput.simulate_valid_hold(0.001)
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout


func _wait_for_action_window(map4: Map4Controller) -> void:
	for _frame in range(240):
		if map4.is_action_window_open():
			return
		await get_tree().process_frame
	assert(false, "Timed out waiting for the Map 4 action window.")


func _wait_for_session_state(session: ExerciseSession, expected_state: ExerciseSession.State) -> void:
	for _frame in range(60):
		if session.state == expected_state:
			return
		await get_tree().process_frame
	assert(false, "Timed out waiting for Map 4 session state.")
