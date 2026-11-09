class_name ExerciseSession
extends Node

signal state_changed(current_state: State, previous_state: State)
signal progress_changed(rep_in_phase: int, reps_per_phase: int, phase: int, phase_count: int)
signal feedback_changed(code: String)
signal repetition_accepted(data: Dictionary)
signal repetition_rejected(data: Dictionary)
signal hold_started(data: Dictionary)
signal hold_progress_changed(progress: float, elapsed_ms: int, target_ms: int)
signal hold_interrupted(data: Dictionary)
signal rest_time_changed(seconds_remaining: float)
signal session_completed(summary: Dictionary)

enum State { IDLE, READY, ACTIVE, RESTING, PAUSED, TRACKING_LOST, COMPLETED }

var state: State = State.IDLE
var config: Dictionary = {}
var session_id := ""
var exercise_id := ""
var rep_in_phase := 0
var total_valid_reps := 0
var total_rejected_reps := 0
var current_phase := 1
var rest_seconds_remaining := 0.0
var repetition_input_enabled := true

var _session_started := false
var _state_before_tracking_loss: State = State.IDLE
var _accepted_candidate_ids: Dictionary = {}
var _pose_input: Node
var _started_at := ""
var _map_id := 1
var _difficulty := 1
var _menu_paused := false


func set_menu_paused(paused: bool) -> void:
	_menu_paused = paused
	if not _session_started:
		return
	if paused:
		_pose_input.pause_exercise("user_paused")
		if state == State.ACTIVE:
			hold_interrupted.emit({"feedback_code": "HOLD_INTERRUPTED"})
			hold_progress_changed.emit(0.0, 0, int(config.get("hold_duration_ms", 0)))
	elif state == State.ACTIVE and repetition_input_enabled:
		_resume_provider()


func _ready() -> void:
	_pose_input = get_node("/root/PoseInput")
	_pose_input.connection_changed.connect(_on_connection_changed)
	_pose_input.tracking_status_changed.connect(_on_tracking_status_changed)
	_pose_input.exercise_event_received.connect(_on_exercise_event_received)
	_pose_input.provider_error_received.connect(_on_provider_error_received)


func _process(delta: float) -> void:
	if state != State.RESTING:
		return
	rest_seconds_remaining = maxf(rest_seconds_remaining - delta, 0.0)
	rest_time_changed.emit(rest_seconds_remaining)
	if rest_seconds_remaining <= 0.0:
		_finish_rest()


func start_session(session_config: Dictionary) -> bool:
	if not _validate_config(session_config):
		return false
	config = session_config.duplicate(true)
	session_id = "%s-%s" % [str(config.get("session_id", "exercise")), Crypto.new().generate_random_bytes(12).hex_encode()]
	_started_at = Time.get_datetime_string_from_system(true)
	_map_id = Global.selected_action
	_difficulty = 3 if Global.speed_multiplier >= 2.0 else (2 if Global.speed_multiplier >= 1.5 else 1)
	exercise_id = str(config["exercise_id"])
	rep_in_phase = 0
	total_valid_reps = 0
	total_rejected_reps = 0
	current_phase = 1
	rest_seconds_remaining = 0.0
	repetition_input_enabled = true
	_accepted_candidate_ids.clear()
	_session_started = true
	_change_state(State.READY)
	_emit_progress()
	# Only recognition settings go to the provider. Godot owns rep targets,
	# phases and rest timing in config for the entire session.
	_pose_input.start_exercise({
		"session_id": session_id,
		"exercise_id": exercise_id,
		"difficulty": str(config.get("difficulty", "standard")),
		"target_side": str(config.get("target_side", "both")),
		"target_rom_ratio": float(config.get("target_rom_ratio", 0.85)),
		"calibrated_max_rom": float(config.get("calibrated_max_rom", 0.0)),
		"target_rom_value": float(config.get("target_rom_value", 0.0)),
		"minimum_movement_duration_ms": int(config.get("minimum_movement_duration_ms", 2000)),
		"maximum_movement_duration_ms": int(config.get("maximum_movement_duration_ms", 5000)),
		"hold_duration_ms": int(config.get("hold_duration_ms", 0)),
	})
	var tracking_ok := bool(_pose_input.last_tracking_status.get("person_detected", false)) \
			and bool(_pose_input.last_tracking_status.get("required_body_visible", false))
	if _pose_input.provider_connected and tracking_ok:
		_change_state(State.ACTIVE)
		feedback_changed.emit("SESSION_READY")
	else:
		_state_before_tracking_loss = State.ACTIVE
		_change_state(State.TRACKING_LOST)
		feedback_changed.emit("TRACKING_LOST")
	return true


func _exit_tree() -> void:
	if _session_started:
		stop_session("scene_exiting")


