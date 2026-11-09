extends Node
const VisualPace = preload("res://ui/shared/visual_pace.gd")
const Guide = preload("res://ui/shared/exercise_guide.gd")
var level: Node
var ui: CanvasLayer
var map_id := 1
var session: Node
var replay: Control
var replay_guide: Control
var resuming := -1.0
var owns_pause := false
var was_paused := false
var replay_label: Label
var intro_guide: Control
var status_display: RichTextLabel
var last_status := ""
var last_subtitle := ""
const STATUS_COLORS := {
	"ĐANG TẬP": "75e889", "TẠM DỪNG": "ffdc69",
	"ĐANG NGHỈ": "80caff", "CHUẨN BỊ": "ffd28a",
	"MẤT NHẬN DIỆN": "ff8585", "HOÀN THÀNH": "75e8cb",
	"HƯỚNG DẪN": "c7d8ef", "CHỜ": "c7d8ef"
}
const SHOW_ROM_DEBUG_WINDOW := false
const CAMERA_STALE_MS := 3000
var _last_camera_frame_ms := -1
var camera_header: HBoxContainer
var rom_state_label: Label
var rom_value_label: Label
var rom_bar: ProgressBar
var hold_title_label: Label
var hold_bar: ProgressBar
var rom_fb_label: Label
var rom_panel: PanelContainer
var camera_box: Control
var camera_bg: ColorRect
var camera_rect: TextureRect
var camera_tex: ImageTexture
var camera_title: Label
var camera_placeholder: Label
var camera_toggle_btn: Button
var is_camera_focused := false
var session_hud: VBoxContainer
var guide_button: Button
var auto_pause_panel: Control
var auto_pause_title: Label
var auto_pause_desc: Label
var auto_pause_countdown: Label
var _tracking_lost_timer := 0.0
var _auto_pause_active := false
var _auto_pause_resuming := -1.0
const AUTO_PAUSE_DEBOUNCE_SEC := 0.4

func place(item: Control, rect: Rect2) -> void:
	item.set_anchors_preset(Control.PRESET_TOP_LEFT)
	item.position = rect.position
	item.size = rect.size
	if item is Label:
		item.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		item.add_theme_font_size_override("font_size",18)
		item.add_theme_color_override("font_color",Color("f3f2de"))
		item.add_theme_color_override("font_outline_color",Color("14251e"))
		item.add_theme_constant_override("outline_size",4)

func label(value: String, rect: Rect2, parent: Node) -> Label:
	var item := Label.new()
	item.text = value
	parent.add_child(item)
	place(item,rect)
	return item

