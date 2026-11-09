class_name TrackingStability
extends Node

# Temporary feature switch: set true to restore hearts and stability-based grading.
const ENABLED := false

signal stability_changed(current: int, maximum: int)
signal tracking_penalty_applied(current: int, grace_seconds: float)

@export var maximum_stability := 3
@export var grace_seconds := 3.0

var stability := 3
var _incident_active := false
var _incident_token := 0
var _session: ExerciseSession
var _pose_input: Node


func setup(session: ExerciseSession, pose_input: Node) -> void:
	_session = session
	_pose_input = pose_input
	if not _session.state_changed.is_connected(_on_session_state_changed):
		_session.state_changed.connect(_on_session_state_changed)
	reset()


func reset() -> void:
	_incident_active = false
	_incident_token += 1
	stability = maximum_stability
	stability_changed.emit(stability, maximum_stability)


func penalize_tracking_loss() -> int:
	if not ENABLED:
		return stability
	stability = maxi(stability - 1, 0)
	stability_changed.emit(stability, maximum_stability)
	return stability


func _on_session_state_changed(current: ExerciseSession.State, previous: ExerciseSession.State) -> void:
	if not ENABLED:
		return
	if current == ExerciseSession.State.ACTIVE:
		_incident_active = false
		_incident_token += 1
		return
	if current != ExerciseSession.State.TRACKING_LOST \
			or previous != ExerciseSession.State.ACTIVE \
			or not _pose_input.provider_connected \
			or _incident_active:
		return
	_incident_active = true
	_incident_token += 1
	_apply_penalty_after_grace(_incident_token)


func _apply_penalty_after_grace(incident_token: int) -> void:
	await get_tree().create_timer(grace_seconds, false).timeout
	if not ENABLED or incident_token != _incident_token \
			or not _incident_active \
			or _session.state != ExerciseSession.State.TRACKING_LOST \
			or not _pose_input.provider_connected:
		return
	penalize_tracking_loss()
	tracking_penalty_applied.emit(stability, grace_seconds)
