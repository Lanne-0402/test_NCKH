extends Node
const Sync := preload("res://core/autoload/report_sync.gd")
const Display := preload("res://ui/shared/session_display.gd")
func _ready() -> void: call_deferred("_run")
func _run() -> void:
	assert(not Global.persistence_enabled)
	var decoder := Sync.new()
	add_child(decoder)
	for result in [HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_TIMEOUT, HTTPRequest.RESULT_CONNECTION_ERROR]:
		var reply := decoder._decode_reply(result, 0, PackedByteArray())
		assert(reply.code == 0 and reply.has("error"))
	for body in ["", "  ", "<html>502 Bad Gateway</html>", "{broken", "null", "[]", "42"]:
		assert(decoder._decode_reply(HTTPRequest.RESULT_SUCCESS, 200, body.to_utf8_buffer()).has("error"))
	assert(not decoder._decode_reply(HTTPRequest.RESULT_SUCCESS, 200, '{"ok":true}'.to_utf8_buffer()).has("error"))
	var fake = preload("res://tests/core/report_fake_sync.gd").new()
	add_child(fake)
	var job := {"patient_id":"BN001","reset":false,"token":"test-token","generation":0}
	var remote := {"code":200,"data":{"patient_id":"BN001","sessions":[]}}
	for bad in [{"code":200,"data":{}}, {"code":404,"data":{}}, {"code":200,"data":{"patient_id":"WRONG"}}, decoder._decode_reply(0,200,"<html/>".to_utf8_buffer())]:
		fake.calls.clear()
		fake.replies = [bad]
		assert(not await fake._perform(job))
		assert(fake.calls.size() == 1 and not Global.cloud_is_online)
	for bad_ack in [{}, {"ok":false,"patient_id":"BN001"}, {"ok":true,"patient_id":"WRONG"}, {"ok":true,"patient_id":"BN001","profile":{"patient_id":"WRONG"}}]:
		fake.replies = [remote,{"code":200,"data":bad_ack}]
		assert(not await fake._perform(job))
	fake.replies = [{"code":404,"data":{"error":"PATIENT_NOT_FOUND"}}, {"code":200,"data":{"ok":true,"patient_id":"BN001"}}]
	assert(await fake._perform(job))
	var reset_job := {"patient_id":"BN001","reset":true,"token":"test-reset","generation":0}
	for body in [{}, {"ok":true}, {"ok":true,"generation":2}, {"ok":false,"generation":1}]:
		fake.replies = [{"code":200,"data":body}]
		assert(not await fake._perform(reset_job))
	fake.replies = [{"code":200,"data":{"ok":true,"generation":1}}]
	assert(await fake._perform(reset_job))
	# Exercise the actual outbox loop using an isolated save file, never user://.
	Global.save_path = "res://report-response-test.json"
	Global.persistence_enabled = true
	Global.cloud_db_enabled = true
	Global.cloud_db_provider = "mongodb"
	Global.cloud_db_url = "mongodb://localhost:27017"
	Global.cloud_outbox = [job.duplicate(true)]
	fake.replies = [decoder._decode_reply(0,200,PackedByteArray())]
	await fake.kick()
	assert(Global.cloud_outbox.size() == 1 and not fake.busy)
	fake.replies = [remote,{"code":200,"data":{"ok":true,"patient_id":"BN001"}}]
	await fake.kick()
	assert(Global.cloud_outbox.is_empty() and Global.cloud_is_online)
	Global.persistence_enabled = false
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = "res://report-response-test.json" + suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	assert(Display.duration({"seconds":3661},"seconds") == "01:01:01")
	assert(Display.duration({"seconds":59},"seconds") == "00:00:59")
	decoder.queue_free()
	fake.queue_free()
	await get_tree().process_frame
	print("REPORT_RESPONSE_PASS: transport, JSON/schema failures, acknowledgments, reset, outbox retry, duration")
	get_tree().quit()
