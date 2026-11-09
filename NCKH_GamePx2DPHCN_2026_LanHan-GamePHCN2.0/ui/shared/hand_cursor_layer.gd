extends CanvasLayer

## HandCursorLayer - Autoload quan ly con tro ao dieu khien bang ban tay.
## Hoat dong tren CanvasLayer cao nhat (layer = 120), phu len toan bo man hinh.
## Cung cap co che Dwell Time 1.5s de kich hoat nut bam khong cham.

const TICK_SFX := preload("res://assets/audio_placeholder/sfx/countdown_tick.wav")
const DWELL_DURATION := 1.5
const CLICK_COOLDOWN_TIME := 0.8
const CENTER_RADIUS := 7.0
const OUTER_RADIUS := 20.0

var _is_hand_active := false
var _target_norm_pos := Vector2(0.5, 0.5)
var _screen_pos := Vector2(576, 324)
var _confidence := 0.0

var _hovered_button: BaseButton = null
var _dwell_time := 0.0
var _dwell_progress := 0.0
var _click_cooldown := 0.0
var _click_wave_timer := 0.0

var _tick_player: AudioStreamPlayer
var _tick_timer := 0.0

@onready var visual: Control = $CursorVisual


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	if is_instance_valid(visual):
		visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		visual.draw.connect(_on_visual_draw)
	
	_tick_player = AudioStreamPlayer.new()
	_tick_player.name = "DwellTickPlayer"
	_tick_player.stream = TICK_SFX
	_tick_player.volume_db = -18.0
	add_child(_tick_player)

	if PoseInput != null and PoseInput.has_signal("hand_control_received"):
		PoseInput.hand_control_received.connect(_on_hand_control_received)
		print("[HandCursorLayer] Da ket noi tin hieu hand_control_received thanh cong.")


func _on_hand_control_received(data: Dictionary) -> void:
	_is_hand_active = bool(data.get("active", false))
	if _is_hand_active:
		var nx := clampf(float(data.get("cursor_x", 0.5)), 0.0, 1.0)
		var ny := clampf(float(data.get("cursor_y", 0.5)), 0.0, 1.0)
		_target_norm_pos = Vector2(nx, ny)
		_confidence = float(data.get("confidence", 0.0))


func _process(delta: float) -> void:
	if _click_cooldown > 0.0:
		_click_cooldown -= delta

	if _click_wave_timer > 0.0:
		_click_wave_timer = maxf(0.0, _click_wave_timer - delta)

	# 1. Kiem tra xem man hinh hien tai co cho phep con tro ban tay hoat dong khong
	var allowed := _is_screen_allowed()

	if not _is_hand_active or not allowed:
		_reset_cursor_state()
		if visual.visible:
			visual.visible = false
		return

	if not visual.visible:
		visual.visible = true

	# 2. Lam muot toa do con tro sang khong gian Viewport (60 FPS interpolation)
	var vp_size := get_viewport().get_visible_rect().size
	var target_px := Vector2(_target_norm_pos.x * vp_size.x, _target_norm_pos.y * vp_size.y)
	if _screen_pos.distance_to(target_px) > 2.0:
		_screen_pos = _screen_pos.lerp(target_px, clampf(14.0 * delta, 0.0, 1.0))
	visual.position = _screen_pos

	# 3. Tim nut bam (Button / TextureButton) dang nam ben duoi con tro ao
	# Uu tien hop thoai noi (Modal Dialog Priority): chi tim trong Modal neu co Modal dang mo
	var active_modal := _get_active_modal_root()
	var search_root: Node = active_modal if active_modal != null else get_tree().root
	var found_btn := _find_button_under_cursor(search_root, _screen_pos)

	# 4. Xu ly logic nạp Dwell Time 1.5s
	if is_instance_valid(found_btn):
		if found_btn == _hovered_button:
			_dwell_time += delta
			_dwell_progress = clampf(_dwell_time / DWELL_DURATION, 0.0, 1.0)

			# 4.1. Phản hồi âm thanh nạp Dwell (Auditory Dwell Feedback):
			# Tíc tắc tăng dần nhịp độ (350ms -> 90ms) và nhấc nhẹ cao độ theo tiến độ
			var tick_interval := lerpf(0.35, 0.09, _dwell_progress)
			_tick_timer += delta
			if _tick_timer >= tick_interval:
				_tick_timer = 0.0
				if is_instance_valid(_tick_player):
					_tick_player.pitch_scale = lerpf(1.0, 1.35, _dwell_progress)
					_tick_player.play()

			# 4.2. Kich hoat khi nap du 1.5 giay
			if _dwell_time >= DWELL_DURATION and _click_cooldown <= 0.0:
				_execute_click(found_btn)
		else:
			# Chuyen sang nut moi
			_hovered_button = found_btn
			_dwell_time = 0.0
			_dwell_progress = 0.0
			_tick_timer = 0.0
			if is_instance_valid(_tick_player):
				_tick_player.stop()
			if AudioManager != null:
				AudioManager.play_sfx("ui_hover")
	else:
		# Khong co nut nao duoi con tro
		_hovered_button = null
		_dwell_time = 0.0
		_dwell_progress = 0.0
		_tick_timer = 0.0
		if is_instance_valid(_tick_player):
			_tick_player.stop()

	visual.queue_redraw()


