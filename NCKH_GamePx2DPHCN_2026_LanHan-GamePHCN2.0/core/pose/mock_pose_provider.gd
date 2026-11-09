extends PoseProvider

## Local replacement for the future Python/MediaPipe backend.
## Debug keys:
##   T - toggle tracking
##   K - disconnect/reconnect the mock backend
##   C - run a five-second calibration
##   R - emit one valid repetition, including hold progress when required
##   F - emit one rejected repetition or interrupted hold

const DEFAULT_EXERCISE_ID := "scapular_retraction"

var _connected := false
var _tracking := false
var _paused := false
var _calibrating := false
var _calibration_elapsed_ms := 0.0
var _calibration_duration_ms := 5000.0
var _message_counter := 0
var _rep_counter := 0
var _pose_frame_counter := 0
var _pose_frame_accumulator := 0.0
var _pose_fps := 15.0
var last_exercise_request: Dictionary = {}
var _movement_generation := 0
var _hold_running := false


func _cancel_movement() -> void:
	_movement_generation += 1
	_hold_running = false


func _ready() -> void:
	set_process(true)
	set_process_unhandled_key_input(true)
	open_connection()


func _process(delta: float) -> void:
	if not _connected or _paused:
		return

	if _calibrating:
		_update_calibration(delta)

	if _tracking and not active_exercise_id.is_empty():
		_pose_frame_accumulator += delta
		if _pose_frame_accumulator >= 1.0 / _pose_fps:
			_pose_frame_accumulator = 0.0
			simulate_pose_frame()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	match event.physical_keycode:
		KEY_T:
			set_tracking(not _tracking)
		KEY_K:
			if _connected:
				close_connection()
			else:
				open_connection()
		KEY_C:
			start_calibration({
				"exercise_id": _current_exercise_id(),
				"duration_ms": 5000,
				"target_side": "both",
			})
		KEY_R:
			simulate_valid_rep()
		KEY_F:
			simulate_rejected_rep("MOVEMENT_TOO_FAST")


func open_connection() -> void:
	if _connected:
		return

	_connected = true
	handle_message(_make_message("server_hello", {
		"backend_version": "mock-1.0.0",
		"pose_engine": "mock",
		"camera_available": true,
		"supported_exercises": [
			"scapular_retraction",
			"wall_abduction_external_rotation",
			"horizontal_shoulder_adduction",
			"hands_behind_head",
			"cross_body_shoulder_stretch",
		],
		"supported_features": [
			"pose_tracking",
			"joint_angles",
			"calibration",
			"movement_speed_validation",
			"hold_validation",
		],
	}))
	set_tracking(true)


func close_connection() -> void:
	_cancel_movement()
	if not _connected:
		return

	_connected = false
	provider_connected = false
	_tracking = false
	_calibrating = false
	connection_changed.emit(false, {"reason": "mock_closed"})


func start_calibration(request: Dictionary) -> void:
	if not _connected or not _tracking:
		return
	active_session_id = str(request.get("session_id", active_session_id))
	active_exercise_id = str(request.get("exercise_id", _current_exercise_id()))
	_calibration_duration_ms = float(request.get("duration_ms", 5000))
	_calibration_elapsed_ms = 0.0
	_calibrating = true


func start_exercise(request: Dictionary) -> void:
	_cancel_movement()
	last_exercise_request = request.duplicate(true)
	active_session_id = str(request.get("session_id", active_session_id))
	active_exercise_id = str(request.get("exercise_id", DEFAULT_EXERCISE_ID))
	_paused = false
	_rep_counter = 0
	set_tracking(true)


func pause_exercise(_reason := "user_paused") -> void:
	_cancel_movement()
	_paused = true


func resume_exercise() -> void:
	_paused = false


func stop_exercise(_reason := "user_cancelled") -> void:
	_cancel_movement()
	_paused = false
	_calibrating = false
	active_exercise_id = ""
	active_session_id = ""


func set_tracking(enabled: bool) -> void:
	if not _connected:
		return
	_tracking = enabled
	if not enabled:
		_cancel_movement()
	handle_message(_make_message("tracking_status", {
		"status": "tracking" if enabled else "no_person",
		"person_detected": enabled,
		"confidence": 0.95 if enabled else 0.0,
		"full_body_visible": enabled,
		"required_body_visible": enabled,
		"camera_fps": 30.0,
		"feedback_code": "POSITION_OK" if enabled else "TRACKING_LOST",
	}))


