extends Node

func _ready() -> void: call_deferred("_run")

func _run() -> void:
	assert(not Global.persistence_enabled)
	Global.selected_action = 2
	var map = load("res://maps/map_2/main_level.tscn").instantiate()
	add_child(map)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud = map.get_node("GamePresentation")
	assert(not hud.rom_panel.visible)
	assert(hud.camera_bg.size.x == 528)
	assert(hud.camera_title.get_global_rect().end.x <= hud.camera_toggle_btn.get_global_rect().position.x)
	assert(not hud.camera_placeholder.text.contains("R:"))
	map.exercise_session.hold_progress_changed.emit(0.4, 2000, 5000)
	PoseInput.pose_frame_received.emit({"exercise":{"rom_progress":0.6,"hold_progress":0.0,"movement_state":"ready"}})
	assert(hud.hold_bar.value == 40)
	assert(hud.hold_title_label.text.contains("2.0s / 5.0s"))
	assert(hud.rom_state_label.text == "Trạng thái: Sẵn sàng")
	assert(hud._movement_state_text("RAISING") == "Đang nâng tay")
	hud.rom_panel.show()
	hud._update_camera_layout()
	await get_tree().process_frame
	assert(hud.camera_title.text == "CAMERA")
	assert(hud.camera_title.get_global_rect().end.x <= hud.camera_toggle_btn.get_global_rect().position.x)
	var sample := Image.create(320,240,false,Image.FORMAT_RGB8)
	sample.fill(Color("26434b"))
	PoseInput.camera_frame_received.emit(sample)
	assert(hud.camera_rect.texture != null and not hud.camera_placeholder.visible)
	var previous_texture = hud.camera_tex
	PoseInput.camera_frame_received.emit(sample)
	assert(hud.camera_tex == previous_texture)
	hud._last_camera_frame_ms = Time.get_ticks_msec() - 3001
	# Keep timestamp positive even immediately after boot.
	if hud._last_camera_frame_ms < 0:
		await get_tree().create_timer(3.1).timeout
		hud._last_camera_frame_ms = Time.get_ticks_msec() - 3001
	hud._refresh_camera_freshness()
	assert(hud.camera_rect.texture == null and hud.camera_placeholder.visible)
	PoseInput.camera_frame_received.emit(sample)
	assert(not hud.camera_placeholder.visible)
	PoseInput.connection_changed.emit(false,{})
	assert(hud.camera_rect.texture == null and hud.camera_tex == null)
	assert(hud.hold_bar.value == 0)
	PoseInput.connection_changed.emit(true,{})
	assert(hud.camera_placeholder.text.contains("Đang chờ"))
	PoseInput.camera_frame_received.emit(sample)
	assert(not hud.camera_placeholder.visible)
	var key := InputEventKey.new()
	key.keycode = KEY_C
	key.physical_keycode = KEY_C
	key.pressed = true
	PoseInput._calibrating = false
	Input.parse_input_event(key)
	await get_tree().process_frame
	assert(hud.is_camera_focused)
	assert(not PoseInput._calibrating)
	assert(hud.camera_title.get_global_rect().end.x <= hud.camera_toggle_btn.get_global_rect().position.x)
	map.queue_free()
	await get_tree().process_frame
	print("CAMERA_UI_PASS: hidden debug, title layout, hold stability, stale/disconnect/reconnect, C isolation")
	get_tree().quit()