func stop_session(reason := "user_cancelled") -> void:
	if not _session_started:
		return
	_session_started = false
	_pose_input.stop_exercise(reason)
	_change_state(State.IDLE)


func pause_session(reason := "user_paused") -> void:
	if not _session_started or state != State.ACTIVE:
		return
	_pose_input.pause_exercise(reason)
	_change_state(State.PAUSED)
	feedback_changed.emit("SESSION_PAUSED")


func resume_session() -> void:
	if not _session_started or state != State.PAUSED:
		return
	var tracking_ok := bool(_pose_input.last_tracking_status.get("person_detected", false)) \
			and bool(_pose_input.last_tracking_status.get("required_body_visible", false))
	if not _pose_input.provider_connected or not tracking_ok:
		_state_before_tracking_loss = State.PAUSED
		_change_state(State.TRACKING_LOST)
		feedback_changed.emit("TRACKING_LOST")
		return
	if repetition_input_enabled:
		_resume_provider()
	else:
		_pose_input.pause_exercise("waiting_for_action_zone")
	_change_state(State.ACTIVE)
	feedback_changed.emit("SESSION_RESUMED")


func set_repetition_input_enabled(enabled: bool, reason := "waiting_for_action_zone") -> void:
	var changed := repetition_input_enabled != enabled
	repetition_input_enabled = enabled
	if not _session_started or state != State.ACTIVE:
		return
	if enabled:
		_resume_provider()
		if changed:
			feedback_changed.emit("ACTION_ZONE_READY")
	else:
		_pose_input.pause_exercise(reason)
		if changed:
			feedback_changed.emit("ROCK_APPROACHING")


func debug_skip_rest() -> void:
	if state == State.RESTING:
		rest_seconds_remaining = 0.0
		_finish_rest()


func _on_exercise_event_received(data: Dictionary) -> void:
	if _menu_paused or get_tree().paused:
		return
	if not _session_started or state != State.ACTIVE:
		return
	if not repetition_input_enabled:
		return
	if str(data.get("exercise_id", "")) != exercise_id:
		return
	match str(data.get("event", "")):
		"movement_started": feedback_changed.emit(str(data.get("feedback_code", "MOVEMENT_STARTED")))
		"feedback": feedback_changed.emit(str(data.get("feedback_code", "")))
		"target_reached": feedback_changed.emit(str(data.get("feedback_code", "TARGET_REACHED")))
		"hold_started":
			hold_started.emit(data)
			hold_progress_changed.emit(0.0, 0, int(config.get("hold_duration_ms", 0)))
			feedback_changed.emit("HOLD_STARTED")
		"hold_progress":
			var target_ms := int(data.get("hold_target_ms", config.get("hold_duration_ms", 0)))
			var elapsed_ms := int(data.get("hold_elapsed_ms", 0))
			var progress := float(data.get("hold_progress", 0.0))
			if target_ms > 0 and not data.has("hold_progress"):
				progress = float(elapsed_ms) / float(target_ms)
			hold_progress_changed.emit(clampf(progress, 0.0, 1.0), elapsed_ms, target_ms)
		"hold_completed":
			var target_ms := int(data.get("hold_target_ms", config.get("hold_duration_ms", 0)))
			hold_progress_changed.emit(1.0, target_ms, target_ms)
			feedback_changed.emit("HOLD_COMPLETED")
		"hold_interrupted":
			hold_interrupted.emit(data)
			hold_progress_changed.emit(0.0, 0, int(config.get("hold_duration_ms", 0)))
			feedback_changed.emit(str(data.get("feedback_code", "HOLD_INTERRUPTED")))
		"rep_completed": _accept_repetition(data)
		"rep_rejected":
			total_rejected_reps += 1
			repetition_rejected.emit(data)
			feedback_changed.emit(str(data.get("feedback_code", "REP_REJECTED")))


func _accept_repetition(data: Dictionary) -> void:
	var candidate_id := str(data.get("rep_candidate_id", ""))
	if candidate_id.is_empty() or _accepted_candidate_ids.has(candidate_id):
		return
	_accepted_candidate_ids[candidate_id] = true
	rep_in_phase += 1
	total_valid_reps += 1
	repetition_accepted.emit(data)
	feedback_changed.emit(str(data.get("feedback_code", "REP_VALID")))
	_emit_progress()
	if rep_in_phase < int(config["repetitions_per_phase"]):
		return
	if current_phase >= int(config["phase_count"]):
		_complete_session()
	else:
		_start_rest()


func _start_rest() -> void:
	rest_seconds_remaining = float(config.get("rest_duration_seconds", 30.0))
	_change_state(State.RESTING)
	_pose_input.pause_exercise("phase_rest")
	rest_time_changed.emit(rest_seconds_remaining)
	feedback_changed.emit("PHASE_REST")


