class_name Map3Controller
extends Node
const VisualPace = preload("res://ui/shared/visual_pace.gd")

signal push_progress_changed(completed: int, total: int)
signal action_window_changed(is_open: bool)
signal hold_visual_progress_changed(progress: float)
signal direction_changed(direction_name: String)

enum WallDirection { HORIZONTAL, VERTICAL, DIAGONAL_RIGHT, DIAGONAL_LEFT }

const DIRECTION_SEQUENCE: Array[WallDirection] = [
	WallDirection.HORIZONTAL,
	WallDirection.VERTICAL,
	WallDirection.DIAGONAL_RIGHT,
]

const DIRECTION_NAMES := {
	WallDirection.HORIZONTAL: "TRÁI - PHẢI",
	WallDirection.VERTICAL: "TRÊN - DƯỚI",
	WallDirection.DIAGONAL_RIGHT: "HAI BÊN CHÉO 45°",
	WallDirection.DIAGONAL_LEFT: "HAI BÊN CHÉO 45°",
}

const CENTER := Vector2(576.0, 320.0)
const WALL_HALF_HEIGHT := 120.0
const SAFE_GAP := 400.0
const RETREAT_GAP := 720.0

@export var wall_close_speed := 140.0

var total_pushes := 5
var pushes_completed := 0
var enabled := false
var current_direction: WallDirection = WallDirection.HORIZONTAL

var _session_active := false
var _walls_closing := false
var _action_window_open := false
var _close_progress := 0.0
var _hold_retreat := 0.0

@onready var wall_a: Node2D = $"../Map3WallPair/WallA"
@onready var wall_b: Node2D = $"../Map3WallPair/WallB"
@onready var energy_wave: Node2D = $"../Map3EnergyWave"
@onready var player = $"../Player"


func _ready() -> void:
	energy_wave.hide()


func _process(delta: float) -> void:
	if not enabled or not _session_active or not _walls_closing:
		return
	_close_progress = move_toward(_close_progress, 1.0, wall_close_speed * VisualPace.factor() * delta / SAFE_GAP)
	_apply_wall_positions(_close_progress, _hold_retreat)
	if is_equal_approx(_close_progress, 1.0):
		_walls_closing = false
		_set_action_window(true)


func setup_map(required_pushes: int) -> void:
	enabled = true
	total_pushes = maxi(required_pushes, 1)
	pushes_completed = 0
	_hold_retreat = 0.0
	_set_action_window(false)
	_begin_wave(0)
	push_progress_changed.emit(pushes_completed, total_pushes)
	hold_visual_progress_changed.emit(0.0)


func set_session_active(active: bool) -> void:
	_session_active = active
	player.set_running(false)
	if active and pushes_completed < total_pushes and not _action_window_open:
		_walls_closing = true


func set_hold_progress(progress: float) -> void:
	if not _action_window_open:
		return
	_hold_retreat = clampf(progress, 0.0, 1.0)
	_apply_wall_positions(1.0, _hold_retreat)
	hold_visual_progress_changed.emit(_hold_retreat)
	_update_energy_wave(_hold_retreat)


func handle_hold_interrupted() -> void:
	if not _action_window_open:
		return
	_hold_retreat = 0.0
	_apply_wall_positions(1.0, 0.0)
	hold_visual_progress_changed.emit(0.0)
	energy_wave.hide()


func handle_valid_repetition(_data: Dictionary) -> void:
	if not enabled or not _session_active or not _action_window_open:
		return
	_set_action_window(false)
	pushes_completed += 1
	player.play_exercise_action()
	push_progress_changed.emit(pushes_completed, total_pushes)
	_play_push_burst()
	_hold_retreat = 0.0
	hold_visual_progress_changed.emit(0.0)
	await get_tree().create_timer(VisualPace.duration(0.45), false).timeout
	if pushes_completed < total_pushes:
		_begin_wave(pushes_completed)


