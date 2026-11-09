class_name BackendPoseProvider
extends PoseProvider

## Bo cung cap du lieu cu dong canh tay ket noi thuc te voi Python Backend (MediaPipe)
## qua giao thuc WebSocket (ws://127.0.0.1:8765) theo JSON Contract 1.0.0.
## Dong thoi ho tro fallback che do mo phong (Mock) khi chua bat Backend.

const DEFAULT_EXERCISE_ID := "scapular_retraction"
const RECONNECT_DELAY_SECONDS := 2.0

@export var server_url := "ws://127.0.0.1:8765"
@export var auto_reconnect := true

var offline_preview_enabled := false
var _preview_auto_reconnect := true

var _socket := WebSocketPeer.new()
var _reconnect_timer := 0.0
var _was_connected := false
var _message_counter := 0

# Cac bien trang thai tuong thich nguoc voi MockPoseProvider (phuc vu smoke test)
var _connected := false
var _tracking := false
var _paused := false
var _calibrating := false
var _calibration_elapsed_ms := 0.0
var _calibration_duration_ms := 5000.0
var _rep_counter := 0
var _pose_frame_counter := 0
var _pose_frame_accumulator := 0.0
var _pose_fps := 15.0
var last_exercise_request: Dictionary = {}
var _movement_generation := 0
var _hold_running := false
var _embedded_backend_pid := -1


func _try_start_embedded_backend() -> void:
	if _connected or _embedded_backend_pid > 0:
		return
	var base_dir := OS.get_executable_path().get_base_dir()
	var candidates := [
		base_dir.path_join("ai_backend/ai_backend.exe"),
		base_dir.path_join("backend/ai_backend.exe"),
		base_dir.path_join("ai_backend.exe")
	]
	for path in candidates:
		if FileAccess.file_exists(path):
			print("[BackendPoseProvider] Tim thay goi Backend: %s -> Tu dong khoi chay..." % path)
			_embedded_backend_pid = OS.create_process(path, [])
			break


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _embedded_backend_pid > 0:
			print("[BackendPoseProvider] Tat tien trinh Backend PID: %d" % _embedded_backend_pid)
			OS.kill(_embedded_backend_pid)
			_embedded_backend_pid = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if "--no-save" in OS.get_cmdline_user_args():
		auto_reconnect = false
		set_process(true)
		return
	_try_start_embedded_backend()
	set_process(true)
	set_process_unhandled_key_input(true)
	open_connection()


