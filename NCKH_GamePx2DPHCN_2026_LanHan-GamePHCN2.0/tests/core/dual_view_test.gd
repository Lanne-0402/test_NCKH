extends Node
const Pose = preload("res://ui/shared/guide_pose.gd")
func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(not Global.persistence_enabled)
	PoseInput.begin_offline_preview()
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://tests/visual_output")
	# Full motion sweep: segment lengths, projections, handedness and layout.
	for id in range(1,6):
		Global.selected_action = id
		var level = load("res://maps/map_%d/main_level.tscn" % id).instantiate()
		level.countdown_step_seconds = 0.01
		add_child(level)
		await get_tree().process_frame
		var presenter = level.get_node("GamePresentation")
		var guide = presenter.intro_guide
		guide.set_process(false)
		assert(guide.side_actor.side_view and guide.side_actor.joints_visible)
		for sample in range(301):
			guide.seconds = sample/20.0
			guide._update()
			assert(guide.actor.amount == guide.side_actor.amount)
			assert(guide.actor.other_side == guide.side_actor.other_side)
			for side in [-1,1]:
				var p = Pose.arm(id,side,guide.actor.amount,guide.actor.other_side)
				assert(absf(p[0].distance_to(p[1])-14)<0.002)
				assert(absf(p[1].distance_to(p[2])-14)<0.002)
				for view in [guide.actor,guide.side_actor]:
					var points = view.endpoints(side)
					for index in range(3):
						assert(points[index].is_equal_approx(Pose.project(p[index],view.side_view)))
						var screen: Vector2 = view.position+points[index]*view.scale
						assert(screen.y-12>122 and screen.y+12<384,"Vertical bounds map %d sample %d side %d point %s" % [id,sample,side,str(screen)])
						assert(screen.x>24 and screen.x<816)
				if id == 1:
					var bend := (p[1]-p[0]).normalized().dot((p[2]-p[1]).normalized())
					assert(absf(bend-cos(guide.actor.amount*PI/2))<0.001)
				if id == 4:
					assert(p[2].is_equal_approx(Vector3(side*3,-60,-5)))
				if id == 3:
					assert(is_equal_approx(p[1].x,p[2].x))
					assert(is_equal_approx(p[1].z,p[2].z))
					assert(absf((p[1]-p[0]).normalized().dot((p[2]-p[1]).normalized()))<0.001)
				if id == 5:
					var reflected = Pose.arm(id,-side,guide.actor.amount,not guide.actor.other_side)
					for index in range(3):
						assert(p[index].is_equal_approx(Vector3(-reflected[index].x,reflected[index].y,reflected[index].z)))
		var before = Pose.arm(id,1,0)
		var after = Pose.arm(id,1,1)
		match id:
			1:
				assert(after[0].z<before[0].z and after[1].z<before[1].z)
				assert(is_equal_approx(before[0].y,before[2].y))
				assert(is_equal_approx(before[2].z-before[0].z,28.0))
				for instant in [0.0,2.9,15.0]:
					guide.seconds = instant
					guide._update()
					assert(guide.actor.amount == 0.0)
					assert(guide.caption.text.to_lower().contains("duỗi"))
			2: assert(after[2].y<before[2].y)
			3:
				assert(absf(before[1].x)<=2.01,"Reference: elbows together, not just wrists")
				assert(after[1].x>before[1].x and after[1].z<before[1].z)
			4: assert(after[1].z>before[1].z and absf(after[1].x)<absf(before[1].x))
			5:
				assert(before[2].y>before[0].y,"Preparation arms must hang downward")
				var stretched = Pose.arm(5,-1,1)
				assert(after[2].distance_to(stretched[1])>4,"Support must not press elbow")
				assert(((after[1]+after[2])*0.5).distance_to(stretched[0].lerp(stretched[1],0.6))<1.01,"Mid forearm must support upper arm")
		if DisplayServer.get_name() != "headless":
			for instant in [0.0,4.0,8.0,11.5,15.0]:
				guide.seconds = instant
				guide._update()
				await RenderingServer.frame_post_draw
				assert(get_viewport().get_texture().get_image().save_png("res://tests/visual_output/dual_map%d_%s.png" % [id,str(instant).replace(".","_")]) == OK)
		# Settings freezes both views during the initial guide.
		guide.set_process(true)
		var menu = level.get_node("SettingsMenu")
		menu.open_menu()
		var frozen: float = guide.seconds
		await get_tree().create_timer(0.05).timeout
		assert(guide.seconds == frozen)
		menu.close_menu()
		guide.seconds = 14.99
		guide._process(0.02)
		for frame in range(180):
			if level.exercise_session.state == ExerciseSession.State.ACTIVE: break
			await get_tree().process_frame
		assert(level.exercise_session.state == ExerciseSession.State.ACTIVE)
		presenter._review()
		assert(get_tree().paused and presenter.replay_guide.side_actor.side_view)
		presenter.replay_guide.seconds = 14.99
		presenter._process(0.02)
		presenter._process(3.1)
		assert(not get_tree().paused)
		level.queue_free()
		await get_tree().process_frame
	print("DUAL_VIEW: PASS (1505 frames, 3D lengths/projections, 5 motion directions, fixed hands map4, map5 support/swap, bounds, pause/replay)")
	get_tree().quit()
