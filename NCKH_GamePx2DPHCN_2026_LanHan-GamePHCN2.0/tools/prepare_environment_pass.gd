extends SceneTree
## Deterministic sprite extraction only. Never imports entire source packs.
func _initialize() -> void:
	var source := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source-assets="): source = arg.trim_prefix("--source-assets=")
	assert(not source.is_empty(), "Pass --source-assets=<archive>/assets")
	var root := source+"/itch.io/Legacy-Fantasy - High Forest 2.0/Legacy-Fantasy - High Forest 2.3/Assets/"
	var selections := [
		["Buildings.png",Rect2i(272,240,128,128),"assets/map_1/goal/stone_mine_entrance.png"],
		["Props-Rocks.png",Rect2i(0,80,64,80),"assets/shared/environment/moss_boulder.png"],
		["Props-Rocks.png",Rect2i(208,48,64,32),"assets/shared/environment/long_rock.png"]
	]
	for entry in selections:
		var image := Image.load_from_file(root+entry[0])
		assert(image != null and not image.is_empty())
		var path: String = "res://"+entry[2]
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		assert(image.get_region(entry[1]).save_png(path) == OK)
	print("ENVIRONMENT_EXPORT: PASS (3 selected crops, originals untouched)")
	quit()
