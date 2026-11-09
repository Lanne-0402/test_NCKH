extends Node2D
signal closed

const Actor = preload("res://tests/visual/mk2_actor.gd")
const TITLES := ["1 · Nâng hai tay", "2 · Hai tay sau đầu", "3 · Kéo tay ngang ngực"]
const PHASES := ["CHUẨN BỊ", "THỰC HIỆN", "GIỮ TƯ THẾ", "TRỞ VỀ"]
const TEXT := [
	["Quan sát vị trí vai và hai tay.", "Quan sát hai tay đi lên đồng thời.", "So sánh độ rõ của vai, khuỷu và cổ tay.", "Quan sát đường đi khi hai tay hạ xuống."],
	["Hai tay gần sau đầu, khuỷu mở hai bên.", "Quan sát mô phỏng khép hai khuỷu.", "Kiểm tra tay có bị đầu che mất hay không.", "Quan sát khuỷu mở trở lại."],
	["Quan sát tay thực hiện và tay hỗ trợ.", "Một tay đi ngang ngực, tay kia hỗ trợ.", "Kiểm tra có phân biệt được hai tay hay không.", "Quan sát hai tay trở về vị trí ban đầu."]
]
var board: Node2D
var full: Node2D
var upper: Node2D
var pose_id := 0
var zoom := 5.0
var playing := true
var seconds := 0.0
var timeline: HSlider
var phase_label: Label
var subtitle: Label
var zoom_label: Label

func text_at(value: String, x: float, y: float, width: float, size: int, color := Color("e2edf4")) -> Label:
	var label := Label.new()
	label.text = value
	label.position = Vector2(x,y)
	label.size.x = width
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	board.add_child(label)
	return label

func button(value: String, x: float, y: float, width: float, callback: Callable) -> Button:
	var item := Button.new()
	item.text = value
	# Leave room for the main project's taller themed buttons.
	item.position = Vector2(x,y-8)
	item.size = Vector2(width,34)
	item.focus_mode = Control.FOCUS_NONE
	item.add_theme_font_size_override("font_size",16)
	item.clip_text = true
	item.pressed.connect(callback)
	board.add_child(item)
	return item

func _ready() -> void:
	board = Node2D.new()
	add_child(board)
	board.draw.connect(_paint)
	get_viewport().size_changed.connect(_fit)
	_fit()
	text_at("MK2 / HƯỚNG DẪN NỬA THÂN TRÊN",32,18,1000,27)
	button("Trang phục [O]",918,27,200,_outfit)
	text_at("Cùng một chuyển động • hông cố định • giữ trọn bàn tay • bản chơi chính không thay đổi",32,58,1080,16,Color("a3b9c9"))
	for index in range(3):
		button(TITLES[index],32+index*260,96,248,_select.bind(index))
	button("Về bản thử [H]",870,96,248,_close)
	text_at("TOÀN THÂN / 3×",48,140,270,14,Color("a3b9c9"))
	zoom_label = text_at("",368,140,700,14,Color("a3b9c9"))
	full = Actor.new()
	full.position = Vector2(184,470)
	full.scale = Vector2.ONE*3
	full.joints_visible = false
	board.add_child(full)
	upper = Actor.new()
	upper.upper_body_only = true
	upper.joints_visible = false
	upper.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	board.add_child(upper)
	_layout_actor()
	phase_label = text_at("",32,508,340,17)
	timeline = HSlider.new()
	timeline.position = Vector2(390,510)
	timeline.size = Vector2(728,25)
	timeline.max_value = 15
	timeline.step = 0.01
	timeline.drag_started.connect(func(): playing = false)
	timeline.value_changed.connect(_at_time)
	board.add_child(timeline)
	button("Chạy/Dừng [Space]",32,548,230,func(): playing = not playing)
	button("Cỡ 4×/5× [V]",278,548,200,_zoom)
	button("Dấu khớp [J]",494,548,200,_joints)
	button("Đổi bên tay [L]",710,548,200,_mirror)
	button("Bắt đầu lại [R]",926,548,192,_restart)
	subtitle = text_at("",32,592,1080,19)
	text_at("Minh họa thị giác, chưa được chuyên môn duyệt. Chu kỳ 15 giây để quan sát, không phải liều tập.",32,622,1080,14,Color("ffd696"))
	_at_time(0)
	board.queue_redraw()
	if "--guide-smoke" in OS.get_cmdline_user_args():
		call_deferred("_smoke")
	elif "--guide-capture" in OS.get_cmdline_user_args():
		call_deferred("_capture")

func _fit() -> void:
	var size := get_viewport_rect().size
	var factor := minf(size.x/1152,size.y/648)
	board.scale = Vector2.ONE*factor
	board.position = (size-Vector2(1152,648)*factor)/2

