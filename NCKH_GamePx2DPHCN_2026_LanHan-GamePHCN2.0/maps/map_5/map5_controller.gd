class_name Map5Controller
extends Node

signal stretch_progress_changed(completed: int, total: int)
signal bonus_changed(current: int, maximum: int)
signal action_window_changed(is_open: bool)
signal hold_visual_progress_changed(progress: float)
signal side_changed(side_label: String)

const SIDE_LABELS: Array[String] = ["TAY TRÁI", "TAY PHẢI"]
const BONUS_PER_STRETCH := 100
const MAX_BONUS := 100

var total_stretches := 2
var stretches_completed := 0
var bonus_points := 0
var enabled := false
var _session_active := false
var _action_window_open := false
var _current_side_index := 0

@onready var player: CharacterBody2D = $"../Player"
@onready var rest_zone: Node2D = $"../Map5RestZone"
@onready var player_anchor: Marker2D = $"../Map5RestZone/PlayerAnchor"
@onready var hot_spring: Node2D = $"../Map5RestZone/HotSpring"
@onready var steam: Node2D = $"../Map5RestZone/Steam"
@onready var side_left: Node2D = $"../Map5RestZone/SideIndicatorLeft"
@onready var side_right: Node2D = $"../Map5RestZone/SideIndicatorRight"


func _ready() -> void:
	call_deferred("_anchor_player")


func setup_map(required_stretches: int) -> void:
	enabled = true
	total_stretches = maxi(required_stretches, 1)
	stretches_completed = 0
	bonus_points = 0
	_current_side_index = 0
	_reset_visuals()
	_anchor_player()
	_set_action_window(false)
	_emit_side(1)
	_update_side_indicators(1)
	stretch_progress_changed.emit(stretches_completed, total_stretches)
	bonus_changed.emit(bonus_points, MAX_BONUS)
	hold_visual_progress_changed.emit(0.0)


func set_session_active(active: bool) -> void:
	_session_active = active
	player.set_running(false)
	_anchor_player()
	_set_action_window(active)


func set_current_phase(phase: int) -> void:
	_current_side_index = clampi(phase - 1, 0, SIDE_LABELS.size() - 1)
	_emit_side(phase)
	_update_side_indicators(phase)
	if is_instance_valid(player) and is_instance_valid(player.mk2):
		player.mk2.mirrored = (phase == 2)
		player.mk2.amount = 0.0
		player.mk2.refresh()
	_reset_hold_visual()
	_anchor_player()


func handle_hold_started() -> void:
	if not _action_window_open:
		return
	if is_instance_valid(player) and is_instance_valid(player.mk2):
		player.mk2.amount = 1.0
		player.mk2.refresh()


func set_hold_progress(progress: float) -> void:
	if not _action_window_open:
		return
	var clamped: float = clampf(progress, 0.0, 1.0)
	if clamped > 0.0 and is_instance_valid(player) and is_instance_valid(player.mk2):
		player.mk2.amount = 1.0
		player.mk2.refresh()
	_update_steam(clamped)
	hold_visual_progress_changed.emit(clamped)


func handle_hold_interrupted() -> void:
	if not _action_window_open:
		return
	if is_instance_valid(player) and is_instance_valid(player.mk2):
		player.mk2.amount = 0.0
		player.mk2.refresh()
	_reset_hold_visual()
	_anchor_player()


func handle_valid_repetition(_data: Dictionary) -> void:
	if not enabled or not _session_active or not _action_window_open:
		return
	stretches_completed += 1
	bonus_points = mini(bonus_points + BONUS_PER_STRETCH, MAX_BONUS)
	_anchor_player()
	player.play_exercise_action()
	stretch_progress_changed.emit(stretches_completed, total_stretches)
	bonus_changed.emit(bonus_points, MAX_BONUS)
	_play_bonus_burst()
	_reset_hold_visual()


func play_finish_sequence() -> void:
	_session_active = false
	_set_action_window(false)
	_update_steam(1.0)
	_anchor_player()
	var tween := create_tween()
	tween.tween_property(steam, "scale", Vector2(1.35, 1.35), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	await get_tree().create_timer(0.35, false).timeout


func is_action_window_open() -> bool:
	return _action_window_open


func get_side_label() -> String:
	return SIDE_LABELS[_current_side_index]


func _emit_side(phase: int) -> void:
	var index := clampi(phase - 1, 0, SIDE_LABELS.size() - 1)
	side_changed.emit(SIDE_LABELS[index])


func _set_action_window(is_open: bool) -> void:
	if _action_window_open == is_open:
		return
	_action_window_open = is_open
	action_window_changed.emit(is_open)
	if is_open:
		_anchor_player()
	if not is_open:
		_reset_hold_visual()


func _anchor_player() -> void:
	if not is_instance_valid(player) or not is_instance_valid(player_anchor):
		return
	player.set_movement_locked(true, player_anchor.global_position)


func _update_side_indicators(phase: int) -> void:
	side_left.visible = phase == 1
	side_right.visible = phase == 2


func _reset_hold_visual() -> void:
	_update_steam(0.0)
	hold_visual_progress_changed.emit(0.0)


func _reset_visuals() -> void:
	steam.scale = Vector2.ONE
	side_left.visible = false
	side_right.visible = false
	_update_steam(0.0)


func _update_steam(progress: float) -> void:
	var clamped: float = clampf(progress, 0.0, 1.0)
	var base_y: float = player_anchor.position.y - 72.0
	steam.position = Vector2(player_anchor.position.x, base_y - clamped * 18.0)
	steam.scale = Vector2.ONE.lerp(Vector2(1.25, 1.25), clamped)
	for child in steam.get_children():
		if child is CanvasItem:
			child.modulate.a = lerpf(0.25, 0.85, clamped)
	var pool_glow: CanvasItem = hot_spring.get_node("PoolGlow")
	pool_glow.modulate = Color(1.0, 1.0, 1.0, lerpf(0.65, 1.0, clamped))


func _play_bonus_burst() -> void:
	var tween := create_tween()
	tween.tween_property(hot_spring, "scale", Vector2(1.04, 1.04), 0.12)
	tween.tween_property(hot_spring, "scale", Vector2.ONE, 0.18)
