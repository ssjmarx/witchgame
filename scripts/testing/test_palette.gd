## The palette law's acceptance suite (world.md §9): the DB16 canon plus
## documented guests, tile banks of at most four and sprite banks of at most
## three, banks sorted dark to light -- law, machine-checked, not memory.

class_name TestPalette
extends TestSandbox

const PAL_PATH := "res://scripts/render/palette.gd"
const DB16: Array[String] = ["#140c1c", "#442434", "#30346d", "#4e4a4e", "#854c30", "#346524", "#d04648", "#757161", "#597dce", "#d27d2c", "#8595a1", "#6daa2c", "#d2aa99", "#6dc2ca", "#dad45e", "#deeed6"]

## The lab's example set: the palette proofs, in order.
func run_tests() -> void:
	_example("PT0  master is the DB16 canon, sixteen and unique", _pt0_master)
	_example("PT1  every tile bank draws from master+guest, at most four", _pt1_banks)
	_example("PT2  every sprite bank the same pool, at most three", _pt2_sprites)
	_example("PT3  banks sort dark to light -- index 0 is darkest", _pt3_luminance)
	_example("PT4  the baseline quantizer maps used colors to bank slots", _pt4_baseline)
	_example("PT5  the colorizer writes bank colors only", _pt5_colorize)
	_example("PT6  every baked atlas draws from its bank alone", _pt6_atlas_files)
	_example("PT7  the gray atlas holds levels only, every role populated", _pt7_gray_atlas)

## PT0: MASTER equals the canonical DB16 hex for hex -- a master change is a law change and fails here by design.
func _pt0_master() -> String:
	if Palette.MASTER.size() != 16:
		return "master holds %d colors, the canon is 16" % Palette.MASTER.size()
	var seen := {}
	for k in Palette.MASTER.size():
		var c: Color = Palette.MASTER[k]
		if c != Color(DB16[k]):
			return "master[%d] is %s, the canon says %s" % [k, c.to_html(false), DB16[k]]
		if seen.has(c):
			return "master holds %s twice" % c.to_html(false)
		seen[c] = true
	return ""

## PT1: every BANK_* constant holds 1-4 colors from master+guest, found by reflection -- a new bank is checked the day it is typed.
func _pt1_banks() -> String:
	var consts := _pal_map()
	var pool := _pool()
	for key in consts:
		if not String(key).begins_with("BANK_"):
			continue
		var bank: Array = consts[key]
		if bank.size() < 1 or bank.size() > 4:
			return "%s holds %d colors, the ceiling is 4" % [key, bank.size()]
		for c in bank:
			if not pool.has(c):
				return "%s draws %s, outside master+guest" % [key, c.to_html(false)]
	return ""

## PT2: every SPRITE_* constant holds 1-3 colors from the same pool -- the witch's bank today, her sisters' tomorrow.
func _pt2_sprites() -> String:
	var consts := _pal_map()
	var pool := _pool()
	for key in consts:
		if not String(key).begins_with("SPRITE_"):
			continue
		var bank: Array = consts[key]
		if bank.size() < 1 or bank.size() > 3:
			return "%s holds %d colors, the ceiling is 3" % [key, bank.size()]
		for c in bank:
			if not pool.has(c):
				return "%s draws %s, outside master+guest" % [key, c.to_html(false)]
	return ""

## PT3: tile-bank luminance never decreases brightward -- index 0 darkest is the convention every renderer read trusts.
func _pt3_luminance() -> String:
	var consts := _pal_map()
	for key in consts:
		if not String(key).begins_with("BANK_"):
			continue
		var bank: Array = consts[key]
		var last := -1.0
		for c: Color in bank:
			var lum := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			if lum < last - 0.001:
				return "%s darkens after luminance %.3f -- banks run dark to light" % [key, last]
			last = lum
	return ""

## The lawful pool every bank draws from: master plus guests, compared by value.
func _pool() -> Array:
	var pool := Palette.MASTER.duplicate()
	pool.append_array(Palette.GUEST)
	return pool

## Palette's declared constants by reflection: the class name is a type to the analyzer, so the script resource is loaded and cast -- the cast forces the receiver to GDScript, the one shape every analyzer accepts.
func _pal_map() -> Dictionary:
	return (load(PAL_PATH) as GDScript).get_script_constant_map()

