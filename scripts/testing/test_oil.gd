## Oil sandbox — the liquid-variant lab: per-material passes, viscosity throttling,
## and the density sort. 1 stone / 2 water / 3 oil select material, LMB paints,
## RMB erases. K runs the oil acceptance suite headlessly and reports PASS/FAIL.

extends TestSandbox

const PAINT_DOSE := 64    # liquid units added per tick while painting

# F1-F9 oil acceptance diagrams, F6/F8 dead on this rig (rows top-to-bottom): s stone, w water 255, o oil 255, d soil full, . air
const PRESETS := {
	KEY_F1: [
		"w",
		"o",
	],
	KEY_F2: [
		"..o..",
		"..o..",
		"sssss",
	],
	KEY_F3: [
		"..",
		"..",
		"oo",
		"ww",
		"dd",
	],
	KEY_F4: [
		"d",
		"o",
		"o",
	],
	KEY_F5: [
		"...",
		"ws.",
		"ws.",
		"wso",
		"wso",
		"wwo",
	],
	KEY_F7: [
		"w...",
		"oooo",
		"oooo",
	],
	KEY_F9: [
		".ss",
		"ws.",
		"wso",
		"wso",
		"wwo",
	],
	KEY_F10: [
		".....",
		"ws.so",
		"wssso",
		"wwwwo",
	],
}

var sand: GridSand
var reactions: GridReactions

## Build the sand and reaction engines, load the flip demo.
func _setup() -> void:
	sand = GridSand.new(GRID_W, GRID_H, stone, water)
	reactions = GridReactions.new(GRID_W, GRID_H, stone)
	_load_preset(KEY_F1)

## Tick-boundary dosing: held-mouse water or oil, dosed per material.
func _dose() -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var t := _hover_tile()
	if t.x < 0:
		return
	if paint == Paint.WATER:
		water.add_water(t.x, t.y, PAINT_DOSE)
	elif paint == Paint.OIL:
		water.add_liquid(t.x, t.y, TilePacket.Mat.OIL, PAINT_DOSE)

## Advance solids, liquids, then reactions — the engine ruling; reactions own the packet assert.
func _tick_world() -> void:
	sand.tick()
	water.tick()
	reactions.tick()

## Reset the sand engine along with the shared world.
func _clear_world() -> void:
	super()
	sand.clear()
	stone.packet.clear_damp()

## Held strokes: RMB erases soil, liquids, and terrain; LMB lays stone over cleared cells.
func _paint_stroke(t: Vector2i) -> bool:
	var i := stone.idx(t.x, t.y)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		stone.packet.set_sub(i, TilePacket.K_SOIL, 0)
		water.set_water(t.x, t.y, 0)
		stone.packet.set_pool(i, TilePacket.Mat.OIL, 0)
		stone.set_terrain(t.x, t.y, GridStone.Terrain.AIR)
		return true
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and paint == Paint.STONE:
		stone.packet.set_sub(i, TilePacket.K_SOIL, 0)
		water.set_water(t.x, t.y, 0)
		stone.packet.set_pool(i, TilePacket.Mat.OIL, 0)
		return stone.set_terrain(t.x, t.y, GridStone.Terrain.STONE)
	return false

## Scene keys: F1-F4 presets, 1/2/3 material, K runs the oil suite.
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
			paint = Paint.OIL
		KEY_K:
			run_oil_tests()
		_:
			return false
	return true

## Controls listing for the oil sandbox.
func _hint_header() -> String:
	return "1 stone  2 water  3 oil  LMB paint  RMB erase\nSPC pause  T step  X clear  G debug  K tests  F1-F4 demos\n"

## Live readout: the base water line plus the hovered tile's oil, soil, and damp.
func _info_line(t: Vector2i) -> String:
	var info := super(t)
	if t.x >= 0:
		var i := stone.idx(t.x, t.y)
		info += "   oil %d   soil %d   damp %d/%d%s" % [
			stone.packet.get_pool(i, TilePacket.Mat.OIL),
			stone.packet.get_sub(i, TilePacket.K_SOIL),
			stone.packet.get_damp(i), stone.packet.damp_capacity(i),
			" WET" if stone.packet.has_tag(i, TilePacket.TAG_WET) else ""]
	return info

