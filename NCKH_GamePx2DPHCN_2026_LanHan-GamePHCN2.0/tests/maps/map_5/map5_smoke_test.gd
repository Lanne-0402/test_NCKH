extends Node

var observed_hold_progress: Array[float] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Global.selected_action = 5
	Global.speed_multiplier = 1.0
	Global.max_rom_angle = 90.0
	Global.unlocked_levels_by_action[5] = 1
	PoseInput.open_connection()
	PoseInput.set_tracking(true)

	var level: Node = load("res://maps/map_5/main_level.tscn").instantiate()
	level.set("countdown_step_seconds", 0.01)
	level.set("tracking_loss_grace_seconds", 0.05)
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame

	var session: ExerciseSession = level.get_node("ExerciseSession")
	var map5: Map5Controller = level.get_node("Map5Controller")
	session.hold_progress_changed.connect(func(progress: float, _elapsed: int, _target: int): observed_hold_progress.append(progress))
	assert(session.state == ExerciseSession.State.IDLE)
	assert(level.get_node("UI/InstructionPanel").visible)
	assert(level.has_node("UI/InstructionPanel/MarginContainer/VBoxContainer/Map5PoseGuide"))
	level.get_node("UI/InstructionPanel/MarginContainer/VBoxContainer/StartExerciseButton").pressed.emit()
	await _wait_for_session_state(session, ExerciseSession.State.ACTIVE)
	assert(str(PoseInput.last_exercise_request.get("exercise_id", "")) == "cross_body_shoulder_stretch")
	assert(int(PoseInput.last_exercise_request.get("hold_duration_ms", 0)) == 30000)
	assert(int(session.config["repetitions_per_phase"]) == 1)
	assert(int(session.config["phase_count"]) == 2)
	for field in ["repetitions_per_phase", "phase_count", "rest_duration_ms"]:
		assert(not PoseInput.last_exercise_request.has(field))
	assert(map5.is_action_window_open())
	assert(map5.get_side_label() == "TAY TRÁI")
	var player_position: Vector2 = level.get_node("Player").global_position
	var anchor_position: Vector2 = level.get_node("Map5RestZone/PlayerAnchor").global_position
	assert(player_position.is_equal_approx(anchor_position))

	PoseInput.simulate_rejected_hold()
	await get_tree().process_frame
	assert(session.total_rejected_reps == 1)
	assert(session.total_valid_reps == 0)
	assert(is_equal_approx(level.get_node("UI/HoldPanel/HoldBar").value, 0.0))

	await PoseInput.simulate_valid_hold(0.001)
	await get_tree().process_frame
	assert(session.total_valid_reps == 1)
	assert(map5.bonus_points == 50)
	assert(session.state == ExerciseSession.State.RESTING)
	session.debug_skip_rest()
	await get_tree().process_frame
	assert(session.current_phase == 2)
	assert(map5.get_side_label() == "TAY PHẢI")

	await PoseInput.simulate_valid_hold(0.001)
	await get_tree().process_frame
	assert(session.total_valid_reps == 2)
	assert(map5.bonus_points == 100)
	assert(session.state == ExerciseSession.State.COMPLETED)
	assert(observed_hold_progress.has(1.0))

	await get_tree().create_timer(1.1).timeout
	assert(level.get_node("UI/ResultPanel").visible)
	assert(Global.get_highest_unlocked_level(5) == 2)
	assert("Điểm thưởng: 100/100" in level.get_node("UI/ResultPanel/MarginContainer/VBoxContainer/ResultLabel").text)
	print("MAP_5_SMOKE_TEST: PASS")
	get_tree().quit(0)


func _wait_for_session_state(session: ExerciseSession, expected_state: ExerciseSession.State) -> void:
	for _frame in range(60):
		if session.state == expected_state:
			return
		await get_tree().process_frame
	assert(false, "Timed out waiting for Map 5 session state.")
