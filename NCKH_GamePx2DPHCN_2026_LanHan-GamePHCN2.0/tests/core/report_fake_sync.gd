extends "res://core/autoload/report_sync.gd"
var replies: Array = []
var calls: Array = []
func _request(path: String, method: int, payload: Dictionary = {}) -> Dictionary:
	calls.append({"path": path, "method": method, "payload": payload.duplicate(true)})
	await get_tree().process_frame
	return replies.pop_front()
