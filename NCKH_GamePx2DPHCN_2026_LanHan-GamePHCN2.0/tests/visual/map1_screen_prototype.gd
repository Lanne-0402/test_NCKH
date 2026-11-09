extends Node2D
## Isolated visual/interaction prototype. Never calls session scoring or persistence.
const Actor = preload("res://tests/visual/map1_mk2_actor.gd")
const SideGuide = preload("res://tests/visual/map1_side_guide.gd")
const World = preload("res://tests/visual/map1_mk2_preview.gd")
var board: Node2D
var hud: Control
var modal: Control
var actor: Node2D
var guide_actor: Node2D
var side_actor: Node2D
var feedback: Label
var progress: Label
var phase_status: Label
var guide_caption: Label
var guide_timer: Label
var state := "guide"
var return_state := "play"
var elapsed := 0.0
var guide_time := 0.0
var countdown := 3.0
var tracking := true
var reps := 0
var volume := 70.0
var frozen := false
var rest_remaining := 0.0
var guide_resume_time := 0.0

func panel(parent: Node, rect: Rect2, color: Color) -> ColorRect:
	var item := ColorRect.new()
	item.position = rect.position
	item.size = rect.size
	item.color = color
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(item)
	return item

func label(parent: Node, value: String, rect: Rect2, size := 20, centered := false) -> Label:
	var item := Label.new()
	item.text = value
	item.position = rect.position
	item.size = rect.size
	item.add_theme_font_size_override("font_size",size)
	item.add_theme_color_override("font_color",Color("f2f3df"))
	item.add_theme_color_override("font_outline_color",Color("15231e"))
	item.add_theme_constant_override("outline_size",4)
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(item)
	return item

func button(parent: Node, value: String, rect: Rect2, action: Callable) -> Button:
	var item := Button.new()
	item.position = rect.position
	item.size = rect.size
	item.text = value
	item.add_theme_font_size_override("font_size",18)
	for color_name in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		item.add_theme_color_override(color_name,Color("f2f3df"))
	for style_name in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("334c43") if style_name == "normal" else Color("506c58")
		style.border_color = Color("acb792")
		style.set_border_width_all(1)
		style.set_content_margin_all(8)
		item.add_theme_stylebox_override(style_name,style)
	item.focus_mode = Control.FOCUS_NONE
	item.pressed.connect(action)
	parent.add_child(item)
	return item

func _ready() -> void:
	board = Node2D.new()
	add_child(board)
	get_viewport().size_changed.connect(_fit)
	_fit()
	var background = World.BACKGROUND.instantiate()
	board.add_child(background)
	background.set_scrolling(false)
	var ground = World.GROUND.instantiate()
	ground.position.y = 320
	board.add_child(ground)
	ground.get_node("Visuals/GrassTop").position.y = -10
	var rock = World.ROCK.instantiate()
	rock.position = Vector2(540,320)
	board.add_child(rock)
	var cave = World.CAVE.instantiate()
	cave.position = Vector2(1030,320)
	board.add_child(cave)
	actor = Actor.new()
	actor.position = Vector2(285,320)
	actor.scale = Vector2.ONE*2
	actor.pose_id = 3
	actor.outfit_enabled = true
	actor.joints_visible = false
	board.add_child(actor)
	hud = Control.new()
	hud.z_index = 20
	board.add_child(hud)
	var gear := button(hud,"",Rect2(24,20,52,52),_settings)
	gear.icon = preload("res://ui/shared/settings_gear.svg")
	gear.expand_icon = true
	gear.tooltip_text = "Cài đặt [Esc]"
	feedback = label(hud,"",Rect2(244,28,590,78),22,true)
	label(hud,"ỔN ĐỊNH: ♥ ♥ ♥",Rect2(860,30,268,44),22,true).add_theme_color_override("font_color",Color("ff7171"))
	panel(hud,Rect2(0,334,1152,314),Color(0.045,0.08,0.055,0.88))
	panel(hud,Rect2(575,350,2,274),Color("64795c"))
	label(hud,"MAP 1 · LUYỆN VAI",Rect2(28,350,510,30),22)
	progress = label(hud,"",Rect2(28,397,516,86),23)
	phase_status = label(hud,"",Rect2(28,478,510,30),18)
	button(hud,"Xem hướng dẫn [U]",Rect2(28,535,248,46),_open_guide)
	button(hud,"Ẩn/hiện khớp [I]",Rect2(290,535,254,46),_joints)
	label(hud,"BẢN THỬ · Không lưu kết quả hoặc tiến độ",Rect2(28,606,520,24),14)
	# Fixed 16:9 placeholder. A future TextureRect must KEEP_ASPECT_CENTERED.
	panel(hud,Rect2(602,348,522,294),Color("162822"))
	label(hud,"CAMERA NGƯỜI TẬP",Rect2(620,369,486,32),20,true)
	label(hud,"Chưa kết nối camera\n\nHình ảnh sẽ xuất hiện tại đây\nsau khi tích hợp camera + backend.",Rect2(626,429,474,150),20,true)
	label(hud,"Khung 16:9 • giữ đúng tỷ lệ hình ảnh",Rect2(618,602,490,26),14,true)
	_open_guide()
	_update_hud()
	if "--screen-smoke" in OS.get_cmdline_user_args(): call_deferred("_smoke")
	if "--screen-capture" in OS.get_cmdline_user_args(): call_deferred("_capture")