func _paint() -> void:
	board.draw_rect(Rect2(0,0,1152,648),Color("101e2c"))
	board.draw_rect(Rect2(32,164,304,332),Color("203447"))
	board.draw_rect(Rect2(352,164,766,332),Color("203447"))
	for x in range(376,1100,24):
		board.draw_line(Vector2(x,172),Vector2(x,484),Color("293f52"))
	for y in range(172,485,24):
		board.draw_line(Vector2(368,y),Vector2(1102,y),Color("293f52"))
	board.draw_line(Vector2(64,471),Vector2(304,471),Color("77edbd"),1)
	board.draw_line(Vector2(674,430),Vector2(794,430),Color("77edbd"),1)

func _layout_actor() -> void:
	upper.scale = Vector2.ONE*zoom
	# Same hip coordinate for all poses and both zoom levels; do not auto-frame.
	upper.position = Vector2(734,430+28*zoom)
	upper.refresh()
	zoom_label.text = "NỬA THÂN TRÊN / %d× · Hông cố định, tay được giữ ngoài mép thân" % int(zoom)

func _select(index: int) -> void:
	pose_id = index
	full.pose_id = index
	upper.pose_id = index
	full.mirrored = false
	upper.mirrored = false
	_restart()

func _restart() -> void:
	seconds = 0
	timeline.set_value_no_signal(0)
	_at_time(0)
	playing = true

func _process(delta: float) -> void:
	if playing:
		timeline.value = fmod(seconds+delta,15.0)

func _at_time(value: float) -> void:
	seconds = value
	timeline.set_value_no_signal(value)
	var phase := 0
	var amount := 0.0
	if value >= 11:
		phase = 3
		amount = 1.0-smoothstep(11,15,value)
	elif value >= 7:
		phase = 2
		amount = 1
	elif value >= 3:
		phase = 1
		amount = smoothstep(3,7,value)
	for actor in [full,upper]:
		actor.amount = amount
		actor.refresh()
	phase_label.text = "%s · %.1f / 15s" % [PHASES[phase],value]
	subtitle.text = TEXT[pose_id][phase]

func _zoom() -> void:
	zoom = 4 if zoom == 5 else 5
	_layout_actor()

func _joints() -> void:
	for actor in [full,upper]:
		actor.joints_visible = not actor.joints_visible
		actor.refresh()

func _mirror() -> void:
	if pose_id != 2:
		return
	for actor in [full,upper]:
		actor.mirrored = not actor.mirrored
		actor.refresh()

func _close() -> void:
	if closed.get_connections().is_empty():
		get_tree().change_scene_to_file("res://tests/visual/mk2_pose_lab.tscn")
	else:
		closed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE: playing = not playing
		KEY_V: _zoom()
		KEY_J: _joints()
		KEY_L: _mirror()
		KEY_R: _restart()
		KEY_O: _outfit()
		KEY_1: _select(0)
		KEY_2: _select(1)
		KEY_3: _select(2)
		KEY_H, KEY_ESCAPE: _close()
	get_viewport().set_input_as_handled()

func _smoke() -> void:
	playing = false
	_outfit()
	assert(not full.outfit_enabled and not upper.outfit_enabled)
	_outfit()
	assert(full.outfit_enabled and upper.outfit_enabled)
	for index in range(3):
		_select(index)
		for scale_value in [4.0,5.0]:
			zoom = scale_value
			_layout_actor()
			for mirror in [false,true]:
				upper.mirrored = mirror
				upper.refresh()
				for step in range(151):
					_at_time(step/10.0)
					assert(full.amount == upper.amount)
					assert(upper.position.y-28*zoom == 430)
					for side in [-1,1]:
						for p in upper.endpoints(side):
							var screen = upper.position + p*upper.scale
							# 4 source pixels cover hand extents and limb thickness.
							assert(Rect2(352,164,766,332).encloses(Rect2(screen-Vector2.ONE*4*zoom,Vector2.ONE*8*zoom)), "Hand/limb outside guide panel")
	print("MK2_UPPER_GUIDE: PASS (3 poses, 4x/5x, both sides, 151 samples, hand bounds, fixed hips)")
	get_tree().quit()

func _capture() -> void:
	playing = false
	DirAccess.make_dir_recursive_absolute("res://tests/visual/captures")
	for index in range(3):
		_select(index)
		playing = false
		_at_time(8)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png("res://tests/visual/captures/mk2_outfit_upper_%d.png" % index) == OK)
	print("MK2_UPPER_CAPTURE: PASS")
	get_tree().quit()

func _outfit() -> void:
	for actor in [full,upper]:
		actor.outfit_enabled = not actor.outfit_enabled
		actor.refresh()
