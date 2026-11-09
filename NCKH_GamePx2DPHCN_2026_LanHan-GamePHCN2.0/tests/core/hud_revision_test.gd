extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	for id in range(1,6):
		Global.selected_action = id
		var level = load("res://maps/map_%d/main_level.tscn" % id).instantiate()
		level.countdown_step_seconds = 0.01
		add_child(level)
		await get_tree().process_frame
		var p = level.get_node("GamePresentation")
		assert(level.feedback_label.position == Vector2(328,24))
		assert(level.hearts_label.position == Vector2(940,24))
		assert(level.hearts_label.get_rect().end.x<=1152)
		assert(level.feedback_label.get_rect().end.x<level.hearts_label.position.x)
		assert(level.feedback_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER)
		assert(level.feedback_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART)
		assert(p.status_display.position.x == level.rep_label.position.x)
		assert(not level.state_label.visible)
		for value in p.STATUS_COLORS:
			level.state_label.text = "TRẠNG THÁI: "+value
			p._sync_status()
			assert(p.status_display.text.begins_with("TRẠNG THÁI: [color=#"))
			assert(p.STATUS_COLORS[value] in p.status_display.text)
			var width: float = p.status_display.get_theme_font("normal_font").get_string_size("TRẠNG THÁI: "+value,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
			assert(width<=p.status_display.size.x)
		level.instruction_start_button.pressed.emit()
		for frame in range(180):
			if level.exercise_session.state == ExerciseSession.State.ACTIVE: break
			await get_tree().process_frame
		assert(level.exercise_session.state == ExerciseSession.State.ACTIVE)
		p._sync_status()
		assert("75e889" in p.status_display.text)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/visual_output/hud_revision_map%d.png" % id)
		level.get_node("SettingsMenu").open_menu()
		await get_tree().process_frame
		await get_tree().process_frame
		assert("ffdc69" in p.status_display.text and "TẠM DỪNG" in p.status_display.text)
		level.get_node("SettingsMenu").close_menu()
		await get_tree().process_frame
		await get_tree().process_frame
		assert("75e889" in p.status_display.text)
		level.queue_free()
		await get_tree().process_frame
	print("HUD_REVISION: PASS (5 maps, alignment, centered wrap, bounds, state colors, actual pause/resume)")
	get_tree().quit()
