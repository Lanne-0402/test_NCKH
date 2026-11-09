extends Node2D

@export var countdown_step_seconds := 1.0
@export var tracking_loss_grace_seconds := 3.0

const EXERCISE_CONFIG := {
	"exercise_id": "cross_body_shoulder_stretch",
	"repetitions_per_phase": 1,
	"phase_count": 2,
	"hold_duration_ms": 30000,
}

var _session_config: Dictionary = {}
var _session_attempt := 0
var _intro_running := false

@onready var exercise_session: ExerciseSession = $ExerciseSession
@onready var map5_controller: Map5Controller = $Map5Controller
@onready var tracking_stability: Node = $TrackingStability
@onready var state_label: Label = $UI/StateLabel
@onready var phase_label: Label = $UI/PhaseLabel
@onready var rep_label: Label = $UI/RepLabel
@onready var feedback_label: Label = $UI/FeedbackLabel
@onready var rest_label: Label = $UI/RestLabel
@onready var result_panel: PanelContainer = $UI/ResultPanel
@onready var result_label: Label = $UI/ResultPanel/MarginContainer/VBoxContainer/ResultLabel
@onready var stretch_progress_label: Label = $UI/StretchProgressLabel
@onready var side_label: Label = $UI/SideLabel
@onready var bonus_label: Label = $UI/BonusLabel
@onready var hearts_label: Label = $UI/HeartsLabel
@onready var hold_bar: ProgressBar = $UI/HoldPanel/HoldBar
@onready var hold_label: Label = $UI/HoldPanel/HoldLabel
@onready var bonus_bar: ProgressBar = $UI/BonusPanel/BonusBar
@onready var instruction_panel: PanelContainer = $UI/InstructionPanel
@onready var instruction_start_button: Button = $UI/InstructionPanel/MarginContainer/VBoxContainer/StartExerciseButton
@onready var countdown_label: Label = $UI/CountdownLabel


func _ready() -> void:
	call_deferred("_mount_presentation")
	result_panel.hide()
	rest_label.hide()
	countdown_label.hide()
	hold_bar.value = 0.0
	bonus_bar.value = 0.0

	exercise_session.state_changed.connect(_on_session_state_changed)
	exercise_session.progress_changed.connect(_on_session_progress_changed)
	exercise_session.feedback_changed.connect(_on_session_feedback_changed)
	exercise_session.repetition_accepted.connect(_on_repetition_accepted)
	exercise_session.repetition_rejected.connect(_on_repetition_rejected)
	exercise_session.hold_progress_changed.connect(_on_hold_progress_changed)
	exercise_session.hold_started.connect(_on_hold_started)
	exercise_session.hold_interrupted.connect(_on_hold_interrupted)
	exercise_session.rest_time_changed.connect(_on_rest_time_changed)
	exercise_session.session_completed.connect(_on_session_completed)

	tracking_stability.grace_seconds = tracking_loss_grace_seconds
	tracking_stability.setup(exercise_session, PoseInput)
	tracking_stability.stability_changed.connect(_on_stability_changed)
	tracking_stability.tracking_penalty_applied.connect(_on_tracking_penalty_applied)

	map5_controller.stretch_progress_changed.connect(_on_stretch_progress_changed)
	map5_controller.bonus_changed.connect(_on_bonus_changed)
	map5_controller.action_window_changed.connect(_on_action_window_changed)
	map5_controller.hold_visual_progress_changed.connect(_on_hold_visual_progress_changed)
	map5_controller.side_changed.connect(_on_side_changed)
	PoseInput.pose_frame_received.connect(_on_pose_frame_received)

	_session_config = EXERCISE_CONFIG.duplicate(true)
	_session_config["difficulty"] = _difficulty_name()
	_session_config["target_rom_ratio"] = _target_rom_ratio()
	_session_config["minimum_movement_duration_ms"] = 2000
	_session_config["maximum_movement_duration_ms"] = 8000
	_session_config["rest_duration_seconds"] = 30.0
	_session_config["calibrated_max_rom"] = Global.max_rom_angle
	_session_config["target_rom_value"] = Global.max_rom_angle * float(_session_config["target_rom_ratio"]) if Global.max_rom_angle > 0.0 else 0.0

	var total_stretches := int(_session_config["repetitions_per_phase"]) * int(_session_config["phase_count"])
	map5_controller.setup_map(total_stretches)
	tracking_stability.reset()
	_show_intro()


func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build(): return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_N:
		exercise_session.debug_skip_rest()

func _mount_presentation() -> void:
	var presentation = preload("res://ui/shared/game_presentation.gd").new()
	presentation.name = "GamePresentation"
	add_child(presentation)


