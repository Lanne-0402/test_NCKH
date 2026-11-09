class_name Map4Controller
extends Node
const VisualPace = preload("res://ui/shared/visual_pace.gd")

signal climb_progress_changed(completed: int, total: int)
signal action_window_changed(is_open: bool)
signal hold_visual_progress_changed(progress: float)
signal run_phase_changed(is_running: bool)

@export var ledge_approach_duration := 5.0
@export var jump_duration := 0.55
@export var step_transition_delay := 0.08

var total_steps := 5
var steps_completed := 0
var enabled := false
var _current_step_index := 0
var _session_active := false
var _running_on_ledge := false
var _action_window_open := false
var _steps: Array[Node2D] = []
var _run_tween: Tween
var _jump_tween: Tween

@onready var player: CharacterBody2D = $"../Player"
@onready var player_visuals: Node2D = $"../Player/Visuals"
@onready var climb_track: Node2D = $"../World/Map4ClimbTrack"
@onready var summit: Node2D = $"../World/Map4ClimbTrack/Step_10/SummitVisual"


func _ready() -> void:
	_collect_steps()
	summit.show()
	call_deferred("_lock_player_at_current_step")


func setup_map(required_steps: int) -> void:
	enabled = true
	total_steps = maxi(required_steps, 1)
	steps_completed = 0
	_current_step_index = 0
	summit.show()
	_set_action_window(false)
	_begin_step(0)
	climb_progress_changed.emit(steps_completed, total_steps)
	hold_visual_progress_changed.emit(0.0)


func set_session_active(active: bool) -> void:
	_session_active = active
	if active and steps_completed < total_steps and not _action_window_open and not _running_on_ledge:
		_begin_step(steps_completed)
	elif not active:
		_stop_run_tween()
		player.set_running(false)
		_set_run_phase(false)
		_lock_player_at_current_step()


func set_hold_progress(progress: float) -> void:
	if not _action_window_open:
		return
	var clamped := clampf(progress, 0.0, 1.0)
	player_visuals.scale = Vector2.ONE.lerp(Vector2(1.06, 0.96), clamped)
	hold_visual_progress_changed.emit(clamped)


func handle_hold_interrupted() -> void:
	if not _action_window_open:
		return
	player_visuals.scale = Vector2.ONE
	hold_visual_progress_changed.emit(0.0)
	_lock_player_at_jump_zone()


func handle_valid_repetition(_data: Dictionary) -> void:
	if not enabled or not _session_active or not _action_window_open:
		return
	_set_action_window(false)
	steps_completed += 1
	player_visuals.scale = Vector2.ONE
	player.play_exercise_action()
	await _play_jump_to(steps_completed)
	_current_step_index = clampi(steps_completed, 0, _steps.size() - 1)
	climb_progress_changed.emit(steps_completed, total_steps)
	hold_visual_progress_changed.emit(0.0)
	if steps_completed < total_steps:
		if step_transition_delay > 0.0:
			await get_tree().create_timer(step_transition_delay, false).timeout
		_begin_step(steps_completed)
	else:
		summit.show()


func play_finish_sequence() -> void:
	_session_active = false
	_stop_run_tween()
	_set_action_window(false)
	_set_run_phase(false)
	player.set_running(false)
	_lock_player_at_current_step()
	var tween := _make_visual_tween()
	tween.tween_property(summit, "scale", Vector2(1.15, 1.15), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	await get_tree().create_timer(0.35, false).timeout


func is_action_window_open() -> bool:
	return _action_window_open


func is_running_on_ledge() -> bool:
	return _running_on_ledge


func _collect_steps() -> void:
	_steps.clear()
	for child in climb_track.get_children():
		if child.name.begins_with("Step_"):
			_steps.append(child)
	_steps.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return _step_number(a.name) < _step_number(b.name)
	)


func _step_number(step_name: String) -> int:
	return int(step_name.trim_prefix("Step_"))


func _step_run_start(step_index: int) -> Vector2:
	var index := clampi(step_index, 0, _steps.size() - 1)
	return _steps[index].get_node("RunStart").global_position


