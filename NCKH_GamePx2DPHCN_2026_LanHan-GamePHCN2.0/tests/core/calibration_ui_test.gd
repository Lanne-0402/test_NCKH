extends Node
func _ready() -> void:
	call_deferred("_run")
func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://calibration_"+name+".png")
func _run() -> void:
	var scene = load("res://ui/screens/calibration/calibration_screen.tscn").instantiate()
	add_child(scene)
	await get_tree().create_timer(.2).timeout
	assert(not scene.start_button.disabled and scene.next_button.disabled)
	assert(not scene.get_node("DebugPanel").visible)
	await _shot("ready")
	scene.get_node("DebugToggle").pressed.emit()
	assert(scene.get_node("DebugPanel").visible)
	await _shot("debug")
	scene.get_node("DebugToggle").pressed.emit()
	scene.start_button.pressed.emit()
	assert(scene.is_calibrating and scene.start_button.disabled)
	scene._on_calibration_progressed({"exercise_id":"scapular_retraction","progress":.5})
	assert(scene.progress_bar.value == 50)
	scene._on_calibration_finished({"exercise_id":"scapular_retraction","success":false})
	assert(scene.next_button.disabled and not scene.is_calibrating)
	PoseInput.stop_exercise("test")
	scene._on_calibration_finished({"exercise_id":"scapular_retraction","success":true,"max_rom":{"combined":90}})
	assert(not scene.next_button.disabled and scene.progress_bar.value == 100)
	await _shot("complete")
	scene._on_connection_changed(false,{})
	assert(scene.next_button.disabled)
	await _shot("disconnected")
	scene.queue_free()
	await get_tree().process_frame
	print("CALIBRATION_UI: PASS (ready, debug, measuring, failure, success, disconnected)")
	get_tree().quit()