func button(value: String, rect: Rect2, callback: Callable) -> Button:
	var item := Button.new()
	item.text = value
	ui.add_child(item)
	place(item,rect)
	item.add_theme_font_size_override("font_size",17)
	item.pressed.connect(callback)
	return item

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	level = get_parent()
	map_id = int(level.scene_file_path.get_slice("map_",1).get_slice("/",0))
	session = level.get_node("ExerciseSession")
	AudioManager.attach_level.call_deferred(level, map_id)
	ui = level.get_node("UI")
	if map_id == 4: level.get_node("Player/FollowCamera").position.y = -20
	# Gameplay actor now renders animated pixel steam instead of static diamonds.
	if map_id == 5: level.get_node("Map5RestZone/Steam").hide()
	for node_name in ["HudBacking","HudLeftBacking","HudRightBacking","DebugHelp","BonusPanel"]:
		var node := ui.get_node_or_null(node_name)
		if node != null: node.hide()
	var bottom := ColorRect.new()
	bottom.position = Vector2(0,366)
	bottom.size = Vector2(1152,282)
	bottom.color = Color(0.04,0.075,0.05,0.91)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bottom)
	ui.move_child(bottom,0)
	_build_session_hud()
	place(level.feedback_label,Rect2(280,20,592,95))
	level.feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level.feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	level.feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	level.feedback_label.add_theme_font_size_override("font_size",28)
	level.hearts_label.visible = TrackingStability.ENABLED
	place(level.hearts_label,Rect2(890,24,238,32))
	level.hearts_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	level.hearts_label.add_theme_font_size_override("font_size",20)
	level.hearts_label.add_theme_color_override("font_color",Color("ff7171"))
	place(level.rest_label,Rect2(280,122,592,36))
	level.rest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level.rest_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level.rest_label.add_theme_font_size_override("font_size",24)
	level.rest_label.add_theme_color_override("font_color",Color("ffd85a"))

	camera_box = Control.new()
	camera_box.name = "CameraBox"
	camera_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(camera_box)

	camera_bg = ColorRect.new()
	camera_bg.color = Color("172b24")
	camera_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camera_box.add_child(camera_bg)

	camera_rect = TextureRect.new()
	camera_rect.name = "CameraStreamRect"
	camera_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	camera_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	camera_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	camera_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camera_box.add_child(camera_rect)

	camera_placeholder = label("Chưa kết nối camera\n\nKhung camera trực quan\ntheo dõi tư thế tập luyện.", Rect2(0, 0, 100, 60), camera_box)
	camera_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	camera_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	camera_placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if PoseInput.get("offline_preview_enabled") == true:
		camera_placeholder.text = "CHẾ ĐỘ KIỂM THỬ\nKhông sử dụng camera\nKhông lưu kết quả tập"

	camera_header = HBoxContainer.new()
	camera_header.add_theme_constant_override("separation", 6)
	camera_box.add_child(camera_header)
	camera_title = label("CAMERA NGƯỜI TẬP", Rect2(0, 0, 100, 22), camera_header)
	camera_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camera_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	camera_title.add_theme_font_size_override("font_size", 14)
	camera_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	camera_title.add_theme_color_override("font_color", Color("ffd85a"))
	camera_title.add_theme_color_override("font_outline_color", Color("14251e"))
	camera_title.add_theme_constant_override("outline_size", 4)

	camera_toggle_btn = Button.new()
	camera_toggle_btn.text = "Toàn cảnh [C]"
	camera_toggle_btn.add_theme_font_size_override("font_size", 12)
	camera_toggle_btn.pressed.connect(_toggle_camera_focus)
	camera_toggle_btn.custom_minimum_size = Vector2(96, 22)
	camera_header.add_child(camera_toggle_btn)

	PoseInput.camera_frame_received.connect(_on_camera_frame_received)
	PoseInput.connection_changed.connect(_on_camera_connection_changed)

	_build_rom_debug_window()
	_update_camera_layout()
	_build_intro()
	_build_auto_pause_ui()
	var results := preload("res://ui/shared/session_results.gd").new()
	level.add_child.call_deferred(results)
	# Ensure overlays stay above newly added HUD controls.
	for node_name in ["InstructionPanel","ResultPanel","CountdownLabel","RestLabel"]:
		ui.move_child(ui.get_node(node_name),-1)
	session.hold_progress_changed.connect(_hold)
	session.hold_interrupted.connect(func(_data): _reset_actor())
	session.state_changed.connect(func(state, _previous):
		if state != ExerciseSession.State.ACTIVE: _reset_actor())
	session.progress_changed.connect(func(_rep,_required,phase,_phases):
		if map_id == 5:
			level.get_node("Player").mk2.mirrored = phase == 2
			level.get_node("Player").mk2.refresh())

