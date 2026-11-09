extends Node
func _ready() -> void: call_deferred("_run")
func _run() -> void:
	assert(not Global.persistence_enabled)
	PoseInput.begin_offline_preview()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1152,648)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	for id in range(1,6):
		Global.selected_action = id
		var map = load("res://maps/map_%d/main_level.tscn" % id).instantiate()
		viewport.add_child(map)
		await get_tree().create_timer(0.15).timeout
		map.instruction_panel.hide()
		map._intro_running = false
		assert(map.exercise_session.start_session(map._session_config))
		var hud = map.get_node("GamePresentation")
		if id == 3: map.direction_label.text = "HƯỚNG: HAI BÊN CHÉO 45°"
		if id == 5:
			map.phase_label.text = "HIỆP: 2/2"
			map.side_label.text = "BÊN: TAY PHẢI (ĐỔI BÊN)"
			map.bonus_label.text = "ĐIỂM THƯỞNG: 100/100"
			map.hold_label.text = "THIỀN GIỮ CĂNG: 6.0/30.0 GIÂY"
			map.hold_bar.value = 20
		elif id > 1:
			map.hold_label.text = "GIỮ: 2.0/5.0 GIÂY"
			map.hold_bar.value = 40
		await get_tree().create_timer(0.2).timeout
		var panel: Rect2 = hud.session_hud.get_global_rect()
		print("HUD ",id," ",panel)
		assert(panel.end.y <= 648 and panel.position.y >= 366)
		assert(panel.end.x <= 556)
		assert(map.phase_label.global_position.y == map.rep_label.global_position.y)
		assert(hud.guide_button.text == "Xem hướng dẫn [U]")
		for row in hud.session_hud.get_children():
			if row is HBoxContainer:
				var previous: Control = null
				for item in row.get_children():
					assert(item.get_global_rect().end.x <= panel.end.x + 1)
					if previous != null: assert(previous.get_global_rect().end.x <= item.global_position.x)
					previous = item
		if id == 5:
			assert(map.side_label.text == "BÊN: TAY PHẢI (ĐỔI BÊN)")
			assert(map.side_label.get_line_count() == 1)
			assert(map.bonus_label.get_line_count() == 1)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png("res://gameplay-hud-map%d.png" % id)
		map.state_label.text = "TRẠNG THÁI: MẤT NHẬN DIỆN"
		hud._sync_status()
		await get_tree().create_timer(0.1).timeout
		assert(hud.session_hud.get_global_rect().end.y <= 648)
		assert(hud.status_display.global_position.x == map.rep_label.global_position.x)
		# Verify the relocated guide button still opens the pause overlay.
		hud.guide_button.pressed.emit()
		assert(get_tree().paused and is_instance_valid(hud.replay))
		map.queue_free()
		await get_tree().process_frame
		assert(not get_tree().paused)
	viewport.queue_free()
	await get_tree().process_frame
	print("GAMEPLAY_HUD_PASS: all five layouts, long side/direction labels, guide action")
	get_tree().quit()
