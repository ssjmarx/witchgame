## Occlusion lab -- directional solidity on the tile pool: sealed edges, sealed
## interiors, pinched corners. Every preset carves a walled basin whose stone
## floors reduce to partial patterns in the setup; K runs the acceptance suite.

extends TestSandbox

# basin diagrams (s stone_s 15 pre-fused -- the setups reduce the floor rows; w water 255)
const PRESETS := {
	KEY_F1: [
		".....",
		".....",
		"sssss",
		".....",
	],
	KEY_F2: [
		".....",
		".....",
		"sssss",
		".....",
	],
	KEY_F3: [
		".....",
		".....",
		"sssss",
		".....",
	],
	KEY_F4: [
		".....",
		".....",
		"sssss",
		"sssss",
	],
	KEY_F5: [
		"..sws",
		"..sws",
		"..sws",
		"sssss",
	],
	KEY_F6: [
		"ws...",
		"s....",
		"sssss",
	],
	KEY_F7: [
		".....",
		".....",
		"sssss",
		".....",
	],
	KEY_F8: [
		"sww",
		".sw",
		".ss",
	],
	KEY_F9: [
		"ws.s",
		"ws.s",
		"ssss",
	],
	KEY_F10: [
		"wssw",
		"wssw",
		"ssss",
	],
	KEY_F11: [
		"ws..",
		"s...",
		"....",
		"....",
	],
}

var sand: GridSand
var react: GridReactions

## Bind the sand engine for its structures half, bind the renderer's solid flow, load the funnel demo.
func _setup() -> void:
	sand = room.sand
	react = room.react
	renderer.bind_sand(sand)
	_load_preset(KEY_F1)

## Reset the sand engine along with the shared world.
func _clear_world() -> void:
	super()
	sand.clear()

## Scene keys: F1-F7 presets, K runs the occlusion suite.
func _handle_key(k: int) -> bool:
	if PRESETS.has(k):
		_load_preset(k)
		return true
	match k:
		KEY_K:
			run_suite()
			return true
		_:
			return false

## Reset both engines and carve the demo bound to a preset key.
func _load_preset(keycode: int) -> void:
	sand.clear()
	stone.clear()
	water.clear()
	react.clear()
	stone.packet.clear_damp()
	stone.packet.clear_fire()
	_carve_preset(stone, water, PRESETS[keycode], sand.structures)
	paused = false
	renderer.redraw()

## Controls listing for the occlusion sandbox.
func _hint_header() -> String:
	return "LMB water  RMB erase\\nSPC pause  T step  X clear  G debug  K tests  F1-F11 demos\\n"

## Reduce one floor row of the F1-family basin to a partial pattern: replace the fused 4/4 stone with bits, the membership invariant clearing the vacated cells (the survivors stay frozen).
func _reduce_row(s: Array, row: int, bits: int) -> void:
	var pk: TilePacket = s[0].packet
	var o: Vector2i = s[2]
	for dx in 5:
		pk.set_sub(pk.idx(o.x + dx, o.y + row), TilePacket.K_STONE, bits)

## Dose the basin's top row with per units of water per tile.
func _dose_top(s: Array, per: int) -> void:
	var pk: TilePacket = s[0].packet
	var o: Vector2i = s[2]
	for dx in 5:
		pk.set_pool(pk.idx(o.x + dx, o.y), TilePacket.Mat.WATER, per)

## Total water held by one row of the basin, across the five interior columns.
func _row_water(s: Array, row: int) -> int:
	var pk: TilePacket = s[0].packet
	var o: Vector2i = s[2]
	var sum := 0
	for dx in 5:
		sum += pk.get_pool(pk.idx(o.x + dx, o.y + row), TilePacket.Mat.WATER)
	return sum

## Water at one basin tile, interior coordinates.
func _tile_water(s: Array, dx: int, row: int) -> int:
	var pk: TilePacket = s[0].packet
	var o: Vector2i = s[2]
	return pk.get_pool(pk.idx(o.x + dx, o.y + row), TilePacket.Mat.WATER)