func _on_session_state_changed(current: ExerciseSession.State, _previous: ExerciseSession.State) -> void:
	state_label.text = "TRẠNG THÁI: %s" % _state_text(current)
	rest_label.visible = current == ExerciseSession.State.RESTING
	if current == ExerciseSession.State.RESTING:
		rest_label.text = "THƯ GIÃN: %d GIÂY" % ceili(exercise_session.rest_seconds_remaining)
	var gameplay_active := current == ExerciseSession.State.ACTIVE
	map5_controller.set_session_active(gameplay_active)
	if gameplay_active:
		exercise_session.set_repetition_input_enabled(map5_controller.is_action_window_open())
	elif current == ExerciseSession.State.TRACKING_LOST:
		map5_controller.handle_hold_interrupted()


func _on_session_progress_changed(rep: int, reps_required: int, phase: int, phases: int) -> void:
	rep_label.text = "LẦN: %d/%d" % [rep, reps_required]
	phase_label.text = "HIỆP: %d/%d" % [phase, phases]
	map5_controller.set_current_phase(phase)


func _on_session_feedback_changed(code: String) -> void:
	feedback_label.text = _feedback_text(code)
	if code in ["REP_VALID", "TRACKING_RESTORED", "CAMERA_RECONNECTED", "ACTION_ZONE_READY", "HOLD_COMPLETED", "PREP_COMPLETED"]:
		feedback_label.modulate = Color("ffd85a")
	elif code in ["MOVEMENT_TOO_FAST", "REP_REJECTED", "HOLD_INTERRUPTED", "CAMERA_DISCONNECTED", "TRACKING_LOST", "BACKEND_DISCONNECTED", "SWITCH_ARM_SIDE", "CLAMP_WITH_OTHER_HAND"]:
		feedback_label.modulate = Color(0.9, 0.2, 0.1)
	else:
		feedback_label.modulate = Color.WHITE

	if code in ["HOLD_INTERRUPTED", "MOVEMENT_TOO_FAST", "REP_REJECTED"]:
		var current_text := feedback_label.text
		get_tree().create_timer(2.0).timeout.connect(func():
			if is_instance_valid(feedback_label) and feedback_label.text == current_text:
				_on_session_feedback_changed("PREP_POSITION")
		)


func _on_pose_frame_received(data: Dictionary) -> void:
	if exercise_session.state != ExerciseSession.State.ACTIVE:
		return
	var ex: Dictionary = data.get("exercise", {})
	var angles: Dictionary = data.get("angles", {})
	var fb_code := str(ex.get("feedback_code", ""))
	if fb_code in ["PREP_POSITION", "PREP_COMPLETED", "CONTINUE_MOVEMENT", "CLAMP_WITH_OTHER_HAND", "SWITCH_ARM_SIDE", "RETURN_TO_PREP"]:
		_on_session_feedback_changed(fb_code)
	var req_side := str(angles.get("required_side", ""))
	var act_side := str(angles.get("active_side", ""))
	if req_side == "left":
		side_label.text = "BÊN: TAY TRÁI (ĐỔI BÊN)"
	elif req_side == "right":
		side_label.text = "BÊN: TAY PHẢI (ĐỔI BÊN)"
	elif act_side == "left":
		side_label.text = "BÊN: TAY TRÁI"
	elif act_side == "right":
		side_label.text = "BÊN: TAY PHẢI"


func _on_repetition_accepted(data: Dictionary) -> void:
	map5_controller.handle_valid_repetition(data)


func _on_repetition_rejected(_data: Dictionary) -> void:
	map5_controller.handle_hold_interrupted()


func _on_hold_started(_data: Dictionary) -> void:
	map5_controller.handle_hold_started()
	feedback_label.text = _feedback_text("HOLD_STARTED")
	feedback_label.modulate = Color("ffd85a")


func _on_hold_progress_changed(progress: float, elapsed_ms: int, target_ms: int) -> void:
	hold_bar.value = progress * 100.0
	var elapsed_seconds := float(elapsed_ms) / 1000.0
	var target_seconds := float(target_ms) / 1000.0
	hold_label.text = "THIỀN GIỮ CĂNG: %.1f/%.1f GIÂY" % [elapsed_seconds, target_seconds]
	map5_controller.set_hold_progress(progress)


func _on_hold_interrupted(_data: Dictionary) -> void:
	map5_controller.handle_hold_interrupted()


func _on_hold_visual_progress_changed(progress: float) -> void:
	if progress <= 0.0:
		hold_bar.value = 0.0
		hold_label.text = "THIỀN GIỮ CĂNG: 0.0/30.0 GIÂY"