func _fit() -> void:
	var viewport_size := get_viewport_rect().size
	var factor := minf(viewport_size.x/1152,viewport_size.y/648)
	board.scale = Vector2.ONE*factor
	board.position = (viewport_size-Vector2(1152,648)*factor)/2

func _clear_modal() -> void:
	if is_instance_valid(modal):
		modal.get_parent().remove_child(modal)
		modal.queue_free()
	modal = null

func _new_modal(rect: Rect2) -> void:
	_clear_modal()
	modal = Control.new()
	modal.z_index = 50
	board.add_child(modal)
	var blocker := panel(modal,Rect2(0,0,1152,648),Color(0,0,0,0.7))
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	panel(modal,rect,Color("20372f"))

func _open_guide() -> void:
	state = "guide"
	guide_time = 0
	_new_modal(Rect2(116,28,920,586))
	label(modal,"HƯỚNG DẪN MAP 1 · ÉP BẢ VAI",Rect2(140,46,872,38),26,true)
	label(modal,"Đứng hoặc ngồi thẳng • gập khuỷu tay • quan sát chuyển động",Rect2(146,94,860,35),18,true)
	panel(modal,Rect2(146,140,420,284),Color("2d4940"))
	panel(modal,Rect2(586,140,420,284),Color("2d4940"))
	label(modal,"TRỰC DIỆN · MK2",Rect2(156,148,400,28),18,true)
	label(modal,"NHÌN NGANG · SƠ ĐỒ BỔ TRỢ",Rect2(596,148,400,28),18,true)
	guide_actor = Actor.new()
	guide_actor.pose_id = 3
	guide_actor.upper_body_only = true
	guide_actor.outfit_enabled = false
	guide_actor.joints_visible = true
	guide_actor.scale = Vector2.ONE*5
	guide_actor.position = Vector2(356,528)
	modal.add_child(guide_actor)
	side_actor = SideGuide.new()
	side_actor.scale = Vector2.ONE*5
	side_actor.position = Vector2(796,528)
	modal.add_child(side_actor)
	label(modal,"Vai • khuỷu • cổ tay",Rect2(156,393,400,25),16,true)
	label(modal,"← Ra sau     |     Mặt hướng sang phải",Rect2(596,393,400,25),16,true)
	label(modal,"Chấm vàng: khớp   ·   Nét xanh: nối các khớp   ·   Hai hình cùng nhịp minh họa",Rect2(148,429,856,25),16,true)
	guide_caption = label(modal,"",Rect2(148,459,856,42),20,true)
	guide_timer = label(modal,"",Rect2(148,505,856,27),16,true)
	button(modal,"Xem lại từ đầu",Rect2(280,540,270,44),func(): guide_time = 0)
	button(modal,"Sẵn sàng / Vào chơi",Rect2(576,540,296,44),_resume)
	label(modal,"Minh họa 2D xấp xỉ; góc ngang không phải rig Mk2 3D. Cần duyệt chuyên môn.",Rect2(146,585,860,23),13,true)
	_animate_guide()

