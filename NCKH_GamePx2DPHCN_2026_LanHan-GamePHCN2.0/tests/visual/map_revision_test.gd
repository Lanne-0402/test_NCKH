extends Node
func _ready() -> void:
	call_deferred("_run")
func shot(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tests/visual_output")
	assert(get_viewport().get_texture().get_image().save_png("res://tests/visual_output/revision_"+name+".png") == OK)
func _run() -> void:
	var rock = load("res://maps/map_1/obstacle.tscn").instantiate()
	rock.set_rock_variant(1)
	assert(rock.get_node("RockVisual/Base").texture.resource_path.ends_with("moss_boulder.png"))
	rock.free()
	for id in [2,3,4]:
		Global.selected_action = id
		var level = load("res://maps/map_%d/main_level.tscn" % id).instantiate()
		add_child(level)
		await get_tree().process_frame
		level.set_process(false)
		level.get_node("UI/InstructionPanel").hide()
		if id == 2:
			level.get_node("Map2Slab").position = Vector2(576,200)
			await shot("map2")
		if id == 3:
			var controller = level.get_node("Map3Controller")
			for direction in range(4):
				controller.current_direction = direction
				for retreat in [0.0,0.5,1.0]:
					controller._apply_wall_positions(1.0,retreat)
					for wall in [controller.wall_a,controller.wall_b]:
						var inward = (controller.CENTER-wall.position).normalized()
						assert(Vector2.RIGHT.rotated(wall.rotation).dot(inward)>0.98)
				controller._apply_wall_positions(1.0,0.0)
				if direction >= 2: await shot("diagonal_%d" % direction)
		if id == 4:
			var summit = level.get_node("World/Map4ClimbTrack/Step_10/SummitVisual")
			assert(summit.visible)
			var player = level.get_node("Player")
			player.set_movement_locked(true,Vector2(1020,80))
			await get_tree().physics_frame
			await get_tree().process_frame
			await shot("summit")
		level.queue_free()
		await get_tree().process_frame
	print("MAP_REVISION: PASS (moss variant, 4 inward normals at 3 gaps, visible goal)")
	get_tree().quit()
