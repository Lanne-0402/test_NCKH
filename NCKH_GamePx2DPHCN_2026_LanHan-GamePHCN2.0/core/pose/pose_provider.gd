class_name PoseProvider
extends Node

## Shared frontend contract for every pose-data source.
## Gameplay should listen to these signals instead of depending on WebSocket,
## MediaPipe, or mock keyboard input directly.

signal connection_changed(is_connected: bool, details: Dictionary)
signal tracking_status_changed(status: Dictionary)
signal calibration_progressed(data: Dictionary)
signal calibration_finished(data: Dictionary)
signal pose_frame_received(data: Dictionary)
signal exercise_event_received(data: Dictionary)
signal provider_error_received(data: Dictionary)
signal camera_frame_received(image: Image)
signal hand_control_received(data: Dictionary)

const CONTRACT_VERSION := "1.0.0"

var active_session_id := ""
var active_exercise_id := ""
var provider_connected := false
var last_pose_frame: Dictionary = {}
var last_tracking_status: Dictionary = {}
var last_tracking_received_ms := -10000


func open_connection() -> void:
	push_error("PoseProvider.open_connection() must be implemented by a subclass.")


func close_connection() -> void:
	push_error("PoseProvider.close_connection() must be implemented by a subclass.")


func start_calibration(_request: Dictionary) -> void:
	push_error("PoseProvider.start_calibration() must be implemented by a subclass.")


func start_exercise(_request: Dictionary) -> void:
	push_error("PoseProvider.start_exercise() must be implemented by a subclass.")


func pause_exercise(_reason := "user_paused") -> void:
	push_error("PoseProvider.pause_exercise() must be implemented by a subclass.")


func resume_exercise() -> void:
	push_error("PoseProvider.resume_exercise() must be implemented by a subclass.")


func stop_exercise(_reason := "user_cancelled") -> void:
	push_error("PoseProvider.stop_exercise() must be implemented by a subclass.")


## Both MockPoseProvider and the future BackendPoseProvider send messages here.
## This keeps validation and signal mapping identical for both implementations.
func handle_message(message: Dictionary) -> bool:
	if not _is_valid_envelope(message):
		return false

	var raw_session = message.get("session_id")
	var message_session := "" if (raw_session == null or str(raw_session) == "<null>") else str(raw_session)
	var msg_type := str(message.get("type", ""))

	var is_session_scoped := (msg_type != "server_hello" and msg_type != "error" and msg_type != "tracking_status" and msg_type != "camera_frame" and msg_type != "hand_control")
	if is_session_scoped and not active_session_id.is_empty() \
			and not message_session.is_empty() \
			and message_session != active_session_id:
		return false

	var payload: Dictionary = message.get("payload", {}).duplicate(true)
	if msg_type in ["calibration_progress", "calibration_completed"]:
		if active_session_id.is_empty() or message_session != active_session_id: return false
		payload["session_id"] = message_session

	match str(message.get("type", "")):
		"server_hello":
			provider_connected = true
			connection_changed.emit(true, payload)
		"tracking_status":
			last_tracking_received_ms = Time.get_ticks_msec()
			last_tracking_status = payload.duplicate(true)
			tracking_status_changed.emit(payload)
		"calibration_progress":
			calibration_progressed.emit(payload)
		"calibration_completed":
			calibration_finished.emit(payload)
		"pose_frame":
			last_pose_frame = payload.duplicate(true)
			pose_frame_received.emit(payload)
		"exercise_event":
			exercise_event_received.emit(payload)
		"camera_frame":
			var b64 := str(payload.get("image", ""))
			if not b64.is_empty():
				var raw_bytes := Marshalls.base64_to_raw(b64)
				var img := Image.new()
				if img.load_jpg_from_buffer(raw_bytes) == OK:
					camera_frame_received.emit(img)
		"hand_control":
			hand_control_received.emit(payload)
		"error":
			provider_error_received.emit(payload)
		_:
			push_warning("PoseProvider ignored unknown message type: %s" % message.get("type", ""))
			return false

	return true


func _is_valid_envelope(message: Dictionary) -> bool:
	var required_fields := [
		"contract_version",
		"type",
		"message_id",
		"timestamp_ms",
		"source",
		"payload",
	]

	for field in required_fields:
		if not message.has(field):
			push_warning("PoseProvider rejected message without field: %s" % field)
			return false

	if str(message["contract_version"]) != CONTRACT_VERSION:
		push_warning("Unsupported pose contract version: %s" % message["contract_version"])
		return false

	if message["source"] != "backend":
		push_warning("PoseProvider only accepts backend messages.")
		return false

	if not message["payload"] is Dictionary:
		push_warning("PoseProvider payload must be a Dictionary.")
		return false

	return true