func simulate_pose_frame(rom_progress := 0.0, movement_state := "ready") -> void:
	if not _connected or not _tracking:
		return

	_pose_frame_counter += 1
	handle_message(_make_message("pose_frame", {
		"frame_id": _pose_frame_counter,
		"tracking": {
			"person_detected": true,
			"confidence": 0.95,
			"required_body_visible": true,
		},
		"angles": {
			"left_shoulder": 75.0 * rom_progress,
			"right_shoulder": 76.0 * rom_progress,
			"left_elbow": 90.0,
			"right_elbow": 90.0,
		},
		"exercise": {
			"exercise_id": _current_exercise_id(),
			"movement_state": movement_state,
			"form_valid": true,
			"rom_progress": clampf(rom_progress, 0.0, 1.0),
			"hold_progress": 0.0,
			"movement_duration_ms": 0,
			"quality": 0.92,
			"feedback_code": "POSITION_OK",
		},
	}))


func simulate_valid_rep() -> void:
	if not _can_simulate_movement():
		return
	if int(last_exercise_request.get("hold_duration_ms", 0)) > 0:
		simulate_valid_hold()
		return
	_emit_standard_valid_rep()


func _emit_standard_valid_rep() -> void:
	_rep_counter += 1
	var candidate_id := "mock-rep-%04d" % _rep_counter
	_emit_exercise_event("movement_started", candidate_id, {
		"quality": 0.90,
		"feedback_code": "MOVEMENT_STARTED",
	})
	_emit_exercise_event("target_reached", candidate_id, {
		"quality": 0.92,
		"feedback_code": "TARGET_REACHED",
	})
	_emit_exercise_event("rep_completed", candidate_id, {
		"duration_ms": 2500,
		"max_rom_ratio": 0.89,
		"hold_duration_ms": 0,
		"quality": 0.92,
		"feedback_code": "REP_VALID",
	})


func simulate_valid_hold(step_seconds := 1.0) -> void:
	if _hold_running or not _can_simulate_movement():
		return
	_hold_running = true
	var generation := _movement_generation
	_rep_counter += 1
	var candidate_id := "mock-rep-%04d" % _rep_counter
	var target_ms := int(last_exercise_request.get("hold_duration_ms", 5000))
	var steps := 5
	_emit_exercise_event("movement_started", candidate_id, {"feedback_code": "MOVEMENT_STARTED"})
	_emit_exercise_event("target_reached", candidate_id, {"feedback_code": "TARGET_REACHED"})
	_emit_exercise_event("hold_started", candidate_id, {
		"hold_target_ms": target_ms,
		"feedback_code": "HOLD_STARTED",
	})
	for step in range(1, steps + 1):
		if generation != _movement_generation:
			return
		if not _connected or not _tracking or _paused or active_exercise_id.is_empty():
			_emit_exercise_event("hold_interrupted", candidate_id, {
				"hold_target_ms": target_ms,
				"feedback_code": "HOLD_INTERRUPTED",
			})
			return
		if step_seconds > 0.0:
			await get_tree().create_timer(step_seconds, false).timeout
		if generation != _movement_generation:
			return
		var elapsed_ms := int(round(float(target_ms) * float(step) / float(steps)))
		_emit_exercise_event("hold_progress", candidate_id, {
			"hold_elapsed_ms": elapsed_ms,
			"hold_target_ms": target_ms,
			"hold_progress": float(step) / float(steps),
			"feedback_code": "HOLD_PROGRESS",
		})
	_hold_running = false
	_emit_exercise_event("hold_completed", candidate_id, {
		"hold_target_ms": target_ms,
		"feedback_code": "HOLD_COMPLETED",
	})
	_emit_exercise_event("rep_completed", candidate_id, {
		"duration_ms": 2500 + target_ms,
		"max_rom_ratio": 0.89,
		"hold_duration_ms": target_ms,
		"quality": 0.92,
		"feedback_code": "REP_VALID",
	})


