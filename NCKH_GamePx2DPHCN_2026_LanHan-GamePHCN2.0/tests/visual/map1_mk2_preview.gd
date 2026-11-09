extends Node2D

const Actor = preload("res://tests/visual/map1_mk2_actor.gd")
const BACKGROUND = preload("res://maps/map_1/visuals/map_1_background.tscn")
const GROUND = preload("res://maps/map_1/visuals/map_1_ground.tscn")
const ROCK = preload("res://maps/map_1/visuals/map_1_rock_visual.tscn")
const CAVE = preload("res://maps/map_1/visuals/map_1_cave.tscn")
var board: Node2D
var actor: Node2D
var reference: Node2D
var background: Node2D
var status: Label
var outfit_button: Button
var compare_button: Button
var timeline: HSlider
var x_slider: HSlider
var clock := 0.0
var playing := true
var comparing := false
var size_factor := 2.0

func label_at(value: String, x: float, y: float, size: int, color := Color("e9eff4")) -> Label:
	var label := Label.new()
	label.text = value
	label.position = Vector2(x,y)
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	board.add_child(label)
	return label

func button_at(value: String, x: float, y: float, width: float, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.position = Vector2(x,y)
	button.size = Vector2(width,42)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size",16)
	button.clip_text = true
	button.pressed.connect(callback)
	board.add_child(button)
	return button

func _ready() -> void:
	board = Node2D.new()
	add_child(board)
	board.draw.connect(_paint)
	get_viewport().size_changed.connect(_fit)
	_fit()
	background = BACKGROUND.instantiate()
	board.add_child(background)
	background.set_scrolling(false)
	var ground = GROUND.instantiate()
	ground.position = Vector2(0,320)
	board.add_child(ground)
	# The 16px grass tile has 10 transparent top rows. Align visible grass
	# to the foot plane in this preview only; do not edit the shared scene.
	ground.get_node("Visuals/GrassTop").position.y = -10
	var rock = ROCK.instantiate()
	rock.position = Vector2(540,320)
	board.add_child(rock)
	var cave = CAVE.instantiate()
	cave.position = Vector2(1030,320)
	board.add_child(cave)
	for index in range(2):
		var item = Actor.new()
		item.position = Vector2(285 if index == 0 else 750,320)
		item.pose_id = 3
		item.scale = Vector2.ONE*2
		item.z_index = 10
		item.joints_visible = false
		item.outfit_enabled = index == 0
		item.visible = index == 0
		board.add_child(item)
		if index == 0: actor = item
		else: reference = item
	# Opaque UI only above/below the play area: no contrast plate behind the actor.
	for rect in [Rect2(0,0,1152,82),Rect2(0,380,1152,268)]:
		var backing := ColorRect.new()
		backing.position = rect.position
		backing.size = rect.size
		backing.color = Color("142536")
		backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board.add_child(backing)
	# Put all subsequent labels/buttons in a top-level sibling board for consistent fit.
	label_at("MAP 1 / PROTOTYPE NHÂN VẬT MK2",24,14,26)
	label_at("Nền, mặt đất và đạo cụ từ Map 1 • mốc chân y=320 • mặc định cỡ 2×",24,50,16)
	status = label_at("",24,392,18)
	outfit_button = button_at("",24,432,244,_outfit)
	compare_button = button_at("So sánh cạnh nhau [B]",280,432,256,_compare)
	button_at("Dấu khớp [J]",548,432,180,_joints)
	button_at("Cỡ 2×/3× [V]",740,432,180,_zoom)
	button_at("Chạy/Dừng [Space]",932,432,196,func(): playing = not playing)
	label_at("Động tác",24,497,16)
	var poses := OptionButton.new()
	poses.position = Vector2(114,488)
	poses.size = Vector2(290,42)
	poses.add_theme_font_size_override("font_size",16)
	for title in ["Nâng hai tay", "Hai tay sau đầu", "Kéo tay ngang ngực", "Map 1: gập khuỷu / ép vai"]:
		poses.add_item(title)
	poses.select(3)
	poses.item_selected.connect(func(index: int):
		actor.pose_id = index
		reference.pose_id = index
		clock = 0
		_apply(0)
	)
	board.add_child(poses)
	label_at("Biên độ",426,497,16)
	timeline = HSlider.new()
	timeline.position = Vector2(510,500)
	timeline.size = Vector2(610,25)
	timeline.max_value = 1
	timeline.step = 0.001
	timeline.value_changed.connect(_apply)
	timeline.drag_started.connect(func(): playing = false)
	board.add_child(timeline)
	label_at("Vị trí trên nền",24,550,16)
	x_slider = HSlider.new()
	x_slider.position = Vector2(165,554)
	x_slider.size = Vector2(630,25)
	x_slider.min_value = 120
	x_slider.max_value = 900
	x_slider.value = 285
	x_slider.value_changed.connect(func(x: float): actor.position.x = x)
	board.add_child(x_slider)
	button_at("Đổi mảng nền [N]",820,540,308,_shift_background)
	label_at("O: đổi trang phục tại cùng vị trí. B: so sánh hai mẫu (mẫu bên phải luôn không trang phục).",24,600,16)
	label_at("Chỉ thử thị giác, không chấm điểm/ghi tiến độ. Động tác ép vai là xấp xỉ 2D. Esc: đóng.",24,624,14,Color("ffd696"))
	_update_status()
	board.queue_redraw()
	if "--preview-smoke" in OS.get_cmdline_user_args(): call_deferred("_smoke")
	elif "--preview-capture" in OS.get_cmdline_user_args(): call_deferred("_capture")

func _fit() -> void:
	var size := get_viewport_rect().size
	var factor := minf(size.x/1152,size.y/648)
	board.scale = Vector2.ONE*factor
	board.position = (size-Vector2(1152,648)*factor)/2

func _paint() -> void:
	board.draw_rect(Rect2(0,0,1152,82),Color("142536"))
	board.draw_rect(Rect2(0,380,1152,268),Color("142536"))

func _process(delta: float) -> void:
	if playing:
		clock = fmod(clock+delta,8)
		timeline.value = (1-cos(clock/8*TAU))/2

func _apply(amount: float) -> void:
	for item in [actor,reference]:
		item.amount = amount
		item.refresh()

func _outfit() -> void:
	actor.outfit_enabled = not actor.outfit_enabled
	actor.refresh()
	_update_status()

func _compare() -> void:
	comparing = not comparing
	reference.visible = comparing
	_update_status()

func _joints() -> void:
	for item in [actor,reference]:
		item.joints_visible = not item.joints_visible
		item.refresh()

func _zoom() -> void:
	size_factor = 3 if size_factor == 2 else 2
	for item in [actor,reference]:
		item.scale = Vector2.ONE*size_factor
	_update_status()

func _shift_background() -> void:
	background.far_layer.position.x = fmod(background.far_layer.position.x-240,1152)
	background.near_layer.position.x = fmod(background.near_layer.position.x-360,1152)

func _update_status() -> void:
	status.text = "Mẫu chính: %s  |  %d×  |  %s" % ["CÓ TRANG PHỤC" if actor.outfit_enabled else "KHÔNG TRANG PHỤC", int(size_factor), "SO SÁNH CẠNH NHAU" if comparing else "ĐỔI TẠI CÙNG VỊ TRÍ"]
	outfit_button.text = "Trang phục: %s [O]" % ("BẬT" if actor.outfit_enabled else "TẮT")

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_O: _outfit()
		KEY_B: _compare()
		KEY_J: _joints()
		KEY_V: _zoom()
		KEY_N: _shift_background()
		KEY_SPACE: playing = not playing
		KEY_ESCAPE: get_tree().quit()

func _smoke() -> void:
	playing = false
	var initial := actor.position
	_outfit()
	assert(not actor.outfit_enabled and actor.position == initial)
	_outfit()
	_compare()
	assert(reference.visible and not reference.outfit_enabled)
	for pose in range(4):
		actor.pose_id = pose
		reference.pose_id = pose
		for step in range(101):
			_apply(step/100.0)
			assert(actor.endpoints(1) == reference.endpoints(1))
	_zoom()
	assert(actor.position.y == 320 and actor.scale == Vector2(3,3))
	_shift_background()
	assert(not background.scrolling_enabled)
	print("MAP1_MK2_PREVIEW: PASS (4 poses, outfit A/B, comparison, fixed feet, background)")
	get_tree().quit()

func _capture() -> void:
	playing = false
	timeline.value = 1
	DirAccess.make_dir_recursive_absolute("res://tests/visual/captures")
	for mode in ["outfit","original","comparison"]:
		actor.outfit_enabled = mode != "original"
		comparing = mode == "comparison"
		reference.visible = comparing
		actor.refresh()
		_update_status()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png("res://tests/visual/captures/map1_mk2_%s.png" % mode) == OK)
	print("MAP1_MK2_CAPTURE: PASS")
	get_tree().quit()
