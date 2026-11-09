extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(not Global.persistence_enabled)
	get_tree().current_scene = null
	for action in range(1,6):
		Global.selected_action = action
		get_tree().change_scene_to_file("res://maps/map_%d/main_level.tscn" % action)
		await get_tree().scene_changed
		await get_tree().process_frame
		var level = get_tree().current_scene
		var player = level.get_node("Player")
		var actor = player.mk2
		assert(actor.map_id == action)
		assert(actor.get_script().resource_path.ends_with("gameplay_actor.gd"))
		level.instruction_panel.hide()
		level._start_new_session_attempt()
		await get_tree().process_frame
		if action == 2:
			level.map2_controller._slab_descending = false
			level.map2_controller._set_action_window(true)
		elif action == 3:
			level.map3_controller._walls_closing = false
			level.map3_controller._set_action_window(true)
		if action == 5:
			assert(actor.leg_points(1)[2].y < -20)
			assert(player.mk2.position.y == 44)
		for amount in [0.0,0.35,1.0]:
			level.exercise_session.hold_progress_changed.emit(amount,int(amount*5000),5000)
			actor.amount = amount
			if action == 4:
				actor.jump_progress = 0.5 if amount == 1 else -1
			if action == 1:
				actor.charging = true
				actor.burst = amount
			actor.refresh()
			await get_tree().process_frame
			if action == 3 and amount == 1:
				var p = actor.endpoints(1)
				assert(is_zero_approx((p[1]-p[0]).cross(p[2]-p[1])))
			if action == 2 and amount >= 0.35:
				var palm: Vector2 = actor.to_global(actor.endpoints(1)[2])
				assert(absf(palm.y-level.get_node("Map2Slab").global_position.y) < 1.0)
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("user://action_map_%d_%d.png" % [action,int(amount*100)])
		actor.jump_progress = -1
		var before: int = level.exercise_session.total_valid_reps
		assert(before == 0)
		PoseInput.set_tracking(false)
		await get_tree().process_frame
		var stopped: float = actor.animation_clock
		await get_tree().create_timer(0.08).timeout
		assert(is_equal_approx(stopped,actor.animation_clock))
		PoseInput.set_tracking(true)
		await get_tree().create_timer(0.05).timeout
		assert(actor.animation_clock > stopped)
		print("PASS gameplay actor map ",action)
	print("GAMEPLAY_ACTIONS_AND_TRACKING_PAUSE: PASS")
	get_tree().quit()
