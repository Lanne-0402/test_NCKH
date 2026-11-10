class_name WebPoseProvider
extends PoseProvider

## Bo cung cap du lieu nhan dien cu dong Pose chuyen dung cho moi truong Trinh duyet Web (HTML5/WebAssembly).
## Giao tiep truc tiep voi MediaPipe JS Bridge chay tren trinh duyet thong qua JavaScriptBridge,
## khong can WebSocket, khong do tre mang, dam bao toc do 60 FPS muot ma.

var _message_counter := 0
var _js_message_callback: JavaScriptObject
var _js_camera_callback: JavaScriptObject


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		_setup_javascript_callbacks()


func _setup_javascript_callbacks() -> void:
	_js_message_callback = JavaScriptBridge.create_callback(_on_js_message)
	_js_camera_callback = JavaScriptBridge.create_callback(_on_js_camera_frame)

	var window = JavaScriptBridge.get_interface("window")
	if window != null:
		window.godotReceiveMessage = _js_message_callback
		window.godotReceiveCameraFrame = _js_camera_callback
		print("[WebPoseProvider] Da dang ky thanh cong JavaScript callbacks voi window.")


func _on_js_message(args: Array) -> void:
	if args.is_empty():
		return
	var raw_str := str(args[0])
	if raw_str.is_empty():
		return
	var parser := JSON.new()
	if parser.parse(raw_str) == OK and parser.data is Dictionary:
		handle_message(parser.data)
	else:
		push_warning("[WebPoseProvider] Khong parse duoc JSON tu JS: %s" % raw_str)


func _on_js_camera_frame(args: Array) -> void:
	if args.is_empty():
		return
	var b64 := str(args[0])
	if b64.is_empty():
		return
	var raw_bytes := Marshalls.base64_to_raw(b64)
	if raw_bytes.is_empty():
		return
	var img := Image.new()
	if img.load_jpg_from_buffer(raw_bytes) == OK:
		camera_frame_received.emit(img)


func open_connection() -> void:
	_send_envelope("client_hello", {
		"application": "shoulder-rehabilitation-game",
		"frontend": "godot-web",
		"frontend_version": "0.1.0",
		"platform": "web",
		"requested_pose_fps": 15,
	})


func close_connection() -> void:
	provider_connected = false
	connection_changed.emit(false, {"reason": "web_manual_close"})
	_send_envelope("stop_exercise", {"reason": "web_manual_close"})


func start_calibration(request: Dictionary) -> void:
	active_session_id = str(request.get("session_id", active_session_id))
	active_exercise_id = str(request.get("exercise_id", "scapular_retraction"))
	_send_envelope("start_calibration", request)


func start_exercise(request: Dictionary) -> void:
	active_session_id = str(request.get("session_id", active_session_id))
	active_exercise_id = str(request.get("exercise_id", "scapular_retraction"))
	_send_envelope("start_exercise", request)


func pause_exercise(reason := "user_paused") -> void:
	_send_envelope("pause_exercise", {"reason": reason})


func resume_exercise() -> void:
	_send_envelope("resume_exercise", {})


func stop_exercise(reason := "user_cancelled") -> void:
	_send_envelope("stop_exercise", {"reason": reason})
	active_exercise_id = ""
	active_session_id = ""


func _send_envelope(msg_type: String, payload: Dictionary) -> void:
	if not OS.has_feature("web"):
		return
	_message_counter += 1
	var session_value: Variant = null
	if not active_session_id.is_empty():
		session_value = active_session_id

	var envelope := {
		"contract_version": CONTRACT_VERSION,
		"type": msg_type,
		"message_id": "godot-web-%06d" % _message_counter,
		"session_id": session_value,
		"timestamp_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"source": "frontend",
		"payload": payload,
	}
	var json_str := JSON.stringify(envelope)

	var window = JavaScriptBridge.get_interface("window")
	if window != null and window.GamePHCN_Bridge != null:
		window.GamePHCN_Bridge.receiveGodotCommand(json_str)
	else:
		# Fallback eval an toan
		var esc := json_str.c_escape()
		JavaScriptBridge.eval("if (window.GamePHCN_Bridge && window.GamePHCN_Bridge.receiveGodotCommand) { window.GamePHCN_Bridge.receiveGodotCommand(\"%s\"); }" % esc)