# Every map keeps its own labels and signals; containers only arrange them.
func _build_session_hud() -> void:
	session_hud = VBoxContainer.new()
	session_hud.name = "SessionHUD"
	session_hud.custom_minimum_size.x = 516
	session_hud.add_theme_constant_override("separation", 8)
	ui.add_child(session_hud)
	var heading := HBoxContainer.new()
	heading.name = "Heading"
	heading.add_theme_constant_override("separation", 16)
	session_hud.add_child(heading)
	var title := RichTextLabel.new()
	title.name = "MapLevelTitle"
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.custom_minimum_size = Vector2(250, 28)
	title.add_theme_font_size_override("normal_font_size", 18)
	title.add_theme_color_override("default_color", Color("f3f2de"))
	title.add_theme_color_override("font_outline_color", Color("14251e"))
	title.add_theme_constant_override("outline_size", 4)
	title.text = "MAP %d · [color=#ffd85a]MỨC %d[/color]" % [map_id, VisualPace.level_index() + 1]
	heading.add_child(title)
	level.state_label.hide()
	status_display = RichTextLabel.new()
	status_display.name = "ColoredStatus"
	status_display.bbcode_enabled = true
	status_display.fit_content = true
	status_display.scroll_active = false
	status_display.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_display.custom_minimum_size.y = 28
	status_display.add_theme_font_size_override("normal_font_size",16)
	status_display.add_theme_color_override("default_color",Color("f3f2de"))
	heading.add_child(status_display)
	_sync_status()
	var divider := ColorRect.new()
	divider.name = "HeadingDivider"
	divider.color = Color(0.48,0.61,0.53,0.4)
	divider.custom_minimum_size.y = 1
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	session_hud.add_child(divider)
	var counters := _hud_row("Counters")
	_hud_label(level.phase_label, counters)
	_hud_label(level.rep_label, counters)
	var progress_row := _hud_row("MapProgress")
	for node_name in ["RockProgressLabel","LiftProgressLabel","PushProgressLabel","ClimbProgressLabel","StretchProgressLabel"]:
		var item := ui.get_node_or_null(node_name)
		if item != null: _hud_label(item, progress_row)
	var bonus := ui.get_node_or_null("BonusLabel")
	if bonus != null: _hud_label(bonus, progress_row)
	for node_name in ["DirectionLabel","SideLabel"]:
		var item := ui.get_node_or_null(node_name)
		if item != null: _hud_label(item, _hud_row("ExerciseDetail"))
	var hold := ui.get_node_or_null("HoldPanel")
	if hold != null:
		hold.reparent(session_hud)
		hold.custom_minimum_size = Vector2(0,44)
		hold.get_node("Backing").hide()
		place(hold.get_node("HoldLabel"), Rect2(0,0,516,26))
		place(hold.get_node("HoldBar"), Rect2(0,32,516,12))
	guide_button = button("Xem hướng dẫn [U]", Rect2(0,0,516,44), _review)
	guide_button.name = "GuideButton"
	guide_button.reparent(session_hud)
	guide_button.custom_minimum_size.y = 44
	session_hud.minimum_size_changed.connect(_fit_session_hud)
	_fit_session_hud.call_deferred()


