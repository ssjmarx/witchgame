## Soil sandbox — solids, damp, and mortar over the shared packet.
## 1 stone / 2 water / 3 soil select material, LMB paints, RMB erases.
## K runs the soil acceptance suite headlessly and reports PASS/FAIL.

extends TestSandbox

const PAINT_DOSE := 64    # water units added per tick while painting

# F1-F11 soil acceptance diagrams (F6 and F8 are dead keys on this rig): s stone, w water 255, d soil full, t soil top-half, . air
const PRESETS := {
	KEY_F1: [
		".d.",
		".d.",
		".d.",
		".d.",
		".d.",
	],
	KEY_F2: [
		"sds",
		".s.",
	],
	KEY_F3: [
		"t",
		"t",
		"t",
		".",
		".",
	],
	KEY_F4: [
		"d",
		"w",
		".",
	],
	KEY_F5: [
		"..",
		"..",
		"dd",
		"ww",
		"ww",
	],
	KEY_F7: [
		"s",
		"d",
		"w",
	],
	KEY_F9: [
		"w",
		"d",
		"d",
		"d",
	],
	KEY_F10: [
		".d.",
		".d.",
		".d.",
	],
	KEY_F11: [
		"d",
	],
}

var sand: GridSand
var reactions: GridReactions

## Build the sand and reaction engines, bind the renderer's solid flow, load the spread demo.
func _setup() -> void:
	sand = GridSand.new(GRID_W, GRID_H, stone, water)
	reactions = GridReactions.new(GRID_W, GRID_H, stone)
	renderer.bind_sand(sand)
	_load_preset(KEY_F1)

## Tick-boundary dosing: held-mouse water, or soil one subtile per tick.
func _dose() -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var t := _hover_tile()
	if t.x < 0:
		return
	if paint == Paint.WATER:
		water.add_water(t.x, t.y, PAINT_DOSE)
	elif paint == Paint.SOIL:
		_brush_soil(t)

## Advance solids, liquids, then reactions -- the movement systems settle, soak reads settled state, and the reaction tick owns the packet assert.
func _tick_world() -> void:
	sand.tick()
	water.tick()
	reactions.tick()

## Reset the sand engine along with the shared world.
func _clear_world() -> void:
	super()
	sand.clear()

## Held strokes: RMB erases soil, water, and terrain; LMB lays stone over cleared cells.
func _paint_stroke(t: Vector2i) -> bool:
	var i := stone.idx(t.x, t.y)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		stone.packet.set_sub(i, TilePacket.K_SOIL, 0)
		water.set_water(t.x, t.y, 0)
		stone.set_terrain(t.x, t.y, GridStone.Terrain.AIR)
		return true
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and paint == Paint.STONE:
		stone.packet.set_sub(i, TilePacket.K_SOIL, 0)
		water.set_water(t.x, t.y, 0)
		return stone.set_terrain(t.x, t.y, GridStone.Terrain.STONE)
	return false

## Scene keys: F1-F7 presets, 1/2/3 material, K runs the soil suite.
func _handle_key(k: int) -> bool:
	if PRESETS.has(k):
		_load_preset(k)
		return true
	match k:
		KEY_1:
			paint = Paint.STONE
		KEY_2:
			paint = Paint.WATER
		KEY_3:
			paint = Paint.SOIL
		KEY_K:
			run_soil_tests()
		_:
			return false
	return true

## Controls listing for the soil sandbox.
func _hint_header() -> String:
	return "1 stone  2 water  3 soil  LMB paint  RMB erase\nSPC pause  T step  X clear  G debug  K tests  F1-F5, F7, F9-F11 demos (F6/F8 dead)\n"

## Live readout: the base water line plus the hovered tile's soil nibble, damp level, and wet tag.
func _info_line(t: Vector2i) -> String:
	var info := super(t)
	if t.x >= 0:
		var i := stone.idx(t.x, t.y)
		var n: int = stone.packet.get_sub(i, TilePacket.K_SOIL)
		var d: int = stone.packet.get_damp(i)
		info += "   soil %d   damp %d/%d%s" % [n, d, stone.packet.damp_capacity(i), " WET" if stone.packet.has_tag(i, TilePacket.TAG_WET) else ""]
	return info