func play_finish_sequence() -> void:
	_session_active = false
	_set_action_window(false)
	_walls_closing = false
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(wall_a, "position", _offscreen_position(wall_a.position, -1.0), 0.55)
	tween.tween_property(wall_b, "position", _offscreen_position(wall_b.position, 1.0), 0.55)
	await tween.finished
	energy_wave.hide()
	await get_tree().create_timer(0.3, false).timeout


func is_action_window_open() -> bool:
	return _action_window_open


func get_direction_label() -> String:
	return str(DIRECTION_NAMES.get(current_direction, ""))


func _begin_wave(wave_index: int) -> void:
	current_direction = DIRECTION_SEQUENCE[wave_index % DIRECTION_SEQUENCE.size()]
	direction_changed.emit(get_direction_label())
	_close_progress = 0.0
	_hold_retreat = 0.0
	energy_wave.hide()
	_apply_wall_positions(0.0, 0.0)
	wall_a.show()
	wall_b.show()
	_walls_closing = _session_active
	_set_action_window(false)


func _set_action_window(is_open: bool) -> void:
	if _action_window_open == is_open:
		return
	_action_window_open = is_open
	action_window_changed.emit(is_open)


func _apply_wall_positions(close_t: float, retreat_t: float) -> void:
	var gap := lerpf(SAFE_GAP, RETREAT_GAP, retreat_t)
	match current_direction:
		WallDirection.HORIZONTAL:
			wall_a.rotation = 0.0
			wall_b.rotation = PI
			var left_x := lerpf(-120.0, CENTER.x - gap * 0.5, close_t)
			var right_x := lerpf(1272.0, CENTER.x + gap * 0.5, close_t)
			wall_a.position = Vector2(left_x, CENTER.y - WALL_HALF_HEIGHT)
			wall_b.position = Vector2(right_x, CENTER.y - WALL_HALF_HEIGHT)
		WallDirection.VERTICAL:
			wall_a.rotation = PI * 0.5
			wall_b.rotation = -PI * 0.5
			var top_y := lerpf(-120.0, CENTER.y - gap * 0.5, close_t)
			var bottom_y := lerpf(760.0, CENTER.y + gap * 0.5, close_t)
			wall_a.position = Vector2(CENTER.x, top_y)
			wall_b.position = Vector2(CENTER.x, bottom_y)
		WallDirection.DIAGONAL_RIGHT, WallDirection.DIAGONAL_LEFT:
			# Both upper halves mirrored across the player; no lower buried wall.
			wall_a.rotation = PI * 0.25
			wall_b.rotation = PI * 0.75
			var offset_x := lerpf(190.0,370.0,retreat_t)
			var height := lerpf(170.0,100.0,retreat_t)
			wall_a.position = Vector2(-160,-160).lerp(Vector2(CENTER.x-offset_x,height),close_t)
			wall_b.position = Vector2(1312,-160).lerp(Vector2(CENTER.x+offset_x,height),close_t)



func _update_energy_wave(progress: float) -> void:
	if progress <= 0.0:
		energy_wave.hide()
		return
	energy_wave.show()
	energy_wave.position = CENTER
	var scale_value := lerpf(0.4, 1.4, progress)
	energy_wave.scale = Vector2(scale_value, scale_value)
	for child in energy_wave.get_children():
		if child is Polygon2D:
			child.modulate.a = lerpf(0.25, 0.85, progress)


func _play_push_burst() -> void:
	energy_wave.show()
	energy_wave.position = CENTER
	energy_wave.scale = Vector2(0.5, 0.5)
	var tween := create_tween()
	tween.tween_property(energy_wave, "scale", Vector2(2.2, 2.2), VisualPace.duration(0.35)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_callback(func() -> void: energy_wave.hide()).set_delay(VisualPace.duration(0.35))


func _offscreen_position(current: Vector2, direction_sign: float) -> Vector2:
	return current + Vector2(260.0 * direction_sign, 180.0 * direction_sign)
