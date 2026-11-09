extends SceneTree
func _initialize() -> void:
	var source := "D:/-NCKH-GamePixel2D_PHCN/ASSETS_UNUSED_2026-10-09/assets/itch.io/Legacy-Fantasy - High Forest 2.0/Legacy-Fantasy - High Forest 2.3/Trees/Green-Tree.png"
	var image := Image.load_from_file(source)
	assert(not image.is_empty())
	DirAccess.make_dir_recursive_absolute("res://assets/map_4/goal")
	assert(image.get_region(Rect2i(0,1088,80,112)).save_png("res://assets/map_4/goal/summit_tree.png") == OK)
	quit()
