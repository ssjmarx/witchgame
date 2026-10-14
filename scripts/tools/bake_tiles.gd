## The tile-atlas baker (tileset lab stage two): paints the grayscale atlas from
## slot-index painters per TileAtlas.LAYOUT, then colors one bake per bank.
## Run headless: Godot --headless --path . -s res://scripts/tools/bake_tiles.gd [-- --regen]

extends SceneTree

const TileAtlas = preload("res://scripts/render/tile_atlas.gd")
const BakeLib = preload("res://scripts/tools/bake_lib.gd")
const GRAY := "res://assets/gray/tiles.png"

## One bake run: paint or reuse the gray atlas, then write every bank-colored bake with the opaque guard.
func _init() -> void:
	var gray: Image = null
	if "--regen" in OS.get_cmdline_user_args() or not FileAccess.file_exists(GRAY):
		gray = Image.create(TileAtlas.GRID * TileAtlas.CELL, 5 * TileAtlas.CELL, false, Image.FORMAT_RGBA8)
		_paint_all(gray)
		DirAccess.make_dir_recursive_absolute("res://assets/gray")
		if gray.save_png(GRAY) != OK:
			print("BAKE FAIL: cannot write %s" % GRAY)
			quit(1)
			return
		print("== gray atlas painted: %s (40 roles)" % GRAY)
	else:
		gray = Image.load_from_file(GRAY)
		if gray == null or gray.is_empty():
			print("BAKE FAIL: no gray atlas at %s -- run with --regen" % GRAY)
			quit(1)
			return
	var lib := BakeLib.new()
	DirAccess.make_dir_recursive_absolute("res://assets/baked")
	for kind in TileAtlas.BANKS:
		var out: Array = lib.color_image(gray, TileAtlas.BANKS[kind])
		var img: Image = out[0]
		var opaque := 0
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a8 > 0:
					opaque += 1
		var path: String = TileAtlas.FILES[kind]
		if img.save_png(path) != OK:
			print("BAKE FAIL: cannot write %s" % path)
			quit(1)
			return
		print("== bake written: %s (%d unmapped, %d opaque pixels)" % [path, out[1], opaque])
		if opaque == 0:
			print("BAKE FAIL: zero opaque pixels in the %s atlas" % kind)
			quit(1)
			return
	quit(0)

## Paint every role: flat fills and strips, dither ramps, ember frames, lick variants.
func _paint_all(img: Image) -> void:
	_flat(img, TileAtlas.LAYOUT["stone_fill"], 1)
	_flat(img, TileAtlas.LAYOUT["wood_fill"], 1)
	_flat(img, TileAtlas.LAYOUT["soil_fill"], 1)
	for pre in ["stone", "wood"]:
		for e in ["t", "r", "b", "l"]:
			_flat(img, TileAtlas.LAYOUT["%s_lip_%s" % [pre, e]], 2)
			_flat(img, TileAtlas.LAYOUT["%s_seam_%s" % [pre, e]], 0)
	_flat(img, TileAtlas.LAYOUT["soil_lip_t"], 2)
	_dither(img, TileAtlas.LAYOUT["soil_damp_25"], 0, 1, 0)
	_dither(img, TileAtlas.LAYOUT["soil_damp_50"], 0, 2, 0)
	_dither(img, TileAtlas.LAYOUT["soil_damp_75"], 0, 3, 0)
	_dither(img, TileAtlas.LAYOUT["soil_damp_full"], 0, 4, 0)
	for gas in ["smoke", "steam"]:
		var phase := 1 if gas == "steam" else 0
		for d in [["25", 1], ["50", 2], ["75", 3], ["full", 4]]:
			_dither(img, TileAtlas.LAYOUT["%s_%s" % [gas, d[0]]], 0, d[1], phase)
	for f in 3:
		_flat(img, TileAtlas.LAYOUT["fire_ember_%d" % f], f + 1)
		_lick(img, TileAtlas.LAYOUT["fire_lick_%d" % f], f)

## Fill a layout rect flat with baseline slot s.
func _flat(img: Image, r: Rect2i, s: int) -> void:
	var c: Color = Palette.BASELINE_LEVELS[s]
	c.a = 1.0
	img.fill_rect(r, c)

## Dither a layout rect at density 1-4 (quarter steps) on checker phase 0 or 1 -- smoke and steam interleave so a shared subtile mixes without blending.
func _dither(img: Image, r: Rect2i, s: int, density: int, phase: int) -> void:
	var c: Color = Palette.BASELINE_LEVELS[s]
	for y in r.size.y:
		for x in r.size.x:
			var lit := false
			if density >= 4:
				lit = true
			elif density == 2:
				lit = (x + y + phase) % 2 == 0
			elif density == 1:
				lit = (x + phase) % 2 == 0 and (y + phase) % 2 == 0
			else:
				lit = not ((x + 1 - phase) % 2 == 0 and (y + 1 - phase) % 2 == 0)
			if lit:
				img.set_pixel(r.position.x + x, r.position.y + y, c)

## One flame lick variant: a base column, a brightening tongue, a hot tip -- proportions per variant.
func _lick(img: Image, r: Rect2i, v: int) -> void:
	var base: Color = Palette.BASELINE_LEVELS[1]
	var tongue: Color = Palette.BASELINE_LEVELS[2]
	var tip: Color = Palette.BASELINE_LEVELS[3]
	var cx := r.position.x + 2 + v
	img.fill_rect(Rect2i(r.position.x, r.position.y + 3, 8, 5), base)
	img.fill_rect(Rect2i(cx, r.position.y + 8 - (5 + v), 2, 5 + v), tongue)
	img.set_pixel(cx, r.position.y + 8 - (5 + v), tip)