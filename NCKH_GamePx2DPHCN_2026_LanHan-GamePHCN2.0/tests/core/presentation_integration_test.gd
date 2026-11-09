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
		var g = p.intro_guide
		assert(g.map_id == id and g.actor.joints_visible and not g.actor.outfit_enabled)
		assert(level.get_node("Player").mk2.outfit_enabled)
		if DisplayServer.get_name() != "headless":
			g.seconds = 4.0 if id == 5 else 8.0
			g._update()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/visual_output/map%d_guide_pose.png" % id)
		for sample in range(150):
			g.seconds = sample/10.0
			g._update()
			for side in [-1,1]:
				for point in g.actor.endpoints(side):
					var projected: Vector2 = g.actor.position+point*g.actor.scale
					assert(projected.y+12 < 384 and projected.y-12 > 122)
		g.seconds = 14.99
		g._process(0.02)
		assert(not level.instruction_panel.visible)
		for frame in range(180):
			if level.exercise_session.state == ExerciseSession.State.ACTIVE: break
			await get_tree().process_frame
		assert(level.exercise_session.state == ExerciseSession.State.ACTIVE, "Map %d failed auto-start: state %d" % [id, level.exercise_session.state])
		var guide_buttons := 0
		for control in level.get_node("UI").get_children():
			if control is Button:
				assert(not control.text.begins_with("Ẩn/hiện khớp"))
				if control.text == "Xem hướng dẫn [U]":
					guide_buttons += 1
					assert(control.position == Vector2(24,596) and control.size.x == 516)
		assert(guide_buttons == 1)
		var reps: int = level.exercise_session.total_valid_reps
		p._review()
		assert(get_tree().paused and p.owns_pause)
		# Real GUI input, not pressed.emit(): catches paused buttons ignoring clicks.
		await get_tree().process_frame
		var skip: Button
		for control in p.replay.get_children():
			if control is Button: skip = control
		assert(skip != null and not skip.disabled and skip.can_process())
		assert(p.replay_guide.seconds < 15.0)
		var click_position := skip.get_global_rect().get_center()
		var move := InputEventMouseMotion.new()
		move.position = click_position
		get_viewport().push_input(move, true)
		for down in [true, false]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.position = click_position
			click.pressed = down
			get_viewport().push_input(click, true)
		assert(p.resuming >= 0, "Skip click must work while paused")
		p._process(3.1)
		assert(not get_tree().paused and level.exercise_session.total_valid_reps == reps)
		await get_tree().process_frame
		# Reopening without clicking must still finish automatically at 15 seconds.
		p._review()
		p.replay_guide.seconds = 14.99
		p._process(0.02)
		assert(p.resuming >= 0)
		p._process(3.1)
		assert(not get_tree().paused and not p.owns_pause)
		assert(level.exercise_session.total_valid_reps == reps)
		assert(not level.get_node("UI/SettingsButton").disabled)
		level.queue_free()
		await get_tree().process_frame
	print("PRESENTATION_INTEGRATION: PASS (5 poses, guide bounds, auto-start, replay pause/countdown, clothing)")
	get_tree().quit()
