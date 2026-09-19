## Soil sandbox -- GridSand dry-soil rules over the shared packet.
## 1 stone / 2 water / 3 soil select material, LMB paints, RMB erases.
## K runs the soil acceptance suite headlessly and reports PASS/FAIL.

extends TestSandbox

const PAINT_DOSE := 64    # water units added per tick while painting

# F1-F7 soil acceptance diagrams (F6 is dead on this keyboard): s stone, w water 255, d soil full, t soil top-half, . air
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
}

var sand: GridSand

## Build the sand engine and load the spread demo.
func _setup() -> void:
	sand = GridSand.new(GRID_W, GRID_H, stone, water)
	_load_preset(KEY_F7)

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

## Advance solids before liquids -- sand's repack deficits are resolved by water's displacement pass the same tick, and water's tick owns the packet assert.
func _tick_world() -> void:
	sand.tick()
	water.tick()

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
	return "1 stone  2 water  3 soil  LMB paint  RMB erase\nSPC pause  T step  X clear  G debug  K tests  F1-F7 demos\n"

## Live readout: the base water line plus the hovered tile's soil nibble.
func _info_line(t: Vector2i) -> String:
	var info := super(t)
	if t.x >= 0:
		var n: int = stone.packet.get_sub(stone.idx(t.x, t.y), TilePacket.K_SOIL)
		info += "   soil %d" % n
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

## Carve one example fresh, run sand and water to equilibrium, report PASS/FAIL/leak.
@warning_ignore("shadowed_variable_base_class")
func _test(name: String, preset_key: int, check: Callable) -> void:
	var t_stone := GridStone.new(GRID_W, GRID_H)
	var t_water := GridWater.new(GRID_W, GRID_H, t_stone)
	var t_sand := GridSand.new(GRID_W, GRID_H, t_stone, t_water)
	var o := _carve_preset(t_stone, t_water, PRESETS[preset_key])
	var w0 := t_water.total()
	var s0 := t_sand.total(TilePacket.K_SOIL)
	for t in TEST_TICKS:
		t_sand.tick()
		t_water.tick()
	var err: String = check.call([t_stone, t_water, o, t_sand])
	if err == "":
		var pk := t_stone.packet
		for i in GRID_W * GRID_H:
			if pk.pool_total(i) > pk.pool_capacity(i):
				err = "pool over capacity at %s" % pk.xy_of(i)
				break
	if err != "":
		print("FAIL  %s -- %s" % [name, err])
	elif t_water.total() != w0:
		print("FAIL  %s -- water leaked %d units" % [name, w0 - t_water.total()])
	elif t_sand.total(TilePacket.K_SOIL) != s0:
		print("FAIL  %s -- soil mass changed %d -> %d" % [name, s0, t_sand.total(TilePacket.K_SOIL)])
	else:
		print("PASS  %s" % name)

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
		if pk.get_sub(pk.idx(o.x, o.y + 2), TilePacket.K_SOIL) != 15:
			return "soil did not compact into the floor tile"
		if pk.get_pool(pk.idx(o.x, o.y + 2), TilePacket.Mat.WATER) != 0:
			return "water entered the soil tile"
		if pk.get_pool(pk.idx(o.x, o.y + 1), TilePacket.Mat.WATER) != 255:
			return "water did not close in above the sunken soil"
		if pk.get_sub(pk.idx(o.x, o.y + 1), TilePacket.K_SOIL) != 0:
			return "soil stranded mid-column"
		if pk.get_pool(pk.idx(o.x, o.y), TilePacket.Mat.WATER) != 0:
			return "water stranded above the exchange"
		return ""

	var check_basin := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for dx in 2:
			if pk.get_sub(pk.idx(o.x + dx, o.y + 4), TilePacket.K_SOIL) != 15:
				return "soil did not compact at column %d" % dx
			if pk.get_pool(pk.idx(o.x + dx, o.y + 4), TilePacket.Mat.WATER) != 0:
				return "water in the soil tile at column %d" % dx
			for ty in 2:
				if pk.get_pool(pk.idx(o.x + dx, o.y + 2 + ty), TilePacket.Mat.WATER) != 255:
					return "water not brim-full at column %d row %d" % [dx, ty]
			for ty in 2:
				if pk.get_pool(pk.idx(o.x + dx, o.y + ty), TilePacket.Mat.WATER) != 0:
					return "water escaped into the air rows at column %d" % dx
		return ""

	var check_sealed := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.get_sub(pk.idx(o.x, o.y + 1), TilePacket.K_SOIL) != 15:
			return "soil left its tile in a sealed column"
		if pk.get_pool(pk.idx(o.x, o.y + 2), TilePacket.Mat.WATER) != 255:
			return "water moved in a sealed column"
		return ""
	
	_test("ST1  column spreads to a staircase", KEY_F1, check_spread)
	_test("ST2  corner rule holds soil on a shelf", KEY_F2, check_corner)
	_test("ST3  half-tiles compact and fall as 3s", KEY_F3, check_compact)
	_test("ST4  soil sinks through water, settles beneath it", KEY_F4, check_sink)
	_test("ST5  sealed basin exchanges soil for water exactly", KEY_F5, check_basin)
	_test("ST6  sealed column refuses the exchange", KEY_F7, check_sealed)
	print("== done ==")