func _animate_guide() -> void:
	var amount := 0.0
	var caption := "Chuẩn bị: giữ thân thẳng, hai khuỷu tay gập."
	if guide_time >= 11:
		amount = 1-smoothstep(11,15,guide_time)
		caption = "Thả lỏng, đưa hai tay trở về vị trí ban đầu."
	elif guide_time >= 7:
		amount = 1
		caption = "Quan sát tư thế giữ và vị trí hai khuỷu tay."
	elif guide_time >= 3:
		amount = smoothstep(3,7,guide_time)
		caption = "Từ từ đưa hai khuỷu ra sau, ép hai bả vai."
	guide_actor.amount = amount
	guide_actor.refresh()
	side_actor.amount = amount
	side_actor.refresh()
	guide_caption.text = caption
	guide_timer.text = "Tự vào màn chơi sau %d giây" % ceili(15-guide_time)

func _resume() -> void:
	_clear_modal()
	state = "countdown"
	countdown = 3
	_update_hud()

func _settings() -> void:
	if state == "settings": return
	return_state = state
	guide_resume_time = guide_time
	state = "settings"
	_new_modal(Rect2(344,52,464,544))
	label(modal,"CÀI ĐẶT · ĐÃ TẠM DỪNG",Rect2(360,70,432,42),23,true)
	label(modal,"Âm lượng (bản thử)",Rect2(376,132,400,30),18)
	var slider := HSlider.new()
	slider.position = Vector2(376,176)
	slider.size = Vector2(400,28)
	slider.value = volume
	slider.value_changed.connect(func(value: float): volume = value)
	modal.add_child(slider)
	button(modal,"Tiếp tục chơi",Rect2(376,228,400,46),_close_settings)
	button(modal,"Điều chỉnh camera",Rect2(376,290,400,46),_camera_settings)
	button(modal,"Quay lại chọn Map",Rect2(376,352,400,46),_leave.bind("res://ui/screens/map_selection/level_selection.tscn"))
	button(modal,"Trang chủ",Rect2(376,414,400,46),_leave.bind("res://ui/screens/start/start_screen.tscn"))
	label(modal,"Âm lượng chỉ thử giao diện, chưa phát âm thanh.\nRời màn này sẽ kết thúc phiên mô phỏng.",Rect2(376,491,400,67),16,true)

func _close_settings() -> void:
	if return_state == "guide":
		_open_guide()
		guide_time = guide_resume_time
		_animate_guide()
	elif return_state == "complete": _complete()
	else: _resume()

func _camera_settings() -> void:
	state = "camera"
	_new_modal(Rect2(284,136,584,360))
	label(modal,"ĐIỀU CHỈNH CAMERA",Rect2(308,160,536,40),24,true)
	label(modal,"Chưa kết nối camera trong bản prototype.\n\nKhung này dành cho chọn thiết bị, xem trước\nvà căn chỉnh vị trí người tập khi tích hợp.",Rect2(308,225,536,164),20,true)
	button(modal,"Quay lại Cài đặt",Rect2(412,415,328,46),func():
		var previous := return_state
		_settings()
		return_state = previous)

func _leave(path: String) -> void:
	get_tree().change_scene_to_file(path)

func _joints() -> void:
	actor.joints_visible = not actor.joints_visible
	actor.refresh()

func _process(delta: float) -> void:
	if not frozen: _advance(delta)

func _advance(delta: float) -> void:
	if state == "guide":
		guide_time = minf(15,guide_time+delta)
		_animate_guide()
		if guide_time >= 15: _resume()
	elif state == "countdown" and tracking:
		countdown -= delta
		if countdown <= 0: state = "play"
	elif state == "play" and tracking:
		if rest_remaining > 0:
			rest_remaining = maxf(0,rest_remaining-delta)
			_update_hud()
			return
		elapsed += delta
		if elapsed >= 8:
			elapsed = fmod(elapsed,8)
			reps += 1
			if reps == 10: rest_remaining = 30
			if reps >= 20:
				_complete()
				return
		actor.amount = (1-cos(elapsed/8*TAU))/2
		actor.refresh()
	_update_hud()

func _update_hud() -> void:
	var second_set := reps >= 10 and rest_remaining <= 0
	var current_rep := reps-10 if second_set else reps
	progress.text = "Đá đã phá: %d/20       Lần: %d/10\nHiệp: %d/2" % [reps,current_rep,2 if second_set else 1]
	phase_status.text = "Mô phỏng • chu kỳ động tác: %.1f / 8 giây" % elapsed
	if rest_remaining > 0: phase_status.text = "Nghỉ giữa hiệp: %d giây" % ceili(rest_remaining)
	if not tracking: feedback.text = "Mất tracking — đã tạm dừng.\nHãy trở lại vùng camera."
	elif state == "countdown": feedback.text = "Sẵn sàng tiếp tục trong %d…" % ceili(countdown)
	elif state == "play" and rest_remaining > 0: feedback.text = "Thả lỏng, nghỉ trước hiệp tiếp theo."
	elif state == "play": feedback.text = "Từ từ ép hai bả vai, rồi thả lỏng."
	else: feedback.text = "Đã tạm dừng"

