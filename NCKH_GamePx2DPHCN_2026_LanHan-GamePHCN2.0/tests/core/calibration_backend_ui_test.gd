extends Node
func _ready() -> void: call_deferred("_run")
func _run() -> void:
	if not PoseInput.has_signal("camera_frame_received"):
		PoseInput.add_user_signal("camera_frame_received", [{"name":"image","type":TYPE_OBJECT}])
	var scene = load("res://ui/screens/calibration/calibration_screen.tscn").instantiate()
	add_child(scene)
	await get_tree().create_timer(.1).timeout
	scene._on_connection_changed(true, {"pose_engine":"mediapipe","camera_available":true})
	scene._update_start_button()
	assert(scene.start_button.disabled)
	var sample := Image.create(480,360,false,Image.FORMAT_RGB8)
	sample.fill(Color("26434b"))
	PoseInput.emit_signal("camera_frame_received", sample)
	scene._on_tracking_status_changed({"status":"tracking","person_detected":true,"required_body_visible":true,"feedback_code":"POSITION_OK"})
	assert(not scene.start_button.disabled)
	assert(scene._camera_view.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	assert(scene._camera_view.texture.get_size() == Vector2(480,360))
	var texture = scene._camera_view.texture
	PoseInput.emit_signal("camera_frame_received", sample)
	assert(scene._camera_view.texture == texture)
	scene.is_calibrating = true
	scene._on_calibration_progressed({"exercise_id":"scapular_retraction","progress":.4,"elapsed_ms":2000,"duration_ms":5000,"tracking_valid":true,"current_rom_value":42,"rom_unit":"degree"})
	assert(scene.get_node("ProgressCaption").text.contains("2.0 / 5.0"))
	assert(scene.get_node("RomLabel").text.contains("42.0"))
	scene._on_calibration_progressed({"exercise_id":"scapular_retraction","progress":.6,"tracking_valid":false})
	assert(scene.progress_bar.value == 60 and scene.introduce.text.contains("BE vẫn đếm"))
	scene._last_frame_ms = -10000
	scene._process(0)
	assert(scene.start_button.disabled and scene._camera_view.texture == null)
	PoseInput.emit_signal("camera_frame_received", sample)
	scene._on_tracking_status_changed({"status":"no_person","person_detected":true,"required_body_visible":false,"feedback_code":"LEFT_ARM_NOT_VISIBLE"})
	assert(scene.tracking_label.text.contains("tay trái") and scene.start_button.disabled)
	scene.queue_free()
	await get_tree().process_frame
	print("CALIBRATION_BACKEND_UI: PASS (Image signal, aspect, texture reuse, readiness, timeout, progress, feedback)")
	get_tree().quit()
