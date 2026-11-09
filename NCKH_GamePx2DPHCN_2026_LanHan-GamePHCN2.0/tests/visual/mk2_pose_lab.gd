extends Node2D

const Actor = preload("res://tests/visual/mk2_actor.gd")
const TITLES := ["01  NÂNG HAI TAY", "02  HAI TAY SAU ĐẦU", "03  KÉO TAY NGANG NGỰC"]
const NOTES := ["Hạ tay → nâng tay → giữ → trở về", "Mở khuỷu → khép khuỷu → mở lại", "Tay qua ngực + tay còn lại hỗ trợ"]
var board: Node2D
var actors: Array = []
var captions: Array[Label] = []
var display_scale := 3.0
var slider: HSlider
var state_label: Label
var playing := true
var elapsed := 0.0
var joints := true
var capture := false
var guide_overlay: Node2D

func label_at(text: String, pos: Vector2, width: float, size: int, color := Color("e2edf4")) -> Label:
	var item := Label.new()
	item.text = text
	item.position = pos
	item.size.x = width
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", color)
	board.add_child(item)
	return item

func button_at(text: String, x: float, width: float, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 16)
	button.clip_text = true
	button.focus_mode = Control.FOCUS_NONE
	button.position = Vector2(x, 540)
	button.size = Vector2(width, 38)
	button.pressed.connect(action)
	board.add_child(button)
	return button

func _ready() -> void:
	board = Node2D.new()
	add_child(board)
	board.draw.connect(_paint_board)
	get_viewport().size_changed.connect(_fit)
	_fit()
	label_at("MK2 / PHÒNG THỬ TƯ THẾ", Vector2(32, 20), 900, 28)
	var guide_button := button_at("Nửa thân trên [H]", 898, 220, _open_guide)
	guide_button.position.y = 20
	var outfit_button := button_at("Trang phục [O]", 680, 202, _outfit)
	outfit_button.position.y = 20
	label_at("Bản thử ghép khớp • không camera / backend • không ghi kết quả buổi tập", Vector2(32, 61), 1050, 17, Color("a3b9c9"))
	for index in range(3):
		var x := 32 + index * 368
		label_at(TITLES[index], Vector2(x+16, 116), 325, 19)
		label_at(NOTES[index], Vector2(x+16, 148), 330, 14, Color("a3b9c9"))
		var actor = Actor.new()
		actor.pose_id = index
		actor.position = Vector2(x+176, 454)
		actor.scale = Vector2(3, 3)
		actor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		board.add_child(actor)
		actors.append(actor)
		captions.append(label_at("3×  •  Mốc chân cố định", Vector2(x+70, 468), 260, 15, Color("a3b9c9")))
	state_label = label_at("", Vector2(32, 505), 250, 17)
	slider = HSlider.new()
	slider.position = Vector2(286, 509)
	slider.size = Vector2(832, 24)
	slider.max_value = 1.0
	slider.step = 0.001
	slider.drag_started.connect(func(): playing = false)
	slider.value_changed.connect(_apply)
	board.add_child(slider)
	button_at("Chạy/Dừng [Space]", 32, 174, func(): playing = not playing)
	button_at("Ẩn/Hiện khớp [J]", 216, 174, _toggle_joints)
	button_at("Đổi bên tay [L]", 400, 174, _mirror)
	button_at("Màu/Xám [C]", 584, 174, _color)
	button_at("Cỡ 2×/3× [V]", 768, 174, _zoom)
	button_at("Tư thế đích [T]", 952, 166, _target)
	label_at("LƯU Ý: mô phỏng thị giác, chưa phải mẫu hướng dẫn động tác đã được chuyên môn duyệt.", Vector2(32, 592), 1080, 16, Color("ffd696"))
	label_at("Võ sinh lữ hành — lớp trang phục thử bằng code. O: so sánh với bản gốc. Esc: đóng bản thử.", Vector2(32, 618), 1080, 14, Color("a3b9c9"))
	_apply(0)
	board.queue_redraw()
	if "--smoke" in OS.get_cmdline_user_args():
		call_deferred("_smoke")
	elif "--capture" in OS.get_cmdline_user_args():
		call_deferred("_capture")

func _fit() -> void:
	var size := get_viewport_rect().size
	var factor := minf(size.x / 1152, size.y / 648)
	board.scale = Vector2.ONE * factor
	board.position = (size - Vector2(1152,648)*factor) / 2