func _on_rest_time_changed(seconds_remaining: float) -> void:
	rest_label.text = "THƯ GIÃN: %d GIÂY" % ceili(seconds_remaining)


func _on_session_completed(summary: Dictionary) -> void:
	await map5_controller.play_finish_sequence()
	var stability: int = int(tracking_stability.stability)
	_unlock_next_difficulty(stability)
	var unlock_text := "Chưa mở cấp độ tiếp theo."
	if _difficulty_level() >= 3:
		unlock_text = "Đã hoàn thành cấp độ cao nhất."
	elif not TrackingStability.ENABLED or stability >= 2:
		unlock_text = "Cấp độ tiếp theo đã sẵn sàng."
	result_label.text = "HOÀN THÀNH MAP 5\n\nLần căng hợp lệ: %d\nLần chưa hợp lệ: %d\nĐiểm thưởng: %d/100\nỔn định còn lại: %d/3\nĐánh giá: %s\n%s" % [
		int(summary.get("valid_reps", 0)),
		int(summary.get("rejected_reps", 0)),
		map5_controller.bonus_points,
		stability,
		_stability_evaluation(stability),
		unlock_text,
	]
	if not TrackingStability.ENABLED:
		result_label.text = result_label.text.replace("Ổn định còn lại: %d/3\n" % stability, "")
	result_panel.show()


func _on_stretch_progress_changed(completed: int, total: int) -> void:
	stretch_progress_label.text = "LẦN CĂNG: %d/%d" % [completed, total]


func _on_bonus_changed(current: int, maximum: int) -> void:
	bonus_label.text = "ĐIỂM THƯỞNG: %d/%d" % [current, maximum]
	bonus_bar.value = float(current) / float(maximum) * 100.0


func _on_side_changed(side_name: String) -> void:
	side_label.text = "BÊN: %s" % side_name


func _on_stability_changed(current: int, maximum: int) -> void:
	var hearts := ""
	for index in range(maximum):
		hearts += "♥ " if index < current else "♡ "
	hearts_label.text = "ỔN ĐỊNH: %s" % hearts.strip_edges()


func _on_tracking_penalty_applied(_current: int, grace_seconds: float) -> void:
	feedback_label.modulate = Color(0.9, 0.2, 0.1)
	feedback_label.text = "Tracking gián đoạn quá %d giây: giảm 1 điểm Ổn định." % ceili(grace_seconds)


func _on_action_window_changed(is_open: bool) -> void:
	exercise_session.set_repetition_input_enabled(is_open)
	if is_open:
		feedback_label.text = _feedback_text("ACTION_ZONE_READY")


func _show_intro() -> void:
	state_label.text = "TRẠNG THÁI: HƯỚNG DẪN"
	feedback_label.text = "Đọc hướng dẫn và nhấn SẴN SÀNG để bắt đầu."
	instruction_start_button.disabled = false
	instruction_panel.show()


func _on_start_exercise_button_pressed() -> void:
	if _intro_running or exercise_session.state != ExerciseSession.State.IDLE:
		return
	_intro_running = true
	instruction_start_button.disabled = true
	instruction_panel.hide()
	countdown_label.show()
	for value in [3, 2, 1]:
		countdown_label.text = str(value)
		await get_tree().create_timer(countdown_step_seconds, false).timeout
	countdown_label.text = "BẮT ĐẦU"
	await get_tree().create_timer(countdown_step_seconds, false).timeout
	countdown_label.hide()
	_start_new_session_attempt()
	_intro_running = false


func _start_new_session_attempt() -> void:
	_session_attempt += 1
	_session_config["session_id"] = "map5-session-%d-%d" % [Time.get_ticks_msec(), _session_attempt]
	exercise_session.start_session(_session_config)


func _on_result_button_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/screens/level_selection/main_menu.tscn")


func _exit_tree() -> void:
	if is_instance_valid(exercise_session):
		exercise_session.stop_session("scene_changed")
	var player: CharacterBody2D = get_node_or_null("Player")
	if is_instance_valid(player):
		player.set_movement_locked(false)


func _difficulty_name() -> String:
	if Global.speed_multiplier >= 2.0:
		return "advanced"
	if Global.speed_multiplier >= 1.5:
		return "standard"
	return "gentle"


func _target_rom_ratio() -> float:
	if Global.speed_multiplier >= 2.0:
		return 0.90
	if Global.speed_multiplier >= 1.5:
		return 0.80
	return 0.70


func _difficulty_level() -> int:
	if Global.speed_multiplier >= 2.0:
		return 3
	if Global.speed_multiplier >= 1.5:
		return 2
	return 1


