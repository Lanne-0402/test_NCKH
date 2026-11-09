extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	assert(not Global.persistence_enabled)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1152,760))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1152,760)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var screen = load("res://ui/screens/calibration/calibration_screen.tscn").instantiate()
	viewport.add_child(screen)
	screen._toggle_technical_info()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://calibration-wide.png")
	# Assert real label rectangles do not overlap after wrapping.
	var heading = screen.get_node("%Label2")
	var steps = screen.get_node("%Steps")
	var rom = screen.get_node("%RomLabel")
	assert(heading.get_global_rect().end.y <= steps.global_position.y)
	assert(steps.get_global_rect().end.y <= rom.global_position.y)
	viewport.size = Vector2i(800,600)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://calibration-small.png")
	var scroll = screen.get_node("ResponsiveLayout").get_child(0).get_node("ContentScroll")
	scroll.scroll_vertical = 10000
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://calibration-small-bottom.png")
	assert(heading.get_global_rect().end.y <= steps.global_position.y)
	assert(steps.get_global_rect().end.y <= rom.global_position.y)
	print("CALIBRATION_VISUAL_PASS")
	get_tree().quit()