## Reset both engines and carve the demo bound to a preset key.
func _load_preset(keycode: int) -> void:
	sand.clear()
	water.clear()
	stone.clear()
	stone.packet.clear_damp()
	_carve_preset(stone, water, PRESETS[keycode])
	paused = false
	renderer.redraw()

## Oil acceptance examples — sort, drain order, stratification, soil through oil.
func run_oil_tests() -> void:
	print("== oil self-tests, %d ticks each ==" % TEST_TICKS)
	var check_float_oil := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.get_pool(pk.idx(o.x, o.y), TilePacket.Mat.OIL) != 255:
			return "oil did not rise to the top tile"
		if pk.get_pool(pk.idx(o.x, o.y), TilePacket.Mat.WATER) != 0:
			return "water remained in the top tile"
		if pk.get_pool(pk.idx(o.x, o.y + 1), TilePacket.Mat.WATER) != 255:
			return "water did not sink to the bottom"
		if pk.get_pool(pk.idx(o.x, o.y + 1), TilePacket.Mat.OIL) != 0:
			return "oil remained in the bottom tile"
		return ""
		
	var setup_mix := func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var i := pk.idx(o.x, o.y)
		pk.set_pool(i, TilePacket.Mat.WATER, 128)
		pk.add_pool(i, TilePacket.Mat.OIL, 127)

	var check_drain := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var up := pk.idx(o.x, o.y)
		var dn := pk.idx(o.x, o.y + 1)
		if pk.get_pool(up, TilePacket.Mat.WATER) != 0 or pk.get_pool(up, TilePacket.Mat.OIL) != 0:
			return "the upper tile did not drain"
		if pk.get_pool(dn, TilePacket.Mat.WATER) != 128:
			return "lower water is %d, want 128" % pk.get_pool(dn, TilePacket.Mat.WATER)
		if pk.get_pool(dn, TilePacket.Mat.OIL) != 127:
			return "lower oil is %d, want 127" % pk.get_pool(dn, TilePacket.Mat.OIL)
		return ""

	var check_threephase := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for dx in 2:
			var soil_i := pk.idx(o.x + dx, o.y + 4)
			if pk.get_sub(soil_i, TilePacket.K_SOIL) != 15 or pk.get_damp(soil_i) != 128 or not pk.has_tag(soil_i, TilePacket.TAG_WET):
				return "floor column %d not saturated-wet soil" % dx
			var wr := pk.idx(o.x + dx, o.y + 3)
			if pk.get_pool(wr, TilePacket.Mat.WATER) != 127:
				return "column %d water is %d, want 127" % [dx, pk.get_pool(wr, TilePacket.Mat.WATER)]
			if pk.get_pool(wr, TilePacket.Mat.OIL) != 128:
				return "column %d interface oil is %d, want 128" % [dx, pk.get_pool(wr, TilePacket.Mat.OIL)]
			var orow := pk.idx(o.x + dx, o.y + 2)
			if pk.get_pool(orow, TilePacket.Mat.OIL) != 127:
				return "column %d oil row is %d, want 127" % [dx, pk.get_pool(orow, TilePacket.Mat.OIL)]
			if pk.get_pool(orow, TilePacket.Mat.WATER) != 0:
				return "water rose into the oil row at column %d" % dx
			for ty in 2:
				if pk.pool_total(pk.idx(o.x + dx, o.y + ty)) != 0:
					return "liquid escaped into the air rows at column %d" % dx
		return ""

	var check_sink_oil := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.get_sub(pk.idx(o.x, o.y + 2), TilePacket.K_SOIL) != 15:
			return "soil did not compact into the floor tile"
		if pk.get_pool(pk.idx(o.x, o.y + 2), TilePacket.Mat.OIL) != 0:
			return "oil remained in the soil tile"
		if pk.get_damp(pk.idx(o.x, o.y + 2)) != 0:
			return "oil soaked into the soil (it must not)"
		for ty in 2:
			if pk.get_pool(pk.idx(o.x, o.y + ty), TilePacket.Mat.OIL) != 255:
				return "oil row %d is %d, want 255" % [ty, pk.get_pool(pk.idx(o.x, o.y + ty), TilePacket.Mat.OIL)]
		return ""

	var check_manometer := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.get_pool(pk.idx(o.x, o.y + 1), TilePacket.Mat.WATER) != 0:
			return "left surface did not fall below the second row"
		var lw := pk.get_pool(pk.idx(o.x, o.y + 2), TilePacket.Mat.WATER)
		if lw < 112 or lw > 143:
			return "left surface fill %d, want ~128" % lw
		for ty in [3, 4, 5]:
			if pk.get_pool(pk.idx(o.x, o.y + ty), TilePacket.Mat.WATER) != 255:
				return "left leg not full at row %d" % ty
		if pk.get_pool(pk.idx(o.x + 1, o.y + 5), TilePacket.Mat.WATER) != 255:
			return "channel not full of water"
		if pk.get_pool(pk.idx(o.x + 2, o.y + 5), TilePacket.Mat.WATER) != 255:
			return "right leg bottom not water-full"
		var rw := pk.get_pool(pk.idx(o.x + 2, o.y + 4), TilePacket.Mat.WATER)
		if rw < 112 or rw > 143:
			return "right water depth %d, want ~128" % rw
		var io := pk.get_pool(pk.idx(o.x + 2, o.y + 4), TilePacket.Mat.OIL)
		if io < 112 or io > 143:
			return "interface oil %d, want ~128 -- the tile is mixed by design" % io
		for ty in [2, 3]:
			if pk.get_pool(pk.idx(o.x + 2, o.y + ty), TilePacket.Mat.OIL) != 255:
				return "oil column broken at row %d" % ty
			if pk.get_pool(pk.idx(o.x + 2, o.y + ty), TilePacket.Mat.WATER) != 0:
				return "water leaked up the oil column at row %d" % ty
		var to := pk.get_pool(pk.idx(o.x + 2, o.y + 1), TilePacket.Mat.OIL)
		if to < 112 or to > 143:
			return "oil surface row 1 is %d, want ~128" % to
		if pk.get_pool(pk.idx(o.x + 2, o.y + 1), TilePacket.Mat.WATER) != 0:
			return "water leaked above the oil column"
		if pk.pool_total(pk.idx(o.x + 2, o.y)) != 0:
			return "matter rose above the diagram"
		var pl := 0
		for ty in range(1, 6):
			pl += pk.get_pool(pk.idx(o.x, o.y + ty), TilePacket.Mat.WATER) * 30
		var pr := 0
		for ty in range(1, 6):
			pr += pk.get_pool(pk.idx(o.x + 2, o.y + ty), TilePacket.Mat.OIL) * 20
			pr += pk.get_pool(pk.idx(o.x + 2, o.y + ty), TilePacket.Mat.WATER) * 30
		if absi(pl - pr) > 60:
			return "pressure unbalanced at the channel: %d vs %d" % [pl, pr]
		return ""

	var check_spread := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for dx in 4:
			var bottom := pk.idx(o.x + dx, o.y + 2)
			var w := pk.get_pool(bottom, TilePacket.Mat.WATER)
			if w < 56 or w > 72:
				return "bottom water at column %d is %d, want ~64" % [dx, w]
			if pk.pool_total(bottom) != 255:
				return "bottom tile at column %d not full" % dx
			for ty in [0, 1]:
				if pk.get_pool(pk.idx(o.x + dx, o.y + ty), TilePacket.Mat.WATER) != 0:
					return "water above the bottom at column %d row %d" % [dx, ty]
			if pk.get_pool(pk.idx(o.x + dx, o.y + 1), TilePacket.Mat.OIL) != 255:
				return "oil row 1 not full at column %d" % dx
		var top_oil := 0
		for dx in 4:
			top_oil += pk.get_pool(pk.idx(o.x + dx, o.y), TilePacket.Mat.OIL)
		if top_oil < 240 or top_oil > 272:
			return "surface oil %d, want ~256" % top_oil
		return ""

	var check_sealed := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for ty in [1, 2, 3, 4]:
			if pk.get_pool(pk.idx(o.x, o.y + ty), TilePacket.Mat.WATER) != 255:
				return "left leg lost water at row %d" % ty
		if pk.get_pool(pk.idx(o.x + 1, o.y + 4), TilePacket.Mat.WATER) != 255:
			return "channel lost water"
		for ty in [2, 3, 4]:
			if pk.get_pool(pk.idx(o.x + 2, o.y + ty), TilePacket.Mat.OIL) != 255:
				return "right leg oil moved at row %d" % ty
			if pk.get_pool(pk.idx(o.x + 2, o.y + ty), TilePacket.Mat.WATER) != 0:
				return "water entered the sealed leg at row %d" % ty
		if pk.get_pool(pk.idx(o.x + 2, o.y + 1), TilePacket.Mat.WATER) != 0:
			return "the sealed pocket took water"
		return ""
		
	var check_overtop := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var cont := pk.idx(o.x + 2, o.y + 1)
		if pk.get_pool(cont, TilePacket.Mat.WATER) != 0:
			return "water entered the container -- the inversion leak"
		var co := pk.get_pool(cont, TilePacket.Mat.OIL)
		if co < 152 or co > 232:
			return "container oil %d, want ~191" % co
		for ty in [1, 2]:
			var i := pk.idx(o.x + 4, o.y + ty)
			if pk.get_pool(i, TilePacket.Mat.OIL) != 255:
				return "oil column broken at row %d" % ty
			if pk.get_pool(i, TilePacket.Mat.WATER) != 0:
				return "water above the oil at row %d" % ty
		var bw := pk.get_pool(pk.idx(o.x + 4, o.y + 3), TilePacket.Mat.WATER)
		if bw < 160 or bw > 224:
			return "right leg water %d, want ~191" % bw
		if pk.pool_total(pk.idx(o.x + 4, o.y)) > 15:
			return "matter lingering above the wall"
		var lw := pk.get_pool(pk.idx(o.x, o.y + 1), TilePacket.Mat.WATER)
		if lw < 32 or lw > 96:
			return "left surface %d, want ~64" % lw
		if pk.get_pool(pk.idx(o.x, o.y + 2), TilePacket.Mat.WATER) != 255:
			return "left leg not full at row 2"
		var pl4 := 0
		for ty in [1, 2, 3]:
			pl4 += pk.get_pool(pk.idx(o.x, o.y + ty), TilePacket.Mat.WATER) * 30
		var pr4 := 0
		for ty in [1, 2, 3]:
			pr4 += pk.get_pool(pk.idx(o.x + 4, o.y + ty), TilePacket.Mat.OIL) * 20
			pr4 += pk.get_pool(pk.idx(o.x + 4, o.y + ty), TilePacket.Mat.WATER) * 30
		if absi(pl4 - pr4) > 60:
			return "pressure unbalanced at the channel: %d vs %d" % [pl4, pr4]
		return ""

	_run_example("OT1  oil floats on water", PRESETS[KEY_F1], check_float_oil, Callable())
	_run_example("OT2  mixed tile drains and layers", ["w", "."], check_drain, setup_mix)
	_run_example("OT3  three-phase basin stratifies", PRESETS[KEY_F3], check_threephase, Callable())
	_run_example("OT4  soil sinks through oil", PRESETS[KEY_F4], check_sink_oil, Callable())
	_run_example("UT1  the manometer equalizes by pressure", PRESETS[KEY_F5], check_manometer, Callable())
	_run_example("UT2  a corner dump spreads beneath the oil", PRESETS[KEY_F7], check_spread, Callable())
	_run_example("UT3  a sealed chamber refuses the trade", PRESETS[KEY_F9], check_sealed, Callable())
	_run_example("UT4  oil overtops, water never follows", PRESETS[KEY_F10], check_overtop, Callable())
	print("== done ==")
