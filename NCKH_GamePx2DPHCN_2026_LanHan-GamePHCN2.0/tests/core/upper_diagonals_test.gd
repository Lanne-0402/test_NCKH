extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	assert(not Global.persistence_enabled)
	get_tree().current_scene = null
	Global.selected_action = 3
	get_tree().change_scene_to_file("res://maps/map_3/main_level.tscn")
	await get_tree().scene_changed
	await get_tree().process_frame
	var level = get_tree().current_scene
	level.instruction_panel.hide()
	var controller = level.map3_controller
	var expected := [0,1,2,0,1,2,0,1,2,0]
	for i in range(10):
		controller._begin_wave(i)
		assert(controller.current_direction == expected[i])
	controller._begin_wave(2)
	controller._apply_wall_positions(1.0,0.0)
	assert(is_equal_approx(controller.wall_a.position.y,controller.wall_b.position.y))
	assert(is_equal_approx(controller.wall_a.position.x+controller.wall_b.position.x,1152.0))
	for wall in [controller.wall_a,controller.wall_b]:
		for corner in [Vector2(-40,-120),Vector2(72,-120),Vector2(-40,120),Vector2(72,120)]:
			assert(wall.to_global(corner).y < 320.0)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://map3_upper_diagonals.png")
	for value in [0.25,0.5,1.0]:
		controller._apply_wall_positions(1.0,value)
		assert(controller.wall_a.position.y == controller.wall_b.position.y)
	assert(level.exercise_session.total_valid_reps == 0)
	print("UPPER_DIAGONALS_SEQUENCE_BOUNDS: PASS")
	get_tree().quit()