func _step_jump_zone(step_index: int) -> Vector2:
	var index := clampi(step_index, 0, _steps.size() - 1)
	return _steps[index].get_node("JumpZone").global_position


func _begin_step(step_index: int) -> void:
	_current_step_index = clampi(step_index, 0, _steps.size() - 1)
	_stop_run_tween()
	_set_action_window(false)
	player_visuals.scale = Vector2.ONE
	_set_player_locked_position(_step_run_start(_current_step_index))
	if _session_active:
		_set_run_phase(true)
		player.set_running(true)
		_start_run_tween()
	else:
		_set_run_phase(false)
		player.set_running(false)
		_lock_player_at_current_step()


func _start_run_tween() -> void:
	_stop_run_tween()
	var start := _step_run_start(_current_step_index)
	var end := _step_jump_zone(_current_step_index)
	_set_player_locked_position(start)
	_run_tween = _make_movement_tween()
	_run_tween.tween_method(_set_player_locked_position, start, end, VisualPace.duration(ledge_approach_duration)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_run_tween.finished.connect(_finish_run_phase)


func _finish_run_phase() -> void:
	if not _running_on_ledge:
		return
	_running_on_ledge = false
	run_phase_changed.emit(false)
	player.set_running(false)
	_set_player_locked_position(_step_jump_zone(_current_step_index))
	_set_action_window(true)


func _play_jump_to(step_index: int) -> void:
	_stop_jump_tween()
	var target_index := clampi(step_index, 0, _steps.size() - 1)
	var start: Vector2 = player.global_position
	var target: Vector2 = _step_run_start(target_index)
	var apex := Vector2(lerpf(start.x, target.x, 0.5), minf(start.y, target.y) - 52.0)
	player.set_running(false)
	var jump_state := {
		"start": start,
		"apex": apex,
		"target": target,
	}
	_jump_tween = _make_movement_tween()
	_jump_tween.tween_method(_apply_jump_arc.bind(jump_state), 0.0, 1.0, VisualPace.duration(jump_duration)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _jump_tween.finished
	_set_player_locked_position(target)
	player.mk2.jump_progress = -1.0
	player.mk2.amount = 0.0
	player.mk2.refresh()


func _apply_jump_arc(progress: float, jump_state: Dictionary) -> void:
	var start: Vector2 = jump_state["start"]
	var apex: Vector2 = jump_state["apex"]
	var target: Vector2 = jump_state["target"]
	var t := clampf(progress, 0.0, 1.0)
	player.mk2.jump_progress = t
	player.mk2.refresh()
	var inv := 1.0 - t
	var pos := start * (inv * inv) + apex * (2.0 * inv * t) + target * (t * t)
	_set_player_locked_position(pos)


func _set_player_locked_position(pos: Vector2) -> void:
	player.set_movement_locked(true, pos)


func _lock_player_at_jump_zone() -> void:
	_set_player_locked_position(_step_jump_zone(_current_step_index))


func _lock_player_at_current_step() -> void:
	var step_index := clampi(maxi(_current_step_index, steps_completed), 0, _steps.size() - 1)
	if _action_window_open:
		_set_player_locked_position(_step_jump_zone(_current_step_index))
	else:
		_set_player_locked_position(_step_run_start(step_index))


func _set_action_window(is_open: bool) -> void:
	if _action_window_open == is_open:
		return
	_action_window_open = is_open
	action_window_changed.emit(is_open)
	if is_open:
		_lock_player_at_jump_zone()


func _set_run_phase(is_running: bool) -> void:
	if _running_on_ledge == is_running:
		return
	_running_on_ledge = is_running
	run_phase_changed.emit(is_running)


func _stop_run_tween() -> void:
	if is_instance_valid(_run_tween):
		_run_tween.kill()
		_run_tween = null


func _stop_jump_tween() -> void:
	if is_instance_valid(_jump_tween):
		_jump_tween.kill()
		_jump_tween = null


func _make_movement_tween() -> Tween:
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	return tween


func _make_visual_tween() -> Tween:
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	return tween
