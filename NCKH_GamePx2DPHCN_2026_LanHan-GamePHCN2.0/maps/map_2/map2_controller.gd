class_name Map2Controller
extends Node
const VisualPace = preload("res://ui/shared/visual_pace.gd")

signal lift_progress_changed(completed: int, total: int)
signal action_window_changed(is_open: bool)
signal hold_visual_progress_changed(progress: float)

@export var slab_descent_speed := 120.0
@export var slab_support_y := 200.0

var total_lifts := 10
var lifts_completed := 0
var enabled := false
var _session_active := false
var _slab_descending := false
var _action_window_open := false

@onready var slab: Node2D = $"../Map2Slab"
@onready var player = $"../Player"


func _process(delta: float) -> void:
	if not enabled or not _session_active or not _slab_descending:
		return
	slab.position.y = move_toward(slab.position.y, slab_support_y, slab_descent_speed * VisualPace.factor() * delta)
	if is_equal_approx(slab.position.y, slab_support_y):
		_slab_descending = false
		_set_action_window(true)


func setup_map(required_lifts: int) -> void:
	enabled = true
	total_lifts = maxi(required_lifts, 1)
	lifts_completed = 0
	slab.position = Vector2(576.0, -40.0)
	slab.show()
	_slab_descending = true
	_set_action_window(false)
	lift_progress_changed.emit(lifts_completed, total_lifts)
	hold_visual_progress_changed.emit(0.0)


func set_session_active(active: bool) -> void:
	_session_active = active
	player.set_running(false)
	if active and lifts_completed < total_lifts and not _action_window_open:
		_slab_descending = true


func set_hold_progress(progress: float) -> void:
	if not _action_window_open:
		return
	var clamped := clampf(progress, 0.0, 1.0)
	slab.position.y = lerpf(slab_support_y, slab_support_y - 24.0, clampf((clamped-0.35)/0.65,0,1))
	hold_visual_progress_changed.emit(clamped)


func handle_hold_interrupted() -> void:
	if not _action_window_open:
		return
	slab.position.y = slab_support_y
	hold_visual_progress_changed.emit(0.0)


func handle_valid_repetition(_data: Dictionary) -> void:
	if not enabled or not _session_active or not _action_window_open:
		return
	_set_action_window(false)
	lifts_completed += 1
	player.play_exercise_action()
	lift_progress_changed.emit(lifts_completed, total_lifts)
	hold_visual_progress_changed.emit(0.0)
	var tween := create_tween()
	tween.tween_property(slab, "position:y", 70.0, VisualPace.duration(0.35)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished
	if lifts_completed < total_lifts:
		slab.position.y = -40.0
		_slab_descending = _session_active


func play_finish_sequence() -> void:
	_session_active = false
	_set_action_window(false)
	var tween := create_tween()
	tween.tween_property(slab, "position:y", -100.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	await get_tree().create_timer(0.3, false).timeout


func is_action_window_open() -> bool:
	return _action_window_open


func _set_action_window(is_open: bool) -> void:
	if _action_window_open == is_open:
		return
	_action_window_open = is_open
	action_window_changed.emit(is_open)
