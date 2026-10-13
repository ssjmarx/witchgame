## The witch-sheet baker (tileset lab stage one): regenerates the colorless baseline
## only when missing or --regen (hand-edits survive), then colors it from SPRITE_WITCH.
## Run headless: Godot --headless --path . -s res://scripts/tools/bake_witch.gd [-- --regen]

extends SceneTree

const BakeLib = preload("res://scripts/tools/bake_lib.gd")
const ORIG := "res://assets/witch/witch-Sheet-outlined.png"
const GRAY := "res://assets/gray/witch/witch-Sheet-outlined.png"
const BAKED := "res://assets/baked/witch/witch-Sheet-outlined.png"

## One bake run: baseline (first time or --regen), then the color pass from SPRITE_WITCH.
func _init() -> void:
	var lib := BakeLib.new()
	if "--regen" in OS.get_cmdline_user_args() or not FileAccess.file_exists(GRAY):
		var src := Image.load_from_file(ORIG)
		if src == null or src.is_empty():
			print("BAKE FAIL: no original sheet at %s" % ORIG)
			quit(1)
			return
		var out: Array = lib.baseline_image(src, Palette.SPRITE_WITCH)
		DirAccess.make_dir_recursive_absolute("res://assets/gray/witch")
		if (out[0] as Image).save_png(GRAY) != OK:
			print("BAKE FAIL: cannot write %s" % GRAY)
			quit(1)
			return
		print("== baseline regenerated: %s" % GRAY)
		for line in out[1]:
			print("   %s" % line)
	var gray := Image.load_from_file(GRAY)
	if gray == null or gray.is_empty():
		print("BAKE FAIL: no baseline at %s -- run with --regen" % GRAY)
		quit(1)
		return
	var baked: Array = lib.color_image(gray, Palette.SPRITE_WITCH)
	var bimg: Image = baked[0]
	var opaque := 0
	for y in bimg.get_height():
		for x in bimg.get_width():
			if bimg.get_pixel(x, y).a8 > 0:
				opaque += 1
	DirAccess.make_dir_recursive_absolute("res://assets/baked/witch")
	if bimg.save_png(BAKED) != OK:
		print("BAKE FAIL: cannot write %s" % BAKED)
		quit(1)
		return
	print("== bake written: %s (%d unmapped grays, %d opaque pixels)" % [BAKED, baked[1], opaque])
	if opaque == 0:
		print("BAKE FAIL: zero opaque pixels -- the sheet baked fully transparent; regen the baseline with --regen")
		quit(1)
		return
	quit(0)
