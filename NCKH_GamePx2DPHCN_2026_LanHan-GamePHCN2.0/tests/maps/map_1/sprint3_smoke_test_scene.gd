extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Global.selected_action = 1
	Global.speed_multiplier = 1.0
	Global.max_rom_angle = 88.0
	Global.unlocked_levels_by_action[1] = 1
	Global.unlocked_levels_by_action[2] = 1
	Global.highest_unlocked_level = 1
	PoseInput.set_tracking(true)

	var level: Node = load("res://maps/map_1/main_level.tscn").instantiate()
	level.set("countdown_step_seconds", 0.01)
	level.set("tracking_loss_grace_seconds", 0.05)
	var map1: Map1Controller = level.get_node("Map1Controller")
	map1.rock_approach_speed = 1000.0
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame

	var session: ExerciseSession = level.get_node("ExerciseSession")
	assert(session.state == ExerciseSession.State.IDLE)
	assert(level.get_node("UI/InstructionPanel").visible)
	assert(level.has_node("UI/InstructionPanel/MarginContainer/VBoxContainer/Map1PoseGuide"))
	assert(is_equal_approx(level.get_node("Player").position.y, 320.0))
	assert(is_equal_approx(level.get_node("SpawnPosition").position.y, 320.0))
	assert(is_equal_approx(level.get_node("Map1ActionZone").position.y, 320.0))
	var player_collision: RectangleShape2D = level.get_node("Player/Bone").shape
	assert(player_collision.size == Vector2(42.0, 72.0))
	level.get_node("UI/InstructionPanel/MarginContainer/VBoxContainer/StartExerciseButton").pressed.emit()
	await _wait_for_session_state(session, ExerciseSession.State.ACTIVE)
	assert(session.state == ExerciseSession.State.ACTIVE)
	assert(is_equal_approx(float(PoseInput.last_exercise_request.get("calibrated_max_rom", 0.0)), 88.0))
	assert(is_equal_approx(float(PoseInput.last_exercise_request.get("target_rom_value", 0.0)), 61.6))
	assert(map1.rocks_destroyed == 0)
	assert(map1.stability == 3)
	assert(level.call("_stability_evaluation", 3) == ("HOÀN HẢO" if TrackingStability.ENABLED else "HOÀN THÀNH"))
	assert(level.call("_stability_evaluation", 2) == "HOÀN THÀNH")
	if TrackingStability.ENABLED:
		assert(not bool(level.call("_unlock_next_difficulty", 1)))
		assert(Global.get_highest_unlocked_level(1) == 1)
	assert(not map1.is_action_window_open())

	# Repetitions sent while the rock is approaching must not be counted.
	PoseInput.simulate_valid_rep()
	await get_tree().process_frame
	assert(session.total_valid_reps == 0)
	assert(map1.rocks_destroyed == 0)
	map1.rock_approach_speed = 100000.0

	await _wait_for_action_window(map1)
	assert(is_instance_valid(map1._current_rock))
	assert(is_equal_approx(map1._current_rock.position.x, level.get_node("Map1ActionZone").position.x))
	assert(is_equal_approx(map1._current_rock.position.y, 320.0))
	assert(map1._current_rock.has_node("RockVisual/Base"))
	var rock_collision: RectangleShape2D = map1._current_rock.get_node("CollisionShape2D").shape
	assert(rock_collision.size == Vector2(68.0, 58.0))

	# A rejected repetition keeps the rock in place and preserves valid progress.
	PoseInput.simulate_rejected_rep()
	await get_tree().process_frame
	assert(session.total_rejected_reps == 1)
	assert(session.total_valid_reps == 0)
	assert(map1.rocks_destroyed == 0)
	assert(map1.is_action_window_open())

	# A short tracking loss freezes gameplay but stays inside the grace period.
	var background: Node2D = level.get_node("ScrollingBackground")
	PoseInput.set_tracking(false)
	await get_tree().process_frame
	assert(session.state == ExerciseSession.State.TRACKING_LOST)
	var far_x_paused: float = background.get_node("FarLayer").position.x
	await get_tree().create_timer(0.01).timeout
	assert(is_equal_approx(background.get_node("FarLayer").position.x, far_x_paused))
	PoseInput.set_tracking(true)
	await get_tree().process_frame
	assert(session.state == ExerciseSession.State.ACTIVE)
	assert(map1.is_action_window_open())
	assert(map1.stability == 3)

	# A sustained loss removes exactly one stability heart, never one per frame.
	PoseInput.set_tracking(false)
	await get_tree().create_timer(0.08).timeout
	assert(session.state == ExerciseSession.State.TRACKING_LOST)
	assert(map1.stability == (2 if TrackingStability.ENABLED else 3))
	await get_tree().create_timer(0.08).timeout
	assert(map1.stability == (2 if TrackingStability.ENABLED else 3))
	PoseInput.set_tracking(true)
	await get_tree().process_frame
	assert(session.state == ExerciseSession.State.ACTIVE)
	assert(map1.is_action_window_open())

	# A backend/camera connection failure pauses the game but does not penalize stability.
	PoseInput.close_connection()
	await get_tree().create_timer(0.08).timeout
	assert(session.state == ExerciseSession.State.TRACKING_LOST)
	assert(map1.stability == (2 if TrackingStability.ENABLED else 3))
	PoseInput.open_connection()
	await get_tree().process_frame
	assert(session.state == ExerciseSession.State.ACTIVE)
	assert(map1.stability == (2 if TrackingStability.ENABLED else 3))
	assert(map1.is_action_window_open())

	# One accepted backend event destroys exactly one rock.
	PoseInput.simulate_valid_rep()
	await get_tree().process_frame
	assert(map1.rocks_destroyed == 1)
	assert(session.total_valid_reps == 1)

	# Complete phase 1 without resetting the preserved repetition or stability.
	for _index in range(9):
		await _complete_one_repetition(map1)
	assert(map1.rocks_destroyed == 10)
	assert(session.state == ExerciseSession.State.RESTING)
	assert(session.current_phase == 1)

	session.debug_skip_rest()
	await get_tree().process_frame
	assert(session.state == ExerciseSession.State.ACTIVE)
	assert(session.current_phase == 2)

	for _index in range(10):
		await _complete_one_repetition(map1)
	assert(map1.rocks_destroyed == 20)
	assert(session.total_valid_reps == 20)
	assert(session.state == ExerciseSession.State.COMPLETED)
	assert(level.get_node("Map1EndCave").visible)
	assert(is_equal_approx(level.get_node("Map1EndCave").position.y, 320.0))
	assert(map1.stability == (2 if TrackingStability.ENABLED else 3))

	await get_tree().create_timer(2.0).timeout
	assert(level.get_node("UI/ResultPanel").visible)
	assert(Global.get_highest_unlocked_level(1) == 2)
	assert(Global.get_highest_unlocked_level(2) == 1)
	assert("Đánh giá: HOÀN THÀNH" in level.get_node("UI/ResultPanel/MarginContainer/VBoxContainer/ResultLabel").text)
	print("SPRINT_3_MAP_1_SMOKE_TEST: PASS")
	get_tree().quit(0)


func _complete_one_repetition(map1: Map1Controller) -> void:
	await _wait_for_action_window(map1)
	PoseInput.simulate_valid_rep()
	await get_tree().process_frame


func _wait_for_action_window(map1: Map1Controller) -> void:
	for _frame in range(120):
		if map1.is_action_window_open():
			return
		await get_tree().process_frame
	var rock_details := "missing"
	if is_instance_valid(map1._current_rock):
		rock_details = "x=%.2f enabled=%s waiting=%s target=%.2f" % [
			map1._current_rock.position.x,
			map1._current_rock._movement_enabled,
			map1._current_rock._waiting_at_action_zone,
			map1._current_rock._action_zone_x,
		]
	assert(false, "Timed out waiting for the Map 1 action window (%s)." % rock_details)


func _wait_for_session_state(session: ExerciseSession, expected_state: ExerciseSession.State) -> void:
	for _frame in range(60):
		if session.state == expected_state:
			return
		await get_tree().process_frame
	assert(false, "Timed out waiting for ExerciseSession state %s; current state is %s." % [expected_state, session.state])