## Reset both engines and carve the demo bound to a preset key.
func _load_preset(keycode: int) -> void:
	sand.clear()
	water.clear()
	stone.clear()
	_carve_preset(stone, water, PRESETS[keycode])
	paused = false
	renderer.redraw()

## Paint one soil subtile into the lowest empty slot of tile t (brush is a god hand -- no flow stamp).
func _brush_soil(t: Vector2i) -> void:
	var i := stone.idx(t.x, t.y)
	var n: int = stone.packet.get_sub(i, TilePacket.K_SOIL)
	for bit in [GridSand.BL, GridSand.BR, GridSand.TL, GridSand.TR]:
		if (n & bit) == 0:
			stone.packet.set_sub(i, TilePacket.K_SOIL, n | bit)
			return

## Carve one preset-key example and route it through the shared runner.
@warning_ignore("shadowed_variable_base_class")
func _test(name: String, preset_key: int, check: Callable) -> void:
	_run_example(name, PRESETS[preset_key], check, Callable())

## Soil acceptance examples -- repose, corner rule, compaction.
func run_soil_tests() -> void:
	print("== soil self-tests, %d ticks each ==" % TEST_TICKS)
	var check_spread := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var prev := -1
		for c in 6:
			var mask := 5 if (c & 1) == 0 else 10
			var hgt := 0
			for ty in 5:
				hgt += TilePacket.POPCOUNT[pk.get_sub(pk.idx(o.x + (c >> 1), o.y + ty), TilePacket.K_SOIL) & mask]
			if prev >= 0 and absi(hgt - prev) > 1:
				return "columns %d/%d differ by %d" % [c - 1, c, absi(hgt - prev)]
			prev = hgt
		return ""
		
	var check_corner := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.get_sub(pk.idx(o.x + 1, o.y), TilePacket.K_SOIL) != 15:
			return "soil did not hold as a full tile"
		for c in [Vector2i(0, 1), Vector2i(2, 1)]:
			if pk.get_sub(pk.idx(o.x + c.x, o.y + c.y), TilePacket.K_SOIL) != 0:
				return "corner rule failed at %s -- soil tunneled" % c
		return ""
		
	var check_compact := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for ty in 5:
			var want := 0
			if ty == 3:
				want = 3
			elif ty == 4:
				want = 15
			var got := pk.get_sub(pk.idx(o.x, o.y + ty), TilePacket.K_SOIL)
			if got != want:
				return "row %d nibble %d, want %d" % [ty, got, want]
		return ""
		
	var check_sink := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var floor_i := pk.idx(o.x, o.y + 2)
		if pk.get_sub(floor_i, TilePacket.K_SOIL) != 15:
			return "soil did not compact into the floor tile"
		if pk.get_damp(floor_i) != 128:
			return "soil did not saturate (damp %d)" % pk.get_damp(floor_i)
		if not pk.has_tag(floor_i, TilePacket.TAG_WET):
			return "saturated soil is not wet-tagged"
		if pk.get_pool(pk.idx(o.x, o.y + 1), TilePacket.Mat.WATER) != 127:
			return "equilibrium water is %d, want 127" % pk.get_pool(pk.idx(o.x, o.y + 1), TilePacket.Mat.WATER)
		if pk.get_pool(floor_i, TilePacket.Mat.WATER) != 0 or pk.get_sub(pk.idx(o.x, o.y + 1), TilePacket.K_SOIL) != 0:
			return "exchange left matter in the wrong tile"
		if pk.get_pool(pk.idx(o.x, o.y), TilePacket.Mat.WATER) != 0:
			return "water stranded above the exchange"
		return ""

	# failure state dump: five basin rows x two columns, soil/water/damp/tag per tile
	var describe := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var rows := PackedStringArray()
		for ty in 5:
			var line := "     "
			for dx in 2:
				var i := pk.idx(o.x + dx, o.y + ty)
				line += "[soil %2d w %3d d %3d %s]  " % [pk.get_sub(i, TilePacket.K_SOIL), pk.get_pool(i, TilePacket.Mat.WATER), pk.get_damp(i), "WET" if pk.has_tag(i, TilePacket.TAG_WET) else "--"]
			rows.append(line)
		return "\n" + "\n".join(rows)

	var check_basin := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for dx in 2:
			var soil_i := pk.idx(o.x + dx, o.y + 4)
			if pk.get_sub(soil_i, TilePacket.K_SOIL) != 15 or pk.get_damp(soil_i) != 128 or not pk.has_tag(soil_i, TilePacket.TAG_WET):
				return "floor column %d not saturated-wet soil" % dx
			if pk.get_pool(pk.idx(o.x + dx, o.y + 3), TilePacket.Mat.WATER) != 255:
				return "column %d bottom water row is not full" % dx
			if pk.get_pool(pk.idx(o.x + dx, o.y + 2), TilePacket.Mat.WATER) != 127:
				return "column %d top water row is %d, want 127%s" % [dx, pk.get_pool(pk.idx(o.x + dx, o.y + 2), TilePacket.Mat.WATER), describe.call(s)]
			for ty in 2:
				if pk.get_pool(pk.idx(o.x + dx, o.y + ty), TilePacket.Mat.WATER) != 0:
					return "water escaped into the air rows at column %d" % dx
		return ""
		
	var check_skip := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.get_pool(pk.idx(o.x, o.y), TilePacket.Mat.WATER) != 0:
			return "water did not soak away"
		var want := [128, 127, 0]
		var wet := [true, true, false]
		for ty in 3:
			var i := pk.idx(o.x, o.y + 1 + ty)
			if pk.get_damp(i) != want[ty]:
				return "soil row %d damp %d, want %d" % [ty, pk.get_damp(i), want[ty]]
			if pk.has_tag(i, TilePacket.TAG_WET) != wet[ty]:
				return "soil row %d tag mismatch" % ty
		return ""

	var check_sealed := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.get_sub(pk.idx(o.x, o.y + 1), TilePacket.K_SOIL) != 15:
			return "soil left its tile in a sealed column"
		if pk.get_pool(pk.idx(o.x, o.y + 2), TilePacket.Mat.WATER) != 255:
			return "water moved in a sealed column"
		return ""
		
	var setup_wet := func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for ty in 3:
			var i := pk.idx(o.x + 1, o.y + ty)
			pk.add_damp(i, 65)
			pk.set_tag(i, TilePacket.TAG_WET, true)

	var check_mortar := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for ty in 3:
			var i := pk.idx(o.x + 1, o.y + ty)
			if pk.get_sub(i, TilePacket.K_SOIL) != 15:
				return "wet column shed soil at row %d" % ty
			if pk.get_damp(i) != 65:
				return "damp drifted at row %d" % ty
		for dx in [0, 2]:
			for ty in GRID_H:
				if pk.get_sub(pk.idx(o.x + dx, ty), TilePacket.K_SOIL) != 0:
					return "soil escaped the column at %d" % dx
		return ""
		
	var damp_at := func(v: int) -> Callable:
		var inject := func(s: Array) -> void:
			var pk: TilePacket = s[0].packet
			var o: Vector2i = s[2]
			pk.add_damp(pk.idx(o.x, o.y), v)
		return inject

	var check_tag_on := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var i := pk.idx(s[2].x, s[2].y)
		if pk.get_damp(i) != 65:
			return "damp drifted (%d)" % pk.get_damp(i)
		if not pk.has_tag(i, TilePacket.TAG_WET):
			return "tag never gained at 65/128"
		return ""

	var check_tag_off := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var i := pk.idx(s[2].x, s[2].y)
		if pk.has_tag(i, TilePacket.TAG_WET):
			return "tag gained inside the band (40/128)"
		return ""
	
	_test("ST1  column spreads to a staircase", KEY_F1, check_spread)
	_test("ST2  corner rule holds soil on a shelf", KEY_F2, check_corner)
	_test("ST3  half-tiles compact and fall as 3s", KEY_F3, check_compact)
	_test("ST4  soil sinks, saturates, leaves 127", KEY_F4, check_sink)
	_test("ST5  sealed basin soaks to 764 water", KEY_F5, check_basin)
	_test("ST6  sealed column refuses the exchange", KEY_F7, check_sealed)
	_test("ST7  percolation skip fills deep soil", KEY_F9, check_skip)
	_run_example("ST8  wet mortar holds the column", PRESETS[KEY_F10], check_mortar, setup_wet)
	_run_example("ST9  wet tag gains above half capacity", PRESETS[KEY_F11], check_tag_on, damp_at.call(65))
	_run_example("ST10 band damp never gains the tag", PRESETS[KEY_F11], check_tag_off, damp_at.call(40))
	print("== done ==")
