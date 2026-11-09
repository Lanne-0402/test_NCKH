extends Node
func _ready() -> void: call_deferred("_run")
func _settle() -> void:
	await get_tree().create_timer(0.2).timeout
func _run() -> void:
	assert(not Global.persistence_enabled)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1152,648)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var screen = load("res://ui/screens/calibration/calibration_screen.tscn").instantiate()
	viewport.add_child(screen)
	await _settle()
	for dimensions in [Vector2i(1152,648), Vector2i(1600,900), Vector2i(800,600)]:
		viewport.size = dimensions
		await _settle()
		var camera = screen.get_node("%ColorRect2")
		var card = screen.get_node("%InstructionCard")
		var status = screen.get_node("%PoseStatusPanel")
		var toggle = screen.get_node("%DebugToggle")
		var columns = card.get_parent()
		print("LAYOUT ", dimensions, " camera=",camera.size," card=",card.size," status=",status.get_global_rect()," next-bottom=",screen.next_button.get_global_rect().end.y)
		assert(status.is_ancestor_of(toggle))
		assert(not screen.get_node("%DebugPanel").visible)
		assert(screen.start_button.disabled and screen.next_button.disabled)
		if dimensions.x >= 900:
			assert(not columns.vertical)
			assert(camera.size.x >= card.size.x * 1.5)
			assert(screen.next_button.get_global_rect().end.y <= dimensions.y - 15)
			assert(status.get_global_rect().end.y <= dimensions.y - 15)
		else:
			assert(columns.vertical)
			assert(camera.size.x <= dimensions.x - 30)
		assert(screen.get_node("%Steps").get_global_rect().end.y <= screen.get_node("%RomLabel").global_position.y)
		var before_size: Vector2 = status.size
		var before_camera: Rect2 = camera.get_global_rect()
		screen._toggle_technical_info()
		await _settle()
		assert(status.size == before_size and camera.get_global_rect() == before_camera)
		assert(not status.is_ancestor_of(screen.get_node("%DebugPanel")))
		assert(screen.get_node("TechnicalOverlay").visible)
		assert(status.size.x == columns.size.x)
		assert(screen.get_node("%Text").text.contains("Chỉ số 0–90"))
		assert(screen.get_node("%Text").size.y < 360)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png("res://calibration-spacing-%d-details.png" % dimensions.x)
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		screen._unhandled_key_input(escape)
		assert(not screen.get_node("TechnicalOverlay").visible)
		await _settle()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png("res://calibration-spacing-%d.png" % dimensions.x)
	viewport.queue_free()
	await get_tree().process_frame
	print("CALIBRATION_COMPACT_PASS")
	get_tree().quit()