func _hud_row(row_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation",16)
	session_hud.add_child(row)
	return row


func _hud_label(item: Label, row: HBoxContainer) -> void:
	place(item,Rect2(0,0,0,28))
	item.reparent(row)
	item.custom_minimum_size = Vector2(0,28)
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _fit_session_hud() -> void:
	var height := session_hud.get_combined_minimum_size().y
	session_hud.size = Vector2(516,height)
	# Center a compact block instead of reserving empty rows in simpler maps.
	session_hud.position = Vector2(24,366 + maxf(8,(282-height)/2.0))


func _build_intro() -> void:
	var panel: PanelContainer = level.instruction_panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color("20392f")
	style.border_color = Color("90a080")
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel",style)
	var margin := panel.get_node("MarginContainer")
	for edge in ["left","right"]: margin.add_theme_constant_override("margin_"+edge,18)
	for edge in ["top","bottom"]: margin.add_theme_constant_override("margin_"+edge,16)
	var box := panel.get_node("MarginContainer/VBoxContainer")
	for child in box.get_children():
		if child != level.instruction_start_button: child.hide()
	intro_guide = Guide.new()
	intro_guide.map_id = map_id
	intro_guide.process_mode = Node.PROCESS_MODE_PAUSABLE
	box.add_child(intro_guide)
	box.move_child(intro_guide,0)
	intro_guide.finished.connect(func():
		if panel.visible and not level.instruction_start_button.disabled:
			level.instruction_start_button.pressed.emit())
	place(panel,Rect2(136,20,880,608))
	level.instruction_start_button.text = "SẴN SÀNG · VÀO CHƠI"

func _hold(progress: float, _elapsed: int, _target: int) -> void:
	var actor = level.get_node("Player").mk2
	actor.amount = clampf(progress,0,1)
	actor.refresh()

func _reset_actor() -> void:
	var actor = level.get_node("Player").mk2
	actor.amount = 0
	actor.refresh()

func _joints() -> void:
	var actor = level.get_node("Player").mk2
	actor.joints_visible = not actor.joints_visible
	actor.refresh()

func _review() -> void:
	if is_instance_valid(replay) or level._intro_running or level.instruction_panel.visible or level.result_panel.visible: return
	was_paused = get_tree().paused
	if was_paused: return
	owns_pause = true
	ui.get_node("SettingsButton").disabled = true
	session.set_menu_paused(true)
	get_tree().paused = true
	replay = Control.new()
	# Keep replay controls interactive while the gameplay tree is paused.
	replay.process_mode = Node.PROCESS_MODE_ALWAYS
	replay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(replay)
	ui.move_child(replay, -1)
	_sync_camera_visibility()
	var shade := ColorRect.new()
	shade.size = Vector2(1152,648)
	shade.color = Color(0,0,0,0.8)
	replay.add_child(shade)
	replay_guide = Guide.new()
	replay_guide.map_id = map_id
	replay_guide.position = Vector2(156,28)
	replay_guide.process_mode = Node.PROCESS_MODE_DISABLED
	replay.add_child(replay_guide)
	replay_guide.finished.connect(_resume)
	var close := Button.new()
	close.position = Vector2(400,534)
	close.size = Vector2(350,48)
	close.text = "TIẾP TỤC CHƠI"
	close.pressed.connect(_resume)
	replay.add_child(close)
	close.grab_focus()
	close.focus_next = NodePath(".")
	close.focus_previous = NodePath(".")
	replay_label = label("",Rect2(400,594,350,36),replay)

func _resume() -> void:
	if resuming >= 0: return
	replay_guide.complete = true
	resuming = 3

func _sync_subtitle() -> void:
	var caption: Label = level.feedback_label
	if caption.text == last_subtitle: return
	var raw := caption.text.replace("\n", " ").strip_edges()
	var font := caption.get_theme_font("font")
	var font_size := caption.get_theme_font_size("font_size")
	var width := caption.size.x - 8.0
	last_subtitle = raw
	if font.get_string_size(raw, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		var words := raw.split(" ", false)
		var best_score := INF
		for split in range(2, words.size() - 1):
			var left := " ".join(words.slice(0, split))
			var right := " ".join(words.slice(split))
			var a := font.get_string_size(left, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var b := font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if a > width or b > width: continue
			var score := absf(a - b)
			if left.ends_with(".") or left.ends_with("!") or left.ends_with("—"): score -= width * 0.3
			if score < best_score:
				best_score = score
				last_subtitle = left + "\n" + right
	caption.text = last_subtitle

func _sync_status() -> void:
	var value: String = level.state_label.text.trim_prefix("TRẠNG THÁI:").strip_edges()
	if get_tree().paused: value = "TẠM DỪNG"
	if value == last_status: return
	last_status = value
	var plain := "TRẠNG THÁI: " + value
	var font := status_display.get_theme_font("normal_font")
	var font_size := 16
	while font_size > 14 and font.get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > 250:
		font_size -= 1
	status_display.add_theme_font_size_override("normal_font_size", font_size)
	status_display.text = "TRẠNG THÁI: [color=#%s]%s[/color]" % [STATUS_COLORS.get(value,"c7d8ef"),value]

func _sync_camera_visibility() -> void:
	if not is_instance_valid(camera_box): return
	var is_intro: bool = is_instance_valid(level.instruction_panel) and bool(level.instruction_panel.visible)
	var is_replay: bool = is_instance_valid(replay)
	var is_result: bool = is_instance_valid(level.result_panel) and bool(level.result_panel.visible)
	camera_box.visible = not (is_intro or is_replay or is_result)


func _process(delta: float) -> void:
	_refresh_camera_freshness()
	_sync_camera_visibility()
	_sync_subtitle()
	_sync_status()
	_process_auto_pause(delta)
	if not is_instance_valid(replay): return
	if level.get_node("SettingsMenu").overlay.visible: return
	if resuming < 0:
		replay_guide._process(delta)
	else:
		resuming -= delta
		replay_label.text = "Tiếp tục trong %d…" % maxi(1,ceili(resuming))
		if resuming <= 0:
			replay.queue_free()
			replay = null
			resuming = -1
			get_tree().paused = was_paused
			session.set_menu_paused(false)
			owns_pause = false
			ui.get_node("SettingsButton").disabled = false
			ui.get_node("SettingsButton").grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(replay) and event.is_action_pressed("ui_cancel") and not event.is_echo():
		_resume()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_C and not get_tree().paused:
		_toggle_camera_focus()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F3 and OS.is_debug_build():
		if is_instance_valid(rom_panel):
			rom_panel.visible = not rom_panel.visible
			_update_camera_layout()
		return
	if get_tree().paused: return
	if event.keycode == KEY_U: _review()
	if event.keycode == KEY_I: _joints()

func _exit_tree() -> void:
	if owns_pause: get_tree().paused = was_paused
	if _auto_pause_active: get_tree().paused = false

func _build_rom_debug_window() -> void:
	rom_panel = PanelContainer.new()
	rom_panel.name = "RomDebugWindow"
	rom_panel.position = Vector2(556, 372)
	rom_panel.size = Vector2(216, 266)
	rom_panel.visible = SHOW_ROM_DEBUG_WINDOW
	ui.add_child(rom_panel)

	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color("0d1e16")
	p_style.border_color = Color("2e7d5a")
	p_style.set_border_width_all(2)
	p_style.set_corner_radius_all(4)
	rom_panel.add_theme_stylebox_override("panel", p_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	rom_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	var header_box := HBoxContainer.new()
	vbox.add_child(header_box)

	var title_lbl := Label.new()
	title_lbl.text = "[ DEBUG ROM ]"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_color_override("font_color", Color("00e676"))
	title_lbl.add_theme_font_size_override("font_size", 14)
	header_box.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.pressed.connect(func():
		rom_panel.visible = false
		_update_camera_layout()
	)
	header_box.add_child(close_btn)

	rom_state_label = Label.new()
	rom_state_label.text = "Trạng thái: CHUẨN BỊ"
	rom_state_label.add_theme_color_override("font_color", Color("ffd28a"))
	rom_state_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(rom_state_label)

	rom_value_label = Label.new()
	rom_value_label.text = "Biên độ ROM: 0%"
	rom_value_label.add_theme_color_override("font_color", Color("f3f2de"))
	rom_value_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(rom_value_label)

	rom_bar = ProgressBar.new()
	rom_bar.custom_minimum_size = Vector2(0, 16)
	rom_bar.max_value = 100.0
	rom_bar.value = 0.0
	rom_bar.show_percentage = true
	vbox.add_child(rom_bar)

	hold_title_label = Label.new()
	var def_target := float(level._session_config.get("hold_duration_ms", 0)) / 1000.0
	hold_title_label.text = "Giữ thế: 0.0s / %.1fs" % def_target
	hold_title_label.add_theme_color_override("font_color", Color("80caff"))
	hold_title_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(hold_title_label)

	hold_bar = ProgressBar.new()
	hold_bar.custom_minimum_size = Vector2(0, 14)
	hold_bar.max_value = 100.0
	hold_bar.value = 0.0
	hold_bar.show_percentage = false
	vbox.add_child(hold_bar)

	rom_fb_label = Label.new()
	rom_fb_label.text = ">> Sẵn sàng bắt đầu"
	rom_fb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rom_fb_label.add_theme_color_override("font_color", Color("b8e2c8"))
	rom_fb_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(rom_fb_label)

	PoseInput.pose_frame_received.connect(_update_rom_snapshot)
	# ExerciseSession owns hold progress; pose snapshots must never reset it.
	session.hold_progress_changed.connect(_update_hold_display)
	session.hold_interrupted.connect(func(_data): _reset_hold_display())
	session.state_changed.connect(func(state, _previous):
		if state != ExerciseSession.State.ACTIVE: _reset_hold_display())


func _update_rom_snapshot(data: Dictionary) -> void:
	var ex: Dictionary = data.get("exercise", {})
	var progress := clampf(float(ex.get("rom_progress", 0.0)), 0.0, 1.0)
	rom_value_label.text = "Biên độ ROM: %d%%" % roundi(progress * 100.0)
	rom_bar.value = progress * 100.0
	rom_state_label.text = "Trạng thái: " + _movement_state_text(str(ex.get("movement_state", "ready")))
	var code := str(ex.get("feedback_code", ""))
	rom_fb_label.text = _vn_fb(code) if not code.is_empty() else "Chờ phản hồi nhận diện"


func _movement_state_text(value: String) -> String:
	const STATES := {
		"ready": "Sẵn sàng", "idle": "Chờ", "moving": "Đang di chuyển",
		"holding": "Đang giữ", "hold": "Đang giữ", "returning": "Trở về tư thế đầu",
		"completed": "Hoàn thành", "prep": "Chuẩn bị", "preparing": "Chuẩn bị",
		"target_reached": "Đạt mục tiêu", "resting": "Đang nghỉ",
		"closing": "Đang khép tay", "contracting": "Đang ép vai",
		"opening": "Đang mở tay", "raising": "Đang nâng tay", "calibrating": "Đang hiệu chỉnh"
	}
	return STATES.get(value.to_lower(), "Đang nhận diện")


func _update_hold_display(progress: float, elapsed_ms: int, target_ms: int) -> void:
	hold_bar.value = clampf(progress, 0.0, 1.0) * 100.0
	hold_title_label.text = "Giữ thế: %.1fs / %.1fs" % [float(elapsed_ms) / 1000.0, float(target_ms) / 1000.0]


func _reset_hold_display() -> void:
	_update_hold_display(0.0, 0, int(level._session_config.get("hold_duration_ms", 0)))


func _on_camera_frame_received(img: Image) -> void:
	if img == null or img.is_empty() or PoseInput.get("offline_preview_enabled") == true: return
	_last_camera_frame_ms = Time.get_ticks_msec()
	var texture_created := false
	if camera_tex != null and camera_tex.get_width() == img.get_width() and camera_tex.get_height() == img.get_height() and camera_tex.get_format() == img.get_format():
		camera_tex.update(img)
	else:
		camera_tex = ImageTexture.create_from_image(img)
		texture_created = true
	camera_rect.texture = camera_tex
	camera_placeholder.hide()
	if texture_created:
		_update_camera_layout()


func _clear_camera(message: String) -> void:
	_last_camera_frame_ms = -1
	camera_rect.texture = null
	camera_tex = null
	camera_placeholder.text = message
	camera_placeholder.show()
	_update_camera_layout()


func _on_camera_connection_changed(connected: bool, _details: Dictionary) -> void:
	if PoseInput.get("offline_preview_enabled") == true: return
	_clear_camera("Đang chờ hình ảnh camera…" if connected else "Mất kết nối camera\nĐang chờ kết nối lại…")
	if not connected:
		_reset_hold_display()
		rom_state_label.text = "Trạng thái: Mất kết nối"
		rom_value_label.text = "Biên độ ROM: —"
		rom_bar.value = 0
		rom_fb_label.text = "Chờ dữ liệu nhận diện mới"


func _refresh_camera_freshness() -> void:
	if _last_camera_frame_ms >= 0 and Time.get_ticks_msec() - _last_camera_frame_ms > CAMERA_STALE_MS:
		_clear_camera("Hình ảnh camera bị gián đoạn\nĐang chờ ảnh mới…")


func _update_camera_layout() -> void:
	if not is_instance_valid(camera_bg): return
	var show_debug := is_instance_valid(rom_panel) and rom_panel.visible

	if is_camera_focused:
		var cam_ratio := 4.0 / 3.0
		if camera_tex != null and camera_tex.get_height() > 0:
			cam_ratio = float(camera_tex.get_width()) / float(camera_tex.get_height())
		var f_h: float = 480.0
		var f_cam_h: float = f_h - 36.0
		var f_cam_w: float = clampf(roundf(f_cam_h * cam_ratio), 360.0, 680.0)
		var f_w: float = f_cam_w + 8.0
		var f_x: float = roundf((1152.0 - f_w) / 2.0)
		var area := Rect2(f_x, 84, f_w, f_h)
		camera_bg.position = area.position
		camera_bg.size = area.size
		camera_bg.color = Color(0.08, 0.14, 0.11, 0.96)
		camera_header.position = area.position + Vector2(6, 4)
		camera_header.size = Vector2(area.size.x - 12, 26)
		camera_title.text = "CAMERA TOÀN CẢNH [C]"
		camera_toggle_btn.text = "Thu nhỏ [C]"
		camera_rect.position = area.position + Vector2(4, 30)
		camera_rect.size = Vector2(f_cam_w, f_cam_h)
		camera_placeholder.position = camera_rect.position + Vector2(4, 4)
		camera_placeholder.size = camera_rect.size - Vector2(8, 8)
		if is_instance_valid(camera_box):
			ui.move_child(camera_box, -1)
		return

	var area := Rect2(780 if show_debug else 608, 372, 356 if show_debug else 528, 266)
	camera_bg.position = area.position
	camera_bg.size = area.size
	camera_bg.color = Color("172b24")
	camera_header.position = area.position + Vector2(10, 4)
	camera_header.size = Vector2(area.size.x - 20, 24)
	camera_title.text = "CAMERA" if area.size.x < 400 else "CAMERA NGƯỜI TẬP"
	camera_toggle_btn.text = "Toàn cảnh [C]"

	var cam_ratio := 4.0 / 3.0
	if camera_tex != null and camera_tex.get_height() > 0:
		cam_ratio = float(camera_tex.get_width()) / float(camera_tex.get_height())
	var max_w: float = area.size.x
	var max_h: float = area.size.y
	var cam_h := max_h
	var cam_w := roundf(cam_h * cam_ratio)
	if cam_w > max_w:
		cam_w = max_w
		cam_h = roundf(cam_w / cam_ratio)
	camera_rect.position = Vector2(area.position.x + roundf((area.size.x - cam_w) / 2.0), area.position.y + roundf((area.size.y - cam_h) / 2.0))
	camera_rect.size = Vector2(cam_w, cam_h)
	camera_placeholder.position = camera_rect.position + Vector2(4, 4)
	camera_placeholder.size = camera_rect.size - Vector2(8, 8)


func _toggle_camera_focus() -> void:
	is_camera_focused = not is_camera_focused
	_update_camera_layout()
	if not is_camera_focused:
		for node_name in ["InstructionPanel","ResultPanel","CountdownLabel","RestLabel"]:
			var node := ui.get_node_or_null(node_name)
			if node != null: ui.move_child(node, -1)

func _vn_fb(code: String) -> String:
	const VN := {
		"POSITION_OK": "Vị trí phù hợp, sẵn sàng",
		"PREP_POSITION": "Vào thế chuẩn bị",
		"PREP_COMPLETED": "Đã chuẩn bị xong, bắt đầu cử động",
		"CLOSE_ELBOWS": "Khép 2 khuỷu tay về trước mặt",
		"OPEN_ARMS": "Dang rộng 2 tay sang 2 bên",
		"REACH_OVERHEAD": "Vươn 2 tay lên cao trên đầu",
		"CONTINUE_MOVEMENT": "Tiếp tục cử động đến ngưỡng đích...",
		"TARGET_REACHED": "Đạt ngưỡng mục tiêu!",
		"HOLD_STARTED": "Đang giữ thế cử động...",
		"KEEP_POSITION": "Duy trì giữ nguyên tư thế",
		"HOLD_COMPLETED": "Hoàn thành thời gian giữ thế!",
		"HOLD_INTERRUPTED": "Tư thế bị gián đoạn! Hãy thử lại",
		"RETURN_TO_PREP": "Đưa tay về tư thế ban đầu",
		"RELEASE_POSITION": "Đưa tay về trước (ROM < 40%) để chuẩn bị",
		"READY_FOR_NEXT_REP": "Sẵn sàng! Hãy ép hai bả vai ra sau",
		"REP_VALID": "Động tác hợp lệ! Rất tốt",
		"LIFT_SUCCESS": "Đã đẩy tảng đá thành công!",
		"PUSH_SUCCESS": "Đã đẩy lùi 2 bức tường!",
		"JUMP_SUCCESS": "Đã nhảy lên bậc tiếp theo!",
		"TRACKING_LOST": "Mất nhận diện camera",
	}
	return VN.get(code, code)


func _build_auto_pause_ui() -> void:
	auto_pause_panel = Control.new()
	auto_pause_panel.name = "AutoPauseOverlay"
	auto_pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	auto_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(auto_pause_panel)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.05, 0.03, 0.90)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	auto_pause_panel.add_child(bg)

	var center_container := CenterContainer.new()
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_pause_panel.add_child(center_container)

	var center_box := PanelContainer.new()
	center_box.custom_minimum_size = Vector2(620, 240)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("172b24")
	style.border_color = Color("ffd85a")
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	center_box.add_theme_stylebox_override("panel", style)
	center_container.add_child(center_box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	center_box.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	auto_pause_title = Label.new()
	auto_pause_title.text = "BẠN ĐÃ RA NGOÀI TẦM NHÌN CAMERA"
	auto_pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	auto_pause_title.add_theme_font_size_override("font_size", 22)
	auto_pause_title.add_theme_color_override("font_color", Color("ffd85a"))
	auto_pause_title.add_theme_color_override("font_outline_color", Color("14251e"))
	auto_pause_title.add_theme_constant_override("outline_size", 4)
	vbox.add_child(auto_pause_title)

	auto_pause_desc = Label.new()
	auto_pause_desc.text = "Game đang tạm dừng để bảo toàn kết quả tập.\nVui lòng đứng vào giữa khung hình camera để tiếp tục."
	auto_pause_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	auto_pause_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	auto_pause_desc.add_theme_font_size_override("font_size", 16)
	auto_pause_desc.add_theme_color_override("font_color", Color("f3f2de"))
	vbox.add_child(auto_pause_desc)

	auto_pause_countdown = Label.new()
	auto_pause_countdown.text = ""
	auto_pause_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	auto_pause_countdown.add_theme_font_size_override("font_size", 38)
	auto_pause_countdown.add_theme_color_override("font_color", Color("ffd85a"))
	auto_pause_countdown.add_theme_color_override("font_outline_color", Color("14251e"))
	auto_pause_countdown.add_theme_constant_override("outline_size", 6)
	vbox.add_child(auto_pause_countdown)

	auto_pause_panel.hide()


func _process_auto_pause(delta: float) -> void:
	if not is_instance_valid(auto_pause_panel) or not is_instance_valid(session): return
	var is_intro: bool = is_instance_valid(level.instruction_panel) and bool(level.instruction_panel.visible)
	var is_replay: bool = is_instance_valid(replay)
	var is_result: bool = is_instance_valid(level.result_panel) and bool(level.result_panel.visible)
	var settings_open: bool = level.has_node("SettingsMenu") and level.get_node("SettingsMenu").overlay.visible

	if is_intro or is_replay or is_result or settings_open or not session._session_started:
		if _auto_pause_active:
			_auto_pause_active = false
			_auto_pause_resuming = -1.0
			auto_pause_panel.hide()
			get_tree().paused = false
		_tracking_lost_timer = 0.0
		return

	var is_lost: bool = session.state == ExerciseSession.State.TRACKING_LOST
	var tracking_ok := bool(PoseInput.last_tracking_status.get("person_detected", false)) and bool(PoseInput.last_tracking_status.get("required_body_visible", false))

	if not tracking_ok:
		if not _auto_pause_active:
			_tracking_lost_timer += delta
			if _tracking_lost_timer >= AUTO_PAUSE_DEBOUNCE_SEC:
				_auto_pause_active = true
				_auto_pause_resuming = -1.0
				session.set_menu_paused(true)
				get_tree().paused = true
				auto_pause_title.text = "BẠN ĐÃ RA NGOÀI TẦM NHÌN CAMERA"
				auto_pause_desc.text = "Game đang tạm dừng để bảo toàn kết quả tập.\nVui lòng đứng vào giữa khung hình camera để tiếp tục."
				auto_pause_countdown.text = ""
				auto_pause_panel.show()
				ui.move_child(auto_pause_panel, -1)
		else:
			_auto_pause_resuming = -1.0
			auto_pause_title.text = "BẠN ĐÃ RA NGOÀI TẦM NHÌN CAMERA"
			auto_pause_desc.text = "Game đang tạm dừng để bảo toàn kết quả tập.\nVui lòng đứng vào giữa khung hình camera để tiếp tục."
			auto_pause_countdown.text = ""
	elif _auto_pause_active and tracking_ok:
		if _auto_pause_resuming < 0.0:
			_auto_pause_resuming = 3.0
			auto_pause_title.text = "ĐÃ NHẬN DIỆN LẠI NGƯỜI TẬP"
			auto_pause_desc.text = "Chuẩn bị tiếp tục sau:"
			auto_pause_countdown.text = "3"
			AudioManager.play_sfx("countdown_tick")
		else:
			var prev_sec := ceili(_auto_pause_resuming)
			_auto_pause_resuming -= delta
			var curr_sec := ceili(_auto_pause_resuming)
			if curr_sec != prev_sec and curr_sec > 0:
				auto_pause_countdown.text = str(curr_sec)
				AudioManager.play_sfx("countdown_tick")
			if _auto_pause_resuming <= 0.0:
				auto_pause_countdown.text = "TIẾP TỤC!"
				_auto_pause_active = false
				_auto_pause_resuming = -1.0
				_tracking_lost_timer = 0.0
				auto_pause_panel.hide()
				get_tree().paused = false
				session.set_menu_paused(false)
				AudioManager.play_sfx("exercise_start")
	else:
		_tracking_lost_timer = 0.0