## The occlusion acceptance suite: funnels, holds, seals, saturations, pinches (world §3).
func run_tests() -> void:
	var check_funnel := func(s: Array) -> String:
		if _row_water.call(s, 2) != 0:
			return "the one-cell floor holds water -- the open column must funnel"
		for dx in 5:
			if _tile_water.call(s, dx, 3) != 200:
				return "basin tile %d holds %d, want 200 -- the water did not pass through" % [dx, _tile_water.call(s, dx, 3)]
		return ""

	var check_toprow := func(s: Array) -> String:
		if _row_water.call(s, 2) != 0 or _row_water.call(s, 3) != 0:
			return "water crossed the top-row floor"
		if _row_water.call(s, 0) + _row_water.call(s, 1) != 1000:
			return "the pool above the floor lost water"
		return ""

	var check_diag := func(s: Array) -> String:
		if _row_water.call(s, 3) != 0:
			return "water crossed the diagonal-pair floor"
		for dx in 5:
			if _tile_water.call(s, dx, 2) != 127:
				return "diagonal tile %d holds %d, want 127 -- it must absorb to capacity and stop" % [dx, _tile_water.call(s, dx, 2)]
		return ""

	var check_stack := func(s: Array) -> String:
		if _row_water.call(s, 3) != 0:
			return "water crossed the stacked diagonal -- the near-side union must seal the edge"
		for dx in 5:
			if _tile_water.call(s, dx, 2) != 191:
				return "upper tile %d holds %d, want 191 -- it must absorb to capacity and stop" % [dx, _tile_water.call(s, dx, 2)]
		return ""

	var check_dam := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for row in 3:
			if pk.get_pool(pk.idx(o.x + 1, o.y + row), TilePacket.Mat.WATER) != 0:
				return "the dry column took water at row %d -- the dam leaked through" % row
		for row in [1, 2]:
			if pk.get_pool(pk.idx(o.x + 2, o.y + row), TilePacket.Mat.WATER) != 127:
				return "dam tile row %d holds %d, want 127 -- it must saturate from its open face" % [row, pk.get_pool(pk.idx(o.x + 2, o.y + row), TilePacket.Mat.WATER)]
		if pk.get_pool(pk.idx(o.x + 2, o.y), TilePacket.Mat.WATER) == 0:
			return "the top dam tile never took water from its open face"
		return ""

	var check_pinch := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.pool_total(pk.idx(o.x + 1, o.y + 1)) != 0:
			return "the pinched corner leaked into the diagonal target"
		if pk.get_pool(pk.idx(o.x, o.y + 1), TilePacket.Mat.WATER) != 127:
			return "the full pillar below lost water"
		if pk.get_pool(pk.idx(o.x, o.y), TilePacket.Mat.WATER) == 0:
			return "the water column drained somewhere it should not have"
		return ""

	var check_column := func(s: Array) -> String:
		if _row_water.call(s, 2) != 0:
			return "the cleared-column floor holds water -- the open half must funnel"
		for dx in 5:
			if _tile_water.call(s, dx, 3) != 200:
				return "basin tile %d holds %d, want 200 -- the water did not pass through" % [dx, _tile_water.call(s, dx, 3)]
		return ""

	var check_tub := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var left := 0
		var right := 0
		for row in 2:
			left += pk.get_pool(pk.idx(o.x, o.y + row), TilePacket.Mat.WATER)
			right += pk.get_pool(pk.idx(o.x + 1, o.y + row), TilePacket.Mat.WATER)
			right += pk.get_pool(pk.idx(o.x + 2, o.y + row), TilePacket.Mat.WATER)
		if left != 510:
			return "the left side drifted to %d -- the tub leveled through the wall" % left
		if right != 256:
			return "the right side drifted to %d -- the tub leveled through the wall" % right
		return ""

	var check_cross_wall := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var left := 0
		var right := 0
		for row in 2:
			left += pk.get_pool(pk.idx(o.x, o.y + row), TilePacket.Mat.WATER)
			left += pk.get_pool(pk.idx(o.x + 1, o.y + row), TilePacket.Mat.WATER)
			right += pk.get_pool(pk.idx(o.x + 2, o.y + row), TilePacket.Mat.WATER)
			right += pk.get_pool(pk.idx(o.x + 3, o.y + row), TilePacket.Mat.WATER)
		if left != 510:
			return "the left side drifted to %d -- the tub leveled through the cross-boundary wall" % left
		if right != 256:
			return "the right side drifted to %d -- the tub leveled through the cross-boundary wall" % right
		return ""

	var check_pinched_tub := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var left := 0
		var right := 0
		for row in 2:
			left += pk.get_pool(pk.idx(o.x, o.y + row), TilePacket.Mat.WATER)
			right += pk.get_pool(pk.idx(o.x + 2, o.y + row), TilePacket.Mat.WATER)
		if absi(left - right) <= 100:
			return "columns converged to %d vs %d -- the tub leveled through the pinched wall" % [left, right]
		return ""

	var check_pinch_interior := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.pool_total(pk.idx(o.x, o.y + 2)) != 0:
			return "the pinched tile poured across its own interior into the pocket"
		if pk.get_pool(pk.idx(o.x, o.y + 1), TilePacket.Mat.WATER) != 0:
			return "the dry side column took water"
		if pk.get_pool(pk.idx(o.x + 1, o.y + 1), TilePacket.Mat.WATER) != 127:
			return "the diagonal tile holds %d, want 127 -- it must saturate from its top and right and hold" % pk.get_pool(pk.idx(o.x + 1, o.y + 1), TilePacket.Mat.WATER)
		return ""

	_run_example("OC0 a one-cell floor funnels through its open column", PRESETS[KEY_F1], check_funnel, func(s: Array) -> void:
		_reduce_row.call(s, 2, GridSand.BL)
		_dose_top.call(s, 200))
	_run_example("OC1 a top-row floor holds", PRESETS[KEY_F2], check_toprow, func(s: Array) -> void:
		_reduce_row.call(s, 2, GridSand.TL | GridSand.TR)
		_dose_top.call(s, 200))
	_run_example("OC2 diagonal pairs hold -- the zigzag", PRESETS[KEY_F3], check_diag, func(s: Array) -> void:
		_reduce_row.call(s, 2, GridSand.TL | GridSand.BR)
		_dose_top.call(s, 200))
	_run_example("OC3 a stacked diagonal seals the edge", PRESETS[KEY_F4], check_stack, func(s: Array) -> void:
		_reduce_row.call(s, 2, GridSand.BL)
		_reduce_row.call(s, 3, GridSand.TR)
		_dose_top.call(s, 200))
	_run_example("OC4 a left-column dam saturates from its open face", PRESETS[KEY_F5], check_dam, func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for row in 3:
			pk.set_sub(pk.idx(o.x + 2, o.y + row), TilePacket.K_STONE, GridSand.TL | GridSand.BL))
	_run_example("OC5 a pinched corner refuses the pour", PRESETS[KEY_F6], check_pinch, func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		pk.set_sub(pk.idx(o.x + 1, o.y), TilePacket.K_STONE, GridSand.TL | GridSand.BL)
		pk.set_sub(pk.idx(o.x, o.y + 1), TilePacket.K_STONE, GridSand.TR | GridSand.BR)
		pk.set_pool(pk.idx(o.x, o.y + 1), TilePacket.Mat.WATER, 127))
	_run_example("OC6 a cleared column funnels through its open half", PRESETS[KEY_F7], check_column, func(s: Array) -> void:
		_reduce_row.call(s, 2, GridSand.TL | GridSand.BL)
		_dose_top.call(s, 200))
	_run_example("OC7 a pinched interior never pours", PRESETS[KEY_F8], check_pinch_interior, func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		pk.set_sub(pk.idx(o.x + 1, o.y + 1), TilePacket.K_STONE, GridSand.TL | GridSand.BR))
	_run_example("OC8 a full-height one-subtile wall never levels the tub", PRESETS[KEY_F9], check_tub, func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for row in 2:
			pk.set_sub(pk.idx(o.x + 1, o.y + row), TilePacket.K_STONE, GridSand.TL | GridSand.BL)
			pk.set_pool(pk.idx(o.x + 2, o.y + row), TilePacket.Mat.WATER, 128))
	_run_example("OC9 a cross-boundary wall never levels the tub", PRESETS[KEY_F10], check_cross_wall, func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for row in 2:
			pk.set_sub(pk.idx(o.x + 1, o.y + row), TilePacket.K_STONE, GridSand.TR)
			pk.set_sub(pk.idx(o.x + 2, o.y + row), TilePacket.K_STONE, GridSand.BL)
			pk.set_pool(pk.idx(o.x + 3, o.y + row), TilePacket.Mat.WATER, 128))
	_run_example("OC10 a pinched wall never levels the tub", PRESETS[KEY_F9], check_pinched_tub, func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for row in 2:
			pk.set_sub(pk.idx(o.x + 1, o.y + row), TilePacket.K_STONE, GridSand.TL | GridSand.BR)
			pk.set_pool(pk.idx(o.x + 2, o.y + row), TilePacket.Mat.WATER, 128))

	var check_notch_drain := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var below := 0
		for row in 2:
			for dx in 4:
				below += pk.get_pool(pk.idx(o.x + dx, o.y + 2 + row), TilePacket.Mat.WATER)
		if below < 200:
			return "the pool stayed above -- only %d of 255 reached the floor" % below
		return ""

	_run_example("OC14 a lone notch beside water drains through", PRESETS[KEY_F11], check_notch_drain, func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		pk.set_sub(pk.idx(o.x + 1, o.y), TilePacket.K_STONE, GridSand.TL | GridSand.TR | GridSand.BR)
		pk.set_pool(pk.idx(o.x, o.y), TilePacket.Mat.WATER, 255))
	_run_example("OC15 the boundary-gap control drains the same", PRESETS[KEY_F11], check_notch_drain, func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		pk.set_sub(pk.idx(o.x + 1, o.y), TilePacket.K_STONE, GridSand.TR)
		pk.set_pool(pk.idx(o.x, o.y), TilePacket.Mat.WATER, 255))
