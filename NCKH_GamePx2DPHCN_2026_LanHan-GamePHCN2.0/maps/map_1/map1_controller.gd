class_name Map1Controller
extends Node
const VisualPace = preload("res://ui/shared/visual_pace.gd")

signal rock_progress_changed(destroyed: int, total: int)
signal action_window_changed(is_open: bool)

const ROCK_SCENE := preload("res://maps/map_1/obstacle.tscn")

@export var rock_approach_speed := 170.0

var total_rocks := 20
var stability: int:
	get:
		var tracker: Node = get_node_or_null("../TrackingStability")
		return int(tracker.stability) if tracker else 3

var rocks_destroyed := 0
var enabled := false
var _session_active := false
var _current_rock
var _action_window_open := false

@onready var spawn_position: Marker2D = $"../SpawnPosition"
@onready var action_zone: Marker2D = $"../Map1ActionZone"
@onready var player = $"../Player"
@onready var cave: Node2D = $"../Map1EndCave"


func setup_map(required_rocks: int) -> void:
	enabled = true
	total_rocks = maxi(required_rocks, 1)
	reset_map_progress()


func reset_map_progress() -> void:
	_clear_current_rock()
	rocks_destroyed = 0
	cave.hide()
	rock_progress_changed.emit(rocks_destroyed, total_rocks)
	_set_action_window(false)


func penalize_tracking_loss() -> int:
	var tracker: Node = get_node_or_null("../TrackingStability")
	return int(tracker.penalize_tracking_loss()) if tracker else 3


func set_session_active(active: bool) -> void:
	_session_active = active
	player.set_running(active and not _action_window_open)
	player.mk2.charging = active and _action_window_open
	if is_instance_valid(_current_rock):
		_current_rock.set_movement_enabled(active and not _action_window_open)
	elif enabled and active and rocks_destroyed < total_rocks:
		_spawn_next_rock()


func handle_valid_repetition(_data: Dictionary) -> void:
	if not enabled or not _session_active or not _action_window_open or rocks_destroyed >= total_rocks:
		return
	if not is_instance_valid(_current_rock):
		return

	var rock_to_break = _current_rock
	_current_rock = null
	_set_action_window(false)
	rocks_destroyed += 1
	player.play_exercise_action()
	rock_to_break.destroy_by_exercise()
	rock_progress_changed.emit(rocks_destroyed, total_rocks)

	if rocks_destroyed < total_rocks:
		call_deferred("_spawn_if_session_active")


func play_finish_sequence() -> void:
	if not enabled:
		return
	_session_active = false
	player.set_running(false)
	cave.position = Vector2(1180.0, 320.0)
	cave.show()
	var tween := create_tween()
	tween.tween_property(cave, "position:x", 930.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished
	await get_tree().create_timer(0.6, false).timeout


func _spawn_if_session_active() -> void:
	if _session_active and not is_instance_valid(_current_rock):
		_spawn_next_rock()


func _spawn_next_rock() -> void:
	if not enabled or rocks_destroyed >= total_rocks or is_instance_valid(_current_rock):
		return
	_current_rock = ROCK_SCENE.instantiate()
	_current_rock.set_rock_variant(rocks_destroyed)
	_current_rock.position = spawn_position.position
	_current_rock.configure_exercise_rock(action_zone.position.x, rock_approach_speed * VisualPace.factor())
	_current_rock.set_movement_enabled(_session_active)
	_current_rock.reached_action_zone.connect(_on_rock_reached_action_zone)
	_current_rock.collided_with_player.connect(_on_rock_collided_with_player)
	get_parent().add_child(_current_rock)
	_set_action_window(false)


func _on_rock_reached_action_zone() -> void:
	if enabled and _session_active and is_instance_valid(_current_rock):
		_set_action_window(true)


func _on_rock_collided_with_player(body: Node) -> void:
	if not enabled or body != player:
		return
	_current_rock = null
	_set_action_window(false)
	call_deferred("_spawn_if_session_active")


func is_action_window_open() -> bool:
	return _action_window_open


func _set_action_window(is_open: bool) -> void:
	if _action_window_open == is_open:
		return
	_action_window_open = is_open
	player.set_running(_session_active and not is_open)
	player.mk2.charging = _session_active and is_open
	action_window_changed.emit(is_open)


func _clear_current_rock() -> void:
	if is_instance_valid(_current_rock):
		_current_rock.queue_free()
	_current_rock = null