func simulate_rejected_hold(feedback_code := "HOLD_INTERRUPTED") -> void:
	if not _can_simulate_movement():
		return
	_cancel_movement()
	_rep_counter += 1
	var candidate_id := "mock-rep-%04d" % _rep_counter
	var target_ms := int(last_exercise_request.get("hold_duration_ms", 5000))
	_emit_exercise_event("movement_started", candidate_id, {"feedback_code": "MOVEMENT_STARTED"})
	_emit_exercise_event("target_reached", candidate_id, {"feedback_code": "TARGET_REACHED"})
	_emit_exercise_event("hold_started", candidate_id, {"hold_target_ms": target_ms})
	_emit_exercise_event("hold_progress", candidate_id, {
		"hold_elapsed_ms": int(float(target_ms) * 0.4),
		"hold_target_ms": target_ms,
		"hold_progress": 0.4,
	})
	_emit_exercise_event("hold_interrupted", candidate_id, {
		"hold_target_ms": target_ms,
		"feedback_code": feedback_code,
	})
	_emit_exercise_event("rep_rejected", candidate_id, {
		"duration_ms": 2500,
		"max_rom_ratio": 0.82,
		"hold_duration_ms": int(float(target_ms) * 0.4),
		"quality": 0.55,
		"feedback_code": feedback_code,
	})
func simulate_rejected_rep(feedback_code := "MOVEMENT_TOO_FAST") -> void:
	if not _can_simulate_movement():
		return
	if int(last_exercise_request.get("hold_duration_ms", 0)) > 0:
		simulate_rejected_hold(feedback_code)
		return

	_rep_counter += 1
	var candidate_id := "mock-rep-%04d" % _rep_counter
	_emit_exercise_event("movement_started", candidate_id, {
		"quality": 0.60,
		"feedback_code": "MOVEMENT_STARTED",
	})
	_emit_exercise_event("rep_rejected", candidate_id, {
		"duration_ms": 700,
		"max_rom_ratio": 0.65,
		"hold_duration_ms": 0,
		"quality": 0.35,
		"feedback_code": feedback_code,
	})


func _update_calibration(delta: float) -> void:
	if not _tracking:
		return

	_calibration_elapsed_ms += delta * 1000.0
	var progress := clampf(_calibration_elapsed_ms / _calibration_duration_ms, 0.0, 1.0)
	handle_message(_make_message("calibration_progress", {
		"exercise_id": _current_exercise_id(),
		"progress": progress,
		"elapsed_ms": int(_calibration_elapsed_ms),
		"duration_ms": int(_calibration_duration_ms),
		"tracking_valid": true,
		"current_rom_value": 90.0 * progress,
		"rom_unit": "degree",
		"feedback_code": "KEEP_POSITION",
	}))

	if progress >= 1.0:
		_calibrating = false
		handle_message(_make_message("calibration_completed", {
			"exercise_id": _current_exercise_id(),
			"success": true,
			"target_side": "both",
			"max_rom": {
				"left": 88.0,
				"right": 90.0,
				"combined": 88.0,
				"unit": "degree",
			},
			"confidence": 0.95,
			"recommended_target_ratio": 0.85,
			"recommended_target_value": 74.8,
			"feedback_code": "CALIBRATION_COMPLETED",
		}))


func _emit_exercise_event(event_name: String, candidate_id: String, extra: Dictionary) -> void:
	var payload := {
		"exercise_id": _current_exercise_id(),
		"event": event_name,
		"rep_candidate_id": candidate_id,
	}
	payload.merge(extra, true)
	handle_message(_make_message("exercise_event", payload))


func _can_simulate_movement() -> bool:
	if not _connected or _paused or not _tracking or active_exercise_id.is_empty():
		return false
	return true


func _current_exercise_id() -> String:
	return DEFAULT_EXERCISE_ID if active_exercise_id.is_empty() else active_exercise_id


func _make_message(message_type: String, payload: Dictionary) -> Dictionary:
	_message_counter += 1
	return {
		"contract_version": CONTRACT_VERSION,
		"type": message_type,
		"message_id": "mock-msg-%06d" % _message_counter,
		"session_id": active_session_id,
		"timestamp_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"source": "backend",
		"payload": payload,
	}