func _execute_click(btn: BaseButton) -> void:
	_click_cooldown = CLICK_COOLDOWN_TIME
	_dwell_time = 0.0
	_dwell_progress = 0.0
	_tick_timer = 0.0
	if is_instance_valid(_tick_player):
		_tick_player.stop()
	_click_wave_timer = 0.22

	if AudioManager != null:
		AudioManager.play_sfx("ui_click")

	# Kich hoat su kien pressed cua nut bam
	btn.pressed.emit()
	print("[HandCursorLayer] >> KICH HOAT THANH CONG: %s" % btn.name)


func _reset_cursor_state() -> void:
	_hovered_button = null
	_dwell_time = 0.0
	_dwell_progress = 0.0
	_tick_timer = 0.0
	if is_instance_valid(_tick_player):
		_tick_player.stop()


## Tim kiem Modal / Hop thoai noi dang duoc bat (neu co)
func _get_active_modal_root() -> Control:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	var current_scene := tree.current_scene

	# 1. Pop-up Tu dong tam dung khi ra khoi Camera
	var auto_pause := current_scene.get_node_or_null("UI/AutoPauseOverlay")
	if is_instance_valid(auto_pause) and auto_pause is Control and auto_pause.is_visible_in_tree():
		return auto_pause as Control

	# 2. Pop-up Menu Tam dung & Cai dat (SettingsMenu/Overlay)
	var settings := current_scene.get_node_or_null("SettingsMenu")
	if is_instance_valid(settings) and settings.has_node("Overlay"):
		var overlay: Control = settings.get_node("Overlay")
		if overlay.is_visible_in_tree():
			return overlay

	# 3. Bang Tong ket ket qua buoi tap (UI/ResultPanel)
	var result_p := current_scene.get_node_or_null("UI/ResultPanel")
	if is_instance_valid(result_p) and result_p is Control and result_p.is_visible_in_tree():
		return result_p as Control

	# 4. Bang Huong dan tap luyen dau map (UI/InstructionPanel)
	var instr := current_scene.get_node_or_null("UI/InstructionPanel")
	if is_instance_valid(instr) and instr is Control and instr.is_visible_in_tree():
		return instr as Control

	# 5. Bang xem lai huong dan trong game (Replay Guide)
	var presentation := current_scene.get_node_or_null("GamePresentation")
	if is_instance_valid(presentation):
		var replay_node = presentation.get("replay")
		if replay_node != null and is_instance_valid(replay_node) and replay_node is Control and replay_node.is_visible_in_tree():
			return replay_node as Control

	return null