func _finish_rest() -> void:
	if state != State.RESTING:
		return
	current_phase += 1
	rep_in_phase = 0
	_resume_provider()
	_change_state(State.ACTIVE)
	_emit_progress()
	feedback_changed.emit("NEXT_PHASE")


func _complete_session() -> void:
	_session_started = false
	_pose_input.stop_exercise("session_completed")
	_change_state(State.COMPLETED)
	var tracker := get_parent().get_node_or_null("TrackingStability")
	var stability := int(tracker.stability) if tracker != null else 0
	var summary := {
		"session_id": session_id,
		"patient_id": Global.current_patient_id,
		"patient_name": Global.current_patient_name,
		"rom_angle": roundf(Global.max_rom_angle * 10.0) / 10.0,
		"map_id": _map_id,
		"difficulty": _difficulty,
		"started_at_utc": _started_at,
		"completed_at_utc": Time.get_datetime_string_from_system(true),
		"stability": stability,
		"stability_enabled": TrackingStability.ENABLED,
		"evaluation": "HOÀN THÀNH" if not TrackingStability.ENABLED else ("HOÀN HẢO" if stability >= 3 else ("HOÀN THÀNH" if stability == 2 else "CẦN CẢI THIỆN ĐỘ ỔN ĐỊNH")),
		"exercise_id": exercise_id,
		"valid_reps": total_valid_reps,
		"rejected_reps": total_rejected_reps,
		"phase_count": int(config["phase_count"]),
	}
	var bonus_controller := get_parent().get_node_or_null("Map5Controller")
	if bonus_controller != null:
		summary["bonus_points"] = int(bonus_controller.bonus_points)
	# Commit results before the finishing animation or a scene change can interrupt it.
	if not TrackingStability.ENABLED or (tracker != null and stability >= 2):
		Global.unlock_level_for_action(_map_id, mini(_difficulty + 1, 3))
	Global.record_session(summary)
	session_completed.emit(summary)
	feedback_changed.emit("SESSION_COMPLETED")


func _on_tracking_status_changed(data: Dictionary) -> void:
	if not _session_started:
		return
	var tracking_ok := bool(data.get("person_detected", false)) \
			and bool(data.get("required_body_visible", false))
	if not tracking_ok and state not in [State.TRACKING_LOST, State.COMPLETED, State.IDLE]:
		_state_before_tracking_loss = state
		_pose_input.pause_exercise("tracking_lost")
		_change_state(State.TRACKING_LOST)
		var fb_code := str(data.get("feedback_code", ""))
		if fb_code == "CAMERA_DISCONNECTED":
			feedback_changed.emit("CAMERA_DISCONNECTED")
		else:
			feedback_changed.emit("TRACKING_LOST")
	elif tracking_ok and state == State.TRACKING_LOST:
		if _state_before_tracking_loss == State.RESTING:
			_change_state(State.RESTING)
		elif _state_before_tracking_loss == State.PAUSED:
			_change_state(State.PAUSED)
		else:
			if repetition_input_enabled:
				_resume_provider()
			else:
				_pose_input.pause_exercise("waiting_for_action_zone")
			_change_state(State.ACTIVE)
		var fb_restored := str(data.get("feedback_code", ""))
		if fb_restored == "CAMERA_RECONNECTED":
			feedback_changed.emit("CAMERA_RECONNECTED")
		else:
			feedback_changed.emit("TRACKING_RESTORED")


func _on_connection_changed(connected: bool, _details: Dictionary) -> void:
	if _session_started and not connected and state != State.TRACKING_LOST:
		_state_before_tracking_loss = state
		_change_state(State.TRACKING_LOST)
		feedback_changed.emit("BACKEND_DISCONNECTED")


func _on_provider_error_received(data: Dictionary) -> void:
	if not _session_started:
		return
	feedback_changed.emit(str(data.get("code", "INTERNAL_ERROR")))
	if str(data.get("severity", "warning")) == "fatal":
		_state_before_tracking_loss = state
		_change_state(State.TRACKING_LOST)


func _change_state(next_state: State) -> void:
	if state == next_state:
		return
	var previous := state
	state = next_state
	state_changed.emit(state, previous)


func _emit_progress() -> void:
	progress_changed.emit(rep_in_phase, int(config["repetitions_per_phase"]), current_phase, int(config["phase_count"]))


func _validate_config(session_config: Dictionary) -> bool:
	for field in ["exercise_id", "repetitions_per_phase", "phase_count"]:
		if not session_config.has(field):
			push_error("ExerciseSession config is missing field: %s" % field)
			return false
	if int(session_config["repetitions_per_phase"]) <= 0 or int(session_config["phase_count"]) <= 0:
		push_error("ExerciseSession repetitions and phases must be greater than zero.")
		return false
	return true


func _resume_provider() -> void:
	if not _menu_paused:
		_pose_input.resume_exercise()