func _process(delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not _was_connected:
				_was_connected = true
				_connected = true
				provider_connected = true
				print("[BackendPoseProvider] Da ket noi thanh cong voi Python Backend tai: %s" % server_url)
				_send_client_hello()

			# Doc toan bo cac goi tin nhan duoc tu Python
			while _socket.get_available_packet_count() > 0:
				var packet := _socket.get_packet()
				var text := packet.get_string_from_utf8()
				var parser := JSON.new()
				if parser.parse(text) == OK and parser.data is Dictionary:
					handle_message(parser.data)
				else:
					push_warning("[BackendPoseProvider] Nhan goi tin khong hop le: %s" % text)

		WebSocketPeer.STATE_CLOSED:
			if _was_connected:
				_was_connected = false
				_connected = false
				provider_connected = false
				print("[BackendPoseProvider] Ngat ket noi voi Python Backend.")
				connection_changed.emit(false, {"reason": "websocket_closed"})

			# Tu dong thu ket noi lai dinh ky
			if auto_reconnect:
				_reconnect_timer += delta
				if _reconnect_timer >= RECONNECT_DELAY_SECONDS:
					_reconnect_timer = 0.0
					_try_connect_socket()

		WebSocketPeer.STATE_CONNECTING:
			pass

		WebSocketPeer.STATE_CLOSING:
			pass

	# Xu ly timer mo phong noi bo neu khong co ket noi socket (Mock fallback)
	if not _is_socket_active():
		if _calibrating:
			_update_mock_calibration(delta)
		if _tracking and not active_exercise_id.is_empty():
			_pose_frame_accumulator += delta
			if _pose_frame_accumulator >= 1.0 / _pose_fps:
				_pose_frame_accumulator = 0.0
				simulate_pose_frame()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	# Cac phim tat debug ho tro kiem thu nhanh
	match event.physical_keycode:
		KEY_K:
			if _is_socket_active():
				close_connection()
			else:
				open_connection()
		KEY_T:
			set_tracking(not _tracking)
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


# ==========================================
# GIAO TIEP WEBSOCKET & DONG GOI GOI TIN
# ==========================================
func _is_socket_active() -> bool:
	return _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func _try_connect_socket() -> void:
	if offline_preview_enabled: return
	if "--no-save" in OS.get_cmdline_user_args(): return
	_socket.close()
	var err := _socket.connect_to_url(server_url)
	if err != OK:
		push_warning("[BackendPoseProvider] Khong the ket noi toi: %s (Error code: %d)" % [server_url, err])


func _send_client_hello() -> void:
	_send_envelope("client_hello", {
		"application": "shoulder-rehabilitation-game",
		"frontend": "godot",
		"frontend_version": "0.1.0",
		"platform": OS.get_name().to_lower(),
		"requested_pose_fps": 15,
	})


func _send_envelope(msg_type: String, payload: Dictionary) -> void:
	if not _is_socket_active():
		return

	_message_counter += 1
	var session_value: Variant = null
	if not active_session_id.is_empty():
		session_value = active_session_id

	var envelope := {
		"contract_version": CONTRACT_VERSION,
		"type": msg_type,
		"message_id": "godot-msg-%06d" % _message_counter,
		"session_id": session_value,
		"timestamp_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"source": "frontend",
		"payload": payload,
	}
	_socket.send_text(JSON.stringify(envelope))


# ==========================================
# TRIEN KHAI CAC PHUONG THUC CUA POSE_PROVIDER
# ==========================================
func open_connection() -> void:
	_try_connect_socket()


func close_connection() -> void:
	_cancel_movement()
	_socket.close()
	_was_connected = false
	_connected = false
	provider_connected = false
	_tracking = false
	_calibrating = false
	connection_changed.emit(false, {"reason": "manual_close"})


func start_calibration(request: Dictionary) -> void:
	active_session_id = str(request.get("session_id", active_session_id))
	active_exercise_id = str(request.get("exercise_id", _current_exercise_id()))
	_calibration_duration_ms = float(request.get("duration_ms", 5000))

	if _is_socket_active():
		_send_envelope("start_calibration", {
			"exercise_id": active_exercise_id,
			"duration_ms": int(_calibration_duration_ms),
			"target_side": str(request.get("target_side", "both")),
			"camera_view": str(request.get("camera_view", "front")),
		})
	else:
		# Fallback cho mock mode
		_calibration_elapsed_ms = 0.0
		_calibrating = true


func start_exercise(request: Dictionary) -> void:
	_cancel_movement()
	last_exercise_request = request.duplicate(true)
	active_session_id = str(request.get("session_id", active_session_id))
	active_exercise_id = str(request.get("exercise_id", DEFAULT_EXERCISE_ID))
	_paused = false
	_rep_counter = 0

	if _is_socket_active():
		_send_envelope("start_exercise", request)
	else:
		set_tracking(true)


func pause_exercise(reason := "user_paused") -> void:
	_cancel_movement()
	_paused = true
	if _is_socket_active():
		_send_envelope("pause_exercise", {"reason": reason})


func resume_exercise() -> void:
	_paused = false
	if _is_socket_active():
		_send_envelope("resume_exercise", {})


func stop_exercise(reason := "user_cancelled") -> void:
	_cancel_movement()
	_paused = false
	_calibrating = false

	if _is_socket_active():
		_send_envelope("stop_exercise", {"reason": reason})

	active_exercise_id = ""
	active_session_id = ""


# ==========================================
# CAC HAM HO TRO MOCK & UNIT TESTS
# ==========================================
func set_tracking(enabled: bool) -> void:
	_tracking = enabled
	if not enabled:
		_cancel_movement()
	if not _is_socket_active():
		handle_message(_make_mock_message("tracking_status", {
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
	handle_message(_make_mock_message("pose_frame", {
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
	_emit_mock_standard_valid_rep()


func _emit_mock_standard_valid_rep() -> void:
	_rep_counter += 1
	var candidate_id := "mock-rep-%04d" % _rep_counter
	_emit_mock_exercise_event("movement_started", candidate_id, {
		"quality": 0.90,
		"feedback_code": "MOVEMENT_STARTED",
	})
	_emit_mock_exercise_event("target_reached", candidate_id, {
		"quality": 0.92,
		"feedback_code": "TARGET_REACHED",
	})
	_emit_mock_exercise_event("rep_completed", candidate_id, {
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
	_emit_mock_exercise_event("movement_started", candidate_id, {"feedback_code": "MOVEMENT_STARTED"})
	_emit_mock_exercise_event("target_reached", candidate_id, {"feedback_code": "TARGET_REACHED"})
	_emit_mock_exercise_event("hold_started", candidate_id, {
		"hold_target_ms": target_ms,
		"feedback_code": "HOLD_STARTED",
	})
	for step in range(1, steps + 1):
		if generation != _movement_generation:
			return
		if not _connected or not _tracking or _paused or active_exercise_id.is_empty():
			_emit_mock_exercise_event("hold_interrupted", candidate_id, {
				"hold_target_ms": target_ms,
				"feedback_code": "HOLD_INTERRUPTED",
			})
			return
		if step_seconds > 0.0:
			await get_tree().create_timer(step_seconds, false).timeout
		if generation != _movement_generation:
			return
		var elapsed_ms := int(round(float(target_ms) * float(step) / float(steps)))
		_emit_mock_exercise_event("hold_progress", candidate_id, {
			"hold_elapsed_ms": elapsed_ms,
			"hold_target_ms": target_ms,
			"hold_progress": float(step) / float(steps),
			"feedback_code": "HOLD_PROGRESS",
		})
	_hold_running = false
	_emit_mock_exercise_event("hold_completed", candidate_id, {
		"hold_target_ms": target_ms,
		"feedback_code": "HOLD_COMPLETED",
	})
	_emit_mock_exercise_event("rep_completed", candidate_id, {
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
	_emit_mock_exercise_event("movement_started", candidate_id, {"feedback_code": "MOVEMENT_STARTED"})
	_emit_mock_exercise_event("target_reached", candidate_id, {"feedback_code": "TARGET_REACHED"})
	_emit_mock_exercise_event("hold_started", candidate_id, {"hold_target_ms": target_ms})
	_emit_mock_exercise_event("hold_progress", candidate_id, {
		"hold_elapsed_ms": int(float(target_ms) * 0.4),
		"hold_target_ms": target_ms,
		"hold_progress": 0.4,
	})
	_emit_mock_exercise_event("hold_interrupted", candidate_id, {
		"hold_target_ms": target_ms,
		"feedback_code": feedback_code,
	})
	_emit_mock_exercise_event("rep_rejected", candidate_id, {
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
	_emit_mock_exercise_event("movement_started", candidate_id, {
		"quality": 0.60,
		"feedback_code": "MOVEMENT_STARTED",
	})
	_emit_mock_exercise_event("rep_rejected", candidate_id, {
		"duration_ms": 700,
		"max_rom_ratio": 0.65,
		"hold_duration_ms": 0,
		"quality": 0.35,
		"feedback_code": feedback_code,
	})


func _update_mock_calibration(delta: float) -> void:
	if not _tracking:
		return
	_calibration_elapsed_ms += delta * 1000.0
	var progress := clampf(_calibration_elapsed_ms / _calibration_duration_ms, 0.0, 1.0)
	handle_message(_make_mock_message("calibration_progress", {
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
		handle_message(_make_mock_message("calibration_completed", {
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


func _emit_mock_exercise_event(event_name: String, candidate_id: String, extra: Dictionary) -> void:
	var payload := {
		"exercise_id": _current_exercise_id(),
		"event": event_name,
		"rep_candidate_id": candidate_id,
	}
	payload.merge(extra, true)
	handle_message(_make_mock_message("exercise_event", payload))


func _make_mock_message(message_type: String, payload: Dictionary) -> Dictionary:
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


func _cancel_movement() -> void:
	_movement_generation += 1
	_hold_running = false


func _can_simulate_movement() -> bool:
	if not _connected or _paused or not _tracking or active_exercise_id.is_empty():
		return false
	return true


func _current_exercise_id() -> String:
	return DEFAULT_EXERCISE_ID if active_exercise_id.is_empty() else active_exercise_id


# Explicit local preview: reuse existing simulator, never reconnect to live input.
func begin_offline_preview() -> void:
	if not OS.is_debug_build(): return
	if offline_preview_enabled: return
	stop_exercise("offline_preview")
	_preview_auto_reconnect = auto_reconnect
	auto_reconnect = false
	close_connection()
	offline_preview_enabled = true
	_connected = true
	provider_connected = true
	last_pose_frame.clear()
	connection_changed.emit(true, {"pose_engine": "mock", "camera_available": false})
	set_tracking(true)


func end_offline_preview() -> void:
	if not offline_preview_enabled: return
	stop_exercise("offline_preview_ended")
	close_connection()
	offline_preview_enabled = false
	last_pose_frame.clear()
	last_tracking_status.clear()
	last_tracking_received_ms = -10000
	auto_reconnect = _preview_auto_reconnect
	open_connection()