func _paint_board() -> void:
	board.draw_rect(Rect2(0,0,1152,648), Color("101e2c"))
	for index in range(3):
		var x := 32 + index*368
		board.draw_rect(Rect2(x,104,352,394), Color("203447"))
		for gx in range(x+16,x+352,24):
			board.draw_line(Vector2(gx,190),Vector2(gx,454),Color("2b4256"))
		for gy in range(190,455,24):
			board.draw_line(Vector2(x+16,gy),Vector2(x+336,gy),Color("2b4256"))
		board.draw_line(Vector2(x+16,455),Vector2(x+336,455),Color("77edbd"),2)

func _process(delta: float) -> void:
	if is_instance_valid(guide_overlay):
		return
	if playing:
		elapsed = fmod(elapsed + delta, 8.0)
		var t := elapsed / 8.0
		var value := 0.0
		if t < 0.35:
			value = smoothstep(0,0.35,t)
		elif t < 0.65:
			value = 1.0
		else:
			value = 1.0-smoothstep(0.65,1,t)
		slider.value = value

func _apply(value: float) -> void:
	state_label.text = "Biên độ minh họa: %d%%" % roundi(value*100)
	for actor in actors:
		actor.amount = value
		actor.refresh()

func _toggle_joints() -> void:
	joints = not joints
	for actor in actors:
		actor.joints_visible = joints
		actor.refresh()

func _mirror() -> void:
	actors[2].mirrored = not actors[2].mirrored
	actors[2].refresh()

func _color() -> void:
	for actor in actors:
		actor.colored = not actor.colored
		actor.refresh()

func _target() -> void:
	playing = false
	slider.value = 1

func _zoom() -> void:
	display_scale = 2.0 if display_scale == 3.0 else 3.0
	for actor in actors:
		actor.scale = Vector2.ONE * display_scale
		actor.refresh()
	for caption in captions:
		caption.text = "%d×  •  Mốc chân cố định" % int(display_scale)

func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(guide_overlay):
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE: playing = not playing
		KEY_J: _toggle_joints()
		KEY_L: _mirror()
		KEY_C: _color()
		KEY_T: _target()
		KEY_V: _zoom()
		KEY_H: _open_guide()
		KEY_O: _outfit()
		KEY_ESCAPE: get_tree().quit()

func _open_guide() -> void:
	if is_instance_valid(guide_overlay):
		return
	guide_overlay = Node2D.new()
	guide_overlay.set_script(load("res://tests/visual/mk2_upper_body_guide.gd"))
	guide_overlay.closed.connect(func():
		for actor in actors:
			actor.outfit_enabled = guide_overlay.full.outfit_enabled
			actor.refresh()
		board.visible = true
		guide_overlay.queue_free()
	)
	board.visible = false
	add_child(guide_overlay)
	for actor in [guide_overlay.full,guide_overlay.upper]:
		actor.outfit_enabled = actors[0].outfit_enabled
		actor.refresh()

func _outfit() -> void:
	for actor in actors:
		actor.outfit_enabled = not actor.outfit_enabled
		actor.refresh()

func _smoke() -> void:
	playing = false
	for step in range(101):
		_apply(step/100.0)
		for actor in actors:
			for side in [-1,1]:
				var p = actor.endpoints(side)
				assert(is_equal_approx(p[0].distance_to(p[1]),14.0))
				assert(is_equal_approx(p[1].distance_to(p[2]),14.0))
				for point in p:
					assert(point.is_finite())
	_toggle_joints()
	_mirror()
	_color()
	_target()
	_zoom()
	assert(not playing and actors[2].mirrored and slider.value == 1)
	assert(actors[2].scale == Vector2(-2,2))
	var previous_points = actors[0].endpoints(1)
	_outfit()
	assert(not actors[0].outfit_enabled and actors[0].endpoints(1) == previous_points)
	_outfit()
	assert(actors[0].outfit_enabled)
	_open_guide()
	assert(is_instance_valid(guide_overlay) and not board.visible)
	guide_overlay._close()
	await get_tree().process_frame
	assert(not is_instance_valid(guide_overlay) and board.visible)
	print("MK2_POSE_LAB: PASS (3 poses, 101 samples, fixed limb lengths, controls)")
	get_tree().quit()

func _capture() -> void:
	playing = false
	DirAccess.make_dir_recursive_absolute("res://tests/visual/captures")
	for step in [0,50,100]:
		slider.value = step/100.0
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var result := get_viewport().get_texture().get_image().save_png("res://tests/visual/captures/mk2_outfit_%d.png" % step)
		assert(result == OK)
	print("MK2_CAPTURE: PASS")
	get_tree().quit()
