extends Area2D

signal collided_with_player(player: Node)
signal reached_action_zone

const SPEED = 250.0

var _exercise_mode := false
var _movement_enabled := true
var _destroying := false
var _waiting_at_action_zone := false
var _action_zone_x := 0.0
var _exercise_approach_speed := 170.0

func set_rock_variant(index: int) -> void:
	var sprite: Sprite2D = $RockVisual/Base
	if index % 2 == 1:
		sprite.texture = preload("res://assets/shared/environment/moss_boulder.png")
		sprite.scale = Vector2(2,2)
		sprite.position = Vector2(0,-80)
		var collision: CollisionShape2D = $CollisionShape2D
		collision.shape = collision.shape.duplicate()
		collision.shape.size = Vector2(108,132)
		collision.position = Vector2(0,-66)
	# Large variant keeps the foot anchor but gets a private matching collider.

func _process(delta: float) -> void:
	if _destroying or not _movement_enabled:
		return
	var movement_speed: float = _exercise_approach_speed
	if not _exercise_mode:
		movement_speed = SPEED * float(Global.speed_multiplier)
	position.x -= movement_speed * delta
	if _exercise_mode and position.x <= _action_zone_x:
		position.x = _action_zone_x
		_waiting_at_action_zone = true
		_movement_enabled = false
		reached_action_zone.emit()
		return
	if position.x < -100:
		queue_free()


func configure_exercise_rock(action_zone_x: float, approach_speed: float) -> void:
	_exercise_mode = true
	_action_zone_x = action_zone_x
	_exercise_approach_speed = approach_speed


func set_movement_enabled(enabled: bool) -> void:
	_movement_enabled = enabled and not _waiting_at_action_zone


func destroy_by_exercise() -> void:
	if _destroying:
		return
	_destroying = true
	monitoring = false
	$CollisionShape2D.set_deferred("disabled", true)
	var fragments := Node2D.new()
	fragments.position = position + Vector2(0,-40)
	get_parent().add_child(fragments)
	for i in range(7):
		var chip := Polygon2D.new()
		chip.polygon = PackedVector2Array([Vector2(-6,-4),Vector2(5,-6),Vector2(7,3),Vector2(-3,6)])
		chip.color = Color("96815a") if i%2 == 0 else Color("574b34")
		fragments.add_child(chip)
		var debris := fragments.create_tween().set_parallel(true)
		debris.tween_property(chip,"position",Vector2((i-3)*24,-35-abs(i-3)*9),0.18)
		debris.tween_property(chip,"rotation",float(i-3),0.5)
		debris.chain().tween_property(chip,"position:y",55.0,0.32)
		debris.parallel().tween_property(chip,"modulate:a",0.0,0.32)
	var cleanup := fragments.create_tween()
	cleanup.tween_interval(0.6)
	cleanup.tween_callback(fragments.queue_free)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.5, 0.35), 0.25).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	await tween.finished
	queue_free()

# Đây là hàm Godot vừa tự tạo cho bạn
func _on_body_entered(body):
	if body.name != "Player" or _destroying:
		return
	if _exercise_mode:
		_destroying = true
		_movement_enabled = false
		set_deferred("monitoring", false)
		$CollisionShape2D.set_deferred("disabled", true)
		collided_with_player.emit(body)
		queue_free()
		return
	body.take_damage()
	queue_free()
