extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	assert(not Global.persistence_enabled)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1152, 760))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1152, 760)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	Global.rom_history = []
	for i in range(12): Global.rom_history.append({"date": "2026-10-%02d" % (i+1), "source": "calibration", "rom_angle": 65.0 + i * 5})
	Global.session_history = [{"session_id": "visual-only", "patient_id": "BN001", "status": "completed", "map_id": 2, "difficulty": 1, "valid_reps": 10, "rejected_reps": 1, "completed_at_utc": "2026-11-01T08:00:00", "calibration_rom_angle": 120, "active_seconds": 125}]
	var screen = load("res://ui/screens/history/history_screen.tscn").instantiate()
	viewport.add_child(screen)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://report-wide.png")
	screen.get_node("Margin/Column/Scroll").scroll_vertical = 230
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://report-chart.png")
	screen.get_node("Margin/Column/Scroll").scroll_vertical = 0
	assert(screen.get_node("Margin/Column/Scroll").size.y > 300)
	viewport.size = Vector2i(800, 600)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://report-small.png")
	print("REPORT_VISUAL_PASS")
	get_tree().quit()