## Kiem tra cac man hinh duoc phep va vo hieu hoa trong luc tap luyen
func _is_screen_allowed() -> bool:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return false

	var current_scene := tree.current_scene
	var scene_path := current_scene.scene_file_path.to_lower()

	# A. Cac man hinh Menu, Calibration, History, Chon Map, Chon Cap do: LUON CHO PHEP
	if not ("maps/map_" in scene_path):
		return true

	# B. Trong cac man choi Gameplay (maps/map_1 -> map_5):
	# Chi cho phep khi co Modal/Hop thoai dang bat (ngoai tru AutoPauseOverlay khong co nut)
	var modal := _get_active_modal_root()
	if modal != null and modal.name != "AutoPauseOverlay":
		return true

	# Nguoi choi dang trong pha tap luyen chay & danh quai/pha da -> VO HIEU HOA
	return false


## De quy tim nut bam (BaseButton) nam duoi toa do con tro ao
func _find_button_under_cursor(node: Node, pos: Vector2) -> BaseButton:
	if not is_instance_valid(node):
		return null

	if node is Control:
		var ctrl := node as Control
		if not ctrl.is_visible_in_tree() or ctrl.modulate.a <= 0.01:
			return null

	# Duyet nguoc tu cuoi ve dau de uu tien node o lop tren cung
	for i in range(node.get_child_count() - 1, -1, -1):
		var child := node.get_child(i)
		# Khong kiem tra chinh con tro HandCursorLayer de tranh tu bat chinh minh
		if child == self:
			continue
		var found := _find_button_under_cursor(child, pos)
		if found != null:
			return found

	if node is BaseButton:
		var btn := node as BaseButton
		if btn.is_visible_in_tree() and not btn.disabled:
			if btn.get_global_rect().has_point(pos):
				return btn

	return null


## Ve giao dien con tro ao truc quan (Khong che khuat chu)
func _on_visual_draw() -> void:
	if not _is_hand_active:
		return

	# 1. Hieu ung song xung kich khi Click thanh cong
	if _click_wave_timer > 0.0:
		var wave_ratio := 1.0 - (_click_wave_timer / 0.22)
		var wave_r := lerpf(OUTER_RADIUS, OUTER_RADIUS + 16.0, wave_ratio)
		var wave_alpha := lerpf(0.85, 0.0, wave_ratio)
		visual.draw_arc(Vector2.ZERO, wave_r, 0.0, TAU, 32, Color(0.2, 1.0, 0.75, wave_alpha), 2.5, true)

	# 2. Vong tron vien ngoai mo nhe dinh vi (Outer Ring)
	var base_ring_color := Color(1.0, 1.0, 1.0, 0.22)
	visual.draw_arc(Vector2.ZERO, OUTER_RADIUS, 0.0, TAU, 32, base_ring_color, 1.8, true)

	# 3. Vong tron Radial Progress the hien thoi gian nap Dwell Time (0% -> 100%)
	if _dwell_progress > 0.0:
		var start_angle := -PI / 2.0  # Bat dau tu dinh 12h
		var sweep_angle := _dwell_progress * TAU
		# Mau xanh ngoc ruc ro khi nap Dwell
		var prog_color := Color(0.15, 1.0, 0.72, 0.98)
		if _dwell_progress >= 0.85:
			# Chuyen sang mau vang ruc ranh sap click
			prog_color = Color(1.0, 0.92, 0.35, 1.0)
		visual.draw_arc(Vector2.ZERO, OUTER_RADIUS, start_angle, start_angle + sweep_angle, 36, prog_color, 3.5, true)

	# 4. Cham tron trung tam (Center Dot): Mau xanh ngoc/vang diu, khong che khuat chu
	# Vien bao quanh de tuong phan tren moi nen sang/toi
	visual.draw_circle(Vector2.ZERO, CENTER_RADIUS + 1.2, Color(0.04, 0.12, 0.09, 0.75))
	# Mau nen xanh ngoc
	visual.draw_circle(Vector2.ZERO, CENTER_RADIUS, Color(0.12, 0.92, 0.78, 0.95))
	# Tam diem vang diu
	visual.draw_circle(Vector2.ZERO, 3.0, Color(1.0, 0.95, 0.55, 0.98))