func _complete() -> void:
	state = "complete"
	_new_modal(Rect2(284,136,584,368))
	label(modal,"HOÀN THÀNH BẢN MÔ PHỎNG",Rect2(308,164,536,42),24,true)
	label(modal,"2 hiệp · 20 lần minh họa\n\nĐây không phải kết quả buổi tập thật.\nKhông ghi dữ liệu hoặc tiến độ người chơi.",Rect2(308,229,536,146),20,true)
	button(modal,"Xem lại prototype",Rect2(412,420,328,46),func():
		reps = 0
		elapsed = 0
		rest_remaining = 0
		_open_guide())

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		if state == "settings": _close_settings()
		elif state == "camera":
			var previous := return_state
			_settings()
			return_state = previous
		else: _settings()
	elif state in ["play","countdown"]:
		if event.keycode == KEY_U: _open_guide()
		if event.keycode == KEY_I: _joints()
		# Developer-only opt-in, never shown as ordinary gameplay controls.
		if event.keycode == KEY_T and "--prototype-debug" in OS.get_cmdline_user_args():
			tracking = not tracking
			if tracking: _resume()
	_update_hud()

func _smoke() -> void:
	frozen = true
	assert(state == "guide" and not guide_actor.outfit_enabled and actor.outfit_enabled)
	assert(guide_actor.joints_visible)
	for sample in range(151):
		guide_time = sample/10.0
		_animate_guide()
		assert(is_equal_approx(guide_actor.amount,side_actor.amount))
		var points: Array[Vector2] = side_actor.endpoints()
		assert(absf((points[0]-points[1]).dot(points[2]-points[1])) < 0.001)
		for side in [-1,1]:
			for point in guide_actor.endpoints(side):
				assert(Rect2(146,178,420,215).has_point(guide_actor.position+point*5))
		for point in points:
			assert(Rect2(586,178,420,215).has_point(side_actor.position+point*5))
	guide_time = 0
	_advance(15)
	assert(state == "countdown")
	_advance(3.1)
	_advance(1)
	var before := elapsed
	_settings()
	_advance(5)
	assert(elapsed == before)
	_camera_settings()
	assert(state == "camera")
	_close_settings()
	_advance(3.1)
	tracking = false
	_advance(5)
	assert(elapsed == before)
	tracking = true
	_open_guide()
	_advance(7)
	assert(elapsed == before and not guide_actor.outfit_enabled)
	_resume()
	assert(state == "countdown" and actor.position.y == 320)
	_advance(3.1)
	reps = 9
	elapsed = 7.9
	_advance(0.2)
	assert(reps == 10 and rest_remaining == 30)
	_settings()
	_advance(10)
	assert(rest_remaining == 30)
	_close_settings()
	_advance(3.1)
	_advance(30)
	assert(rest_remaining == 0)
	reps = 19
	elapsed = 7.9
	_advance(0.2)
	assert(state == "complete" and reps == 20)
	assert(ResourceLoader.exists("res://ui/screens/start/start_screen.tscn"))
	assert(ResourceLoader.exists("res://ui/screens/map_selection/level_selection.tscn"))
	print("MAP1_SCREEN: PASS (guide, clothing, pause, camera modal, tracking freeze, resume, rest, completion, navigation targets)")
	get_tree().quit()

func _capture() -> void:
	frozen = true
	DirAccess.make_dir_recursive_absolute("res://tests/visual/captures")
	for mode in ["guide","play","settings","tracking"]:
		if mode == "guide":
			guide_time = 8
			_animate_guide()
		elif mode == "play":
			_clear_modal()
			state = "play"
			actor.amount = 0.8
			actor.refresh()
		elif mode == "settings": _settings()
		else:
			_clear_modal()
			state = "play"
			tracking = false
		_update_hud()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png("res://tests/visual/captures/map1_screen_%s.png" % mode) == OK)
	print("MAP1_SCREEN_CAPTURE: PASS")
	get_tree().quit()
