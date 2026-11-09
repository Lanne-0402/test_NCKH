extends CharacterBody2D
const VisualPace = preload("res://ui/shared/visual_pace.gd")

# Lực nhảy (Số âm vì trong game 2D, trục Y hướng lên trên là số âm)
const JUMP_VELOCITY = -400.0

# Lấy trọng lực mặc định của Godot
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
@export var max_lives := 3
@export var enable_keyboard_jump := false

var lives := 3
var _running := false
var _run_clock := 0.0
var _action_tween: Tween
var _movement_locked := false
var _lock_position := Vector2.ZERO
var mk2: Node2D

@onready var visuals: Node2D = $Visuals
@onready var body_shape: ColorRect = $Visuals/Shape
@onready var arm_left: ColorRect = $Visuals/ArmLeft
@onready var arm_right: ColorRect = $Visuals/ArmRight


func _ready() -> void:
	lives = max_lives
	for child in visuals.get_children():
		if child is CanvasItem and child.name != "Shadow": child.hide()
	mk2 = preload("res://maps/shared/characters/player/gameplay_actor.gd").new()
	mk2.name = "Mk2"
	mk2.map_id = clampi(Global.selected_action,1,5)
	if mk2.map_id == 5: mk2.position.y = 44
	mk2.z_index = 30
	mk2.pose_id = [3,0,4,1,2][clampi(Global.selected_action,1,5)-1]
	mk2.outfit_enabled = true
	mk2.joints_visible = false
	mk2.scale = Vector2(2,2)
	mk2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visuals.add_child(mk2)


func _process(delta: float) -> void:
	var session := get_parent().get_node_or_null("ExerciseSession")
	mk2.visual_active = session != null and session.state == ExerciseSession.State.ACTIVE
	mk2.running = _running
	if mk2.visual_active:
		mk2.advance(delta * VisualPace.factor())
	else:
		mk2.refresh()
	if _running:
		_run_clock += delta * VisualPace.factor()
		var stride := sin(_run_clock * 12.0)
		visuals.position.y = -absf(stride) * 3.0
		arm_left.rotation = stride * 0.12
		arm_right.rotation = -stride * 0.12
	else:
		visuals.position.y = move_toward(visuals.position.y, 0.0, 30.0 * delta)
		arm_left.rotation = move_toward(arm_left.rotation, 0.0, 2.0 * delta)
		arm_right.rotation = move_toward(arm_right.rotation, 0.0, 2.0 * delta)

func _physics_process(delta):
	if _movement_locked:
		velocity = Vector2.ZERO
		global_position = _lock_position
		return

	# 1. TRỌNG LỰC: Nếu nhân vật không đứng trên sàn, nó sẽ bị rơi xuống
	if not is_on_floor():
		velocity.y += gravity * delta

	# 2. NHẢY: Nếu bấm phím Space (ui_accept) VÀ đang đứng trên sàn
	if enable_keyboard_jump and Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# 3. Lệnh bắt buộc để nhân vật di chuyển và tương tác vật lý
	move_and_slide()


func play_exercise_action() -> void:
	if is_instance_valid(_action_tween):
		_action_tween.kill()
	mk2.burst = 1.0
	if mk2.map_id in [4,5]:
		mk2.refresh()
		return
	mk2.amount = 1.0
	mk2.refresh()
	_action_tween = create_tween()
	_action_tween.tween_interval(VisualPace.duration(0.25))
	_action_tween.tween_property(mk2,"amount",0.0,VisualPace.duration(0.2))
	_action_tween.tween_callback(mk2.refresh)

func set_running(enabled: bool) -> void:
	_running = enabled


func set_movement_locked(locked: bool, anchor_position: Vector2 = Vector2.INF) -> void:
	_movement_locked = locked
	if not locked:
		velocity = Vector2.ZERO
		return
	if anchor_position != Vector2.INF:
		_lock_position = anchor_position
	velocity = Vector2.ZERO


func set_lock_position(anchor_position: Vector2) -> void:
	_lock_position = anchor_position
	if _movement_locked:
		velocity = Vector2.ZERO


func reset_lives() -> void:
	lives = max_lives
	body_shape.color = Color(0.20, 0.45, 0.85)
	visuals.modulate = Color.WHITE


func take_damage() -> int:
	lives = maxi(lives - 1, 0)
	_play_hit_reaction()
	return lives


func _play_hit_reaction() -> void:
	if is_instance_valid(_action_tween):
		_action_tween.kill()
	body_shape.color = Color(0.90, 0.18, 0.15)
	visuals.scale = Vector2.ONE
	visuals.modulate = Color.WHITE
	_action_tween = create_tween()
	_action_tween.tween_property(visuals, "modulate:a", 0.25, 0.08)
	_action_tween.tween_property(visuals, "modulate:a", 1.0, 0.08)
	_action_tween.tween_property(visuals, "modulate:a", 0.25, 0.08)
	_action_tween.tween_property(visuals, "modulate:a", 1.0, 0.08)
	_action_tween.tween_callback(func(): body_shape.color = Color(0.20, 0.45, 0.85))