func _unlock_next_difficulty(stability: int) -> bool:
	if (TrackingStability.ENABLED and stability < 2) or _difficulty_level() >= 3:
		return false
	var previous_highest: int = Global.get_highest_unlocked_level(5)
	Global.unlock_level_for_action(5, _difficulty_level() + 1)
	return Global.get_highest_unlocked_level(5) > previous_highest


func _stability_evaluation(stability: int) -> String:
	if not TrackingStability.ENABLED:
		return "HOÀN THÀNH"
	if stability >= 3:
		return "HOÀN HẢO"
	if stability == 2:
		return "HOÀN THÀNH"
	return "CẦN CẢI THIỆN ĐỘ ỔN ĐỊNH"


func _state_text(value: ExerciseSession.State) -> String:
	match value:
		ExerciseSession.State.READY:
			return "CHUẨN BỊ"
		ExerciseSession.State.ACTIVE:
			return "ĐANG TẬP"
		ExerciseSession.State.RESTING:
			return "ĐANG THƯ GIÃN"
		ExerciseSession.State.PAUSED:
			return "TẠM DỪNG"
		ExerciseSession.State.TRACKING_LOST:
			return "MẤT NHẬN DIỆN"
		ExerciseSession.State.COMPLETED:
			return "HOÀN THÀNH"
		_:
			return "CHỜ"


func _feedback_text(code: String) -> String:
	const TEXTS := {
		"SESSION_READY": "Suối nước nóng sẵn sàng. Hãy thả lỏng 2 vai để chuẩn bị.",
		"ACTION_ZONE_READY": "Thả lỏng 2 vai ở tư thế chuẩn bị (100% ROM) trước khi kéo căng.",
		"PREP_POSITION": "Đứng thẳng, thả lỏng 2 vai cân bằng để vào tư thế chuẩn bị...",
		"PREP_COMPLETED": "Đã chuẩn bị! Hãy kéo cánh tay qua ngực và dùng tay kia kẹp giữ.",
		"MOVEMENT_STARTED": "Đã nhận tư thế chuẩn bị! Bắt đầu kéo căng cánh tay qua ngực.",
		"CONTINUE_MOVEMENT": "Kéo khuỷu tay sát vai đối diện và dùng cổ tay kia kẹp giữ trước ngực...",
		"CLAMP_WITH_OTHER_HAND": "Hãy dùng cẳng tay/cổ tay còn lại kẹp giữ khuỷu tay vào ngực!",
		"SWITCH_ARM_SIDE": "Bạn đã tập bên tay này ở Hiệp 1! Hãy đổi sang kéo căng tay đối diện!",
		"TARGET_REACHED": "Đúng tư thế (ROM 100%)! Bắt đầu thiền giữ căng 30 giây.",
		"HOLD_STARTED": "Đang thiền và giữ căng 30 giây...",
		"HOLD_PROGRESS": "Duy trì hơi thở đều đặn và giữ nguyên tư thế kéo căng 30 giây...",
		"HOLD_COMPLETED": "Hoàn thành 30 giây thiền kéo căng! Nhận +100 điểm thưởng!",
		"HOLD_INTERRUPTED": "Tư thế bị gián đoạn. Hãy kéo căng và kẹp giữ lại chậm rãi.",
		"RETURN_TO_PREP": "Thả lỏng 2 tay về tư thế chuẩn bị.",
		"REP_VALID": "Tuyệt vời! Đã hoàn thành hiệp kéo căng (+100 điểm thưởng).",
		"MOVEMENT_TOO_FAST": "Cử động quá nhanh. Hãy kéo căng chậm hơn.",
		"REP_REJECTED": "Lần căng chưa hợp lệ.",
		"PHASE_REST": "Hoàn thành hiệp 1. Hãy thư giãn 30 giây trước khi đổi sang tay đối diện.",
		"NEXT_PHASE": "Bắt đầu hiệp 2: Hãy đổi sang kéo căng cánh tay đối diện qua ngực!",
		"CAMERA_DISCONNECTED": "Mất kết nối Camera! Vui lòng kiểm tra lại dây cắm.",
		"CAMERA_RECONNECTED": "Đã kết nối lại Camera. Tiếp tục buổi tập.",
		"TRACKING_LOST": "Không nhìn thấy người chơi. Buổi tập đã tạm dừng.",
		"TRACKING_RESTORED": "Đã nhận diện lại. Tiếp tục buổi tập.",
		"BACKEND_DISCONNECTED": "Mất kết nối với hệ thống nhận diện.",
		"SESSION_COMPLETED": "Hoàn thành Map 5!",
	}
	return TEXTS.get(code, code)
