extends RefCounted

static func completed(s: Dictionary) -> bool:
	return str(s.get("status", "")) == "completed" or (not s.has("status") and not str(s.get("completed_at_utc", "")).is_empty())

static func merge_profile(local: Dictionary, remote: Dictionary) -> Dictionary:
	var lg := int(local.get("generation", 0))
	var rg := int(remote.get("generation", 0))
	if rg > lg: return remote.duplicate(true)
	if lg > rg: return local.duplicate(true)
	var out := remote.duplicate(true)
	if str(local.get("updated_at_utc", "")) > str(remote.get("updated_at_utc", "")):
		out = local.duplicate(true)
	var pid := str(out.get("patient_id", ""))
	var sessions := {}
	for s in remote.get("sessions", []) + local.get("sessions", []):
		if s is Dictionary and str(s.get("patient_id", "")) == pid and not str(s.get("session_id", "")).is_empty():
			sessions[str(s.session_id)] = s
	out["sessions"] = sessions.values()
	var points := {}
	for p in remote.get("rom_history", []) + local.get("rom_history", []):
		if not p is Dictionary: continue
		var key := str(p.get("date", "")) + ":" + str(p.get("source", "legacy"))
		if not points.has(key) or float(p.get("rom_angle", 0)) > float(points[key].get("rom_angle", 0)):
			points[key] = p
	out["rom_history"] = points.values()
	var calibrations := calibration_points(out["rom_history"])
	if not calibrations.is_empty(): out["max_rom_angle"] = float(calibrations[-1].rom_angle)
	var levels := {}
	for i in range(1, 6):
		levels[str(i)] = maxi(int(local.get("levels", {}).get(str(i), 1)), int(remote.get("levels", {}).get(str(i), 1)))
	out["levels"] = levels
	return out

static func calibration_points(history: Array) -> Array:
	var daily := {}
	for p in history:
		if not p is Dictionary or str(p.get("source", "")) != "calibration": continue
		var angle := float(p.get("rom_angle", -1))
		var date := str(p.get("date", ""))
		if not is_finite(angle) or angle <= 0 or date.length() != 10: continue
		if not daily.has(date) or angle > float(daily[date].rom_angle): daily[date] = p
	var result: Array = daily.values()
	result.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.date) < str(b.date))
	return result
