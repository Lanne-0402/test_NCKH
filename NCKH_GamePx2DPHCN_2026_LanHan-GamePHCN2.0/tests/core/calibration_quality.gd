extends Node
var screen: Control
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	assert(not Global.persistence_enabled)
	screen = load("res://ui/screens/calibration/calibration_screen.tscn").instantiate()
	add_child(screen)
	await get_tree().process_frame
	assert(screen.start_button.disabled and screen.next_button.disabled)
	assert(not screen.get_node("%DebugPanel").visible)
	screen._toggle_technical_info()
	assert(screen.get_node("%DebugPanel").visible)
	assert(screen._technical_info_text().contains("Chưa kết nối"))
	assert(not screen._technical_info_text().contains("Giả lập:"))
	screen._toggle_technical_info()
	PoseInput.provider_connected = true
	screen._on_tracking_status_changed({"person_detected":true,"required_body_visible":true})
	screen._on_camera_frame_received(Image.create(16,16,false,Image.FORMAT_RGB8))
	PoseInput.last_tracking_status = {"camera_fps": 29.5}
	assert(screen._technical_info_text().contains("29.5 FPS"))
	assert(screen._technical_info_text().contains("16 × 16 px"))
	assert(not screen.start_button.disabled)
	# Avoid invoking the provider; construct the pending session directly.
	screen.is_calibrating = true
	screen._session_id = "test-current"
	screen._patient_id = Global.current_patient_id
	screen._started_ms = Time.get_ticks_msec()
	Global.rom_history = []
	var result := {"session_id":"old", "exercise_id":"scapular_retraction", "success":true,"max_rom":{"combined":75.0},"measurement_kind":"normalized_t_pose","valid_elapsed_ms":5000,"valid_sample_count":60}
	screen._on_calibration_finished(result)
	assert(screen.is_calibrating and Global.rom_history.is_empty())
	result.session_id = "test-current"
	result.valid_elapsed_ms = 100
	screen._on_calibration_finished(result)
	assert(not screen._calibration_success and Global.rom_history.is_empty())
	screen.is_calibrating = true
	result.valid_elapsed_ms = 5000
	screen._on_calibration_finished(result)
	assert(screen._calibration_success and Global.rom_history.size() == 1)
	assert(not screen.next_button.disabled)
	screen._on_connection_changed(false,{})
	PoseInput.provider_connected = false
	assert(not screen._technical_info_text().contains("29.5 FPS"))
	assert(screen.next_button.disabled)
	screen._on_calibration_finished(result)
	assert(not screen._calibration_success)
	# No active session and missing/mismatched envelopes are rejected centrally.
	PoseInput.active_session_id = ""
	var envelope := {"contract_version":"1.0.0","type":"calibration_completed","message_id":"late","session_id":"old","timestamp_ms":1,"source":"backend","payload":result}
	assert(not PoseInput.handle_message(envelope))
	screen.queue_free()
	await get_tree().process_frame
	print("CALIBRATION_QUALITY_PASS")
	get_tree().quit()