## PT4: the bake library's baseline pass quantizes used colors to bank slots as baseline grays, preserves alpha, and warns when distinct colors exceed the bank -- the pipeline's law, machine-checked.
func _pt4_baseline() -> String:
	var lib = preload("res://scripts/tools/bake_lib.gd").new()
	var src := Image.create(4, 1, false, Image.FORMAT_RGBA8)
	src.set_pixel(0, 0, Palette.INK)
	src.set_pixel(1, 0, Palette.RED)
	src.set_pixel(2, 0, Palette.INDIGO)
	src.set_pixel(3, 0, Color(0, 0, 0, 0))
	var out: Array = lib.baseline_image(src, Palette.SPRITE_WITCH)
	var img: Image = out[0]
	var report: PackedStringArray = out[1]
	var seen := {}
	for x in 4:
		var c := img.get_pixel(x, 0)
		if x == 3:
			if c.a8 != 0:
				return "the transparent pixel became opaque"
			continue
		if c.a8 == 0:
			return "opaque pixel %d lost its alpha" % x
		if not _is_level(c):
			return "pixel %d is no baseline gray (%s)" % [x, c.to_html(false)]
		seen[c.to_html(false)] = true
	if seen.size() != 3:
		return "three distinct colors collapsed to %d grays, want 3" % seen.size()
	if report.size() != 3:
		return "the report holds %d lines, want 3 mappings" % report.size()
	var over := Image.create(5, 1, false, Image.FORMAT_RGBA8)
	over.set_pixel(0, 0, Palette.INK)
	over.set_pixel(1, 0, Palette.RED)
	over.set_pixel(2, 0, Palette.INDIGO)
	over.set_pixel(3, 0, Palette.OLIVE)
	over.set_pixel(4, 0, Palette.TAN)
	var warn: Array = lib.baseline_image(over, Palette.SPRITE_WITCH)
	var wreport: PackedStringArray = warn[1]
	if wreport.size() != 6 or not String(wreport[5]).begins_with("WARN"):
		return "five colors against three slots must append one WARN line (report holds %d)" % wreport.size()
	return ""

## PT5: the colorize pass maps baseline grays back to bank slots and writes bank colors only, counting hand-edit grays that match no level.
func _pt5_colorize() -> String:
	var lib = preload("res://scripts/tools/bake_lib.gd").new()
	var src := Image.create(5, 1, false, Image.FORMAT_RGBA8)
	src.set_pixel(0, 0, Palette.BASELINE_LEVELS[0])
	src.set_pixel(1, 0, Palette.BASELINE_LEVELS[1])
	src.set_pixel(2, 0, Palette.BASELINE_LEVELS[2])
	src.set_pixel(3, 0, Color(0, 0, 0, 0))
	src.set_pixel(4, 0, Color(0.25, 0.5, 0.75))
	var out: Array = lib.color_image(src, Palette.SPRITE_WITCH)
	var img: Image = out[0]
	var unmapped: int = out[1]
	if unmapped != 1:
		return "the off-level gray must count as unmapped (got %d)" % unmapped
	for x in 5:
		var c := img.get_pixel(x, 0)
		if x == 3 or x == 4:
			if c.a8 != 0:
				return "pixel %d should stay transparent" % x
			continue
		if not Palette.SPRITE_WITCH.has(c):
			return "pixel %d is %s, outside SPRITE_WITCH" % [x, c.to_html(false)]
	return ""

## True when c sits within tolerance of some baseline level.
func _is_level(c: Color) -> bool:
	for lv in Palette.BASELINE_LEVELS:
		if absi(c.r8 - lv.r8) <= 8 and absi(c.g8 - lv.g8) <= 8 and absi(c.b8 - lv.b8) <= 8:
			return true
	return false

## PT6: the file gate -- every pixel of every baked atlas is its bank's color or transparent, and every role rect holds something opaque (the invisible-witch lesson: the artifact is gated, not just the math).
func _pt6_atlas_files() -> String:
	var TileAtlas = preload("res://scripts/render/tile_atlas.gd")
	for kind in TileAtlas.FILES:
		var img := Image.load_from_file(TileAtlas.FILES[kind])
		if img == null or img.is_empty():
			return "%s atlas missing -- run bake_tiles.gd and let the editor import" % kind
		var bank: Array = TileAtlas.BANKS[kind]
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a8 == 0:
					continue
				if not bank.has(c):
					return "%s atlas pixel (%d, %d) is %s, outside its bank" % [kind, x, y, c.to_html(false)]
		for role in TileAtlas.LAYOUT:
			var r: Rect2i = TileAtlas.LAYOUT[role]
			var opaque := false
			for y in range(r.position.y, r.position.y + r.size.y):
				for x in range(r.position.x, r.position.x + r.size.x):
					if img.get_pixel(x, y).a8 > 0:
						opaque = true
						break
				if opaque:
					break
			if not opaque:
				return "%s atlas role %s holds no opaque pixel" % [kind, role]
	return ""

## PT7: the gray source holds baseline levels (or transparency) only -- the hand-editable truth stays quantized.
func _pt7_gray_atlas() -> String:
	var TileAtlas = preload("res://scripts/render/tile_atlas.gd")
	var img := Image.load_from_file("res://assets/gray/tiles.png")
	if img == null or img.is_empty():
		return "gray atlas missing -- run bake_tiles.gd"
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a8 == 0:
				continue
			if not _is_level(c):
				return "gray pixel (%d, %d) is %s, no baseline level" % [x, y, c.to_html(false)]
	return ""
