## Structures lab -- authored matter over the shared packet: fuse, freeze, cut.
## LMB paints stone_s matter, S fuses under the hover, RMB erases (a real cut).
## K runs the structures acceptance suite headlessly and reports PASS/FAIL.

extends TestSandbox

# BK0-BK7 structures diagrams (r stone_s 15, H wood_s 15, d soil 15, . air)
const PRESETS := {
	KEY_F1: [
		".rrr.",
		".....",
		".....",
	],
	KEY_F2: [
		"rrr",
		".....",
		".....",
	],
	KEY_F3: [
		"rrrrr",
		".....",
		".....",
	],
	KEY_F4: [
		"rHrr",
		".....",
		".....",
	],
	KEY_F5: [
		"..r..",
		".....",
		".....",
	],
	KEY_F6: [
		".d.",
		".r.",
		".r.",
	],
	KEY_F8: [
		"HHH",
		"s...",
	],
	KEY_F9: [
		"w.",
		"s.",
		"s.",
	],
	KEY_F10: [
		".....",
		".....",
		".....",
	],
	KEY_F11: [
		".....",
		".....",
		".....",
	],
}

var sand: GridSand

## Bind the sand engine for its structures half, bind the renderer's solid flow, load the beam demo.
func _setup() -> void:
	sand = room.sand
	renderer.bind_sand(sand)
	_load_preset(KEY_F1)

## Held strokes: RMB erases (the shared cut), LMB paints stone_s matter one guarded bit at the hover tile.
func _paint_stroke(t: Vector2i) -> bool:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_erase_tile(t)
		renderer.redraw()
		return true
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var i := stone.idx(t.x, t.y)
		var n: int = stone.packet.get_sub(i, TilePacket.K_STONE)
		for bit in [GridSand.BL, GridSand.BR, GridSand.TL, GridSand.TR]:
			if (n & bit) == 0:
				stone.packet.set_sub(i, TilePacket.K_STONE, n | bit)
				return true
	return false

## Reset the sand engine along with the shared world.
func _clear_world() -> void:
	super()
	sand.clear()

## Scene keys: F1-F6 presets, S fuses the hover tile, K runs the structures suite.
func _handle_key(k: int) -> bool:
	if PRESETS.has(k):
		_load_preset(k)
		return true
	match k:
		KEY_S:
			var t := _hover_tile()
			if t.x >= 0:
				sand.structures.fuse(t.x, t.y)
				renderer.redraw()
			return true
		KEY_K:
			run_suite()
			return true
		_:
			return false

## Reset both engines and carve the demo bound to a preset key.
func _load_preset(keycode: int) -> void:
	sand.clear()
	water.clear()
	stone.clear()
	_carve_preset(stone, water, PRESETS[keycode], sand.structures)
	paused = false
	renderer.redraw()

## Controls listing for the structures sandbox.
func _hint_header() -> String:
	return "LMB stone_s  S fuse  RMB erase (cut)\\nSPC pause  T step  X clear  G debug  K tests  F1-F10 demos\\n"

## Live readout: the base water line plus the hovered tile's stone nibble and membership nibble.
func _info_line(t: Vector2i) -> String:
	var info := super(t)
	if t.x >= 0:
		var i := stone.idx(t.x, t.y)
		info += "   stone %d  struct %d" % [stone.packet.get_sub(i, TilePacket.K_STONE), stone.packet.struct_s[i]]
	return info

## Carve one preset-key example and route it through the shared runner.
@warning_ignore("shadowed_variable_base_class")
func _test(name: String, preset_key: int, check: Callable, setup: Callable = Callable()) -> void:
	_run_example(name, PRESETS[preset_key], check, setup)

## The shared authoring-then-cut setup: fuse the listed tile offsets from the origin, destroy one tile's matter of one kind through the packet, and re-partition -- the tool path, never a sim shortcut.
func fuse_and_cut(s: Array, offs: Array, cut: Vector2i, kind: int) -> void:
	var o: Vector2i = s[2]
	var st: GridStructures = s[3].structures
	for off in offs:
		st.fuse(o.x + off.x, o.y + off.y)
	if cut.x < 0:
		return
	var pk: TilePacket = s[0].packet
	pk.set_sub(pk.idx(o.x + cut.x, o.y + cut.y), kind, 0)
	st.repartition_around(o.x + cut.x, o.y + cut.y)

## The structures lab's conservation: with wood_burns the burn converts matter to smoke at 4:1 (the fire policy's ceiling); without it the shared policy stands.
func drift_report(w0: PackedInt32Array, pk: TilePacket, react: GridReactions = null) -> String:
	if not wood_burns:
		return super(w0, pk, react)
	var burned := react.burned_units if react != null else 0
	var smoke_made := pk.mat_total(TilePacket.Mat.SMOKE) - w0[TilePacket.Mat.SMOKE]
	var parts := PackedStringArray()
	if smoke_made < 0:
		parts.append("smoke vanished %d" % smoke_made)
	elif smoke_made > 4 * burned:
		parts.append("smoke %d over 4x burned %d" % [smoke_made, burned])
	if parts.is_empty():
		return ""
	return " [drift: " + ", ".join(parts) + "]"

## Structures acceptance examples -- authorship freezes, cuts partition.
func run_tests() -> void:
	print("== structures self-tests, %d ticks each ==" % run_ticks)

	var check_held := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for dx in 3:
			var i := pk.idx(o.x + 1 + dx, o.y)
			if pk.get_sub(i, TilePacket.K_STONE) != 15:
				return "beam tile %d shed matter" % dx
			if pk.struct_s[i] != 15:
				return "beam tile %d lost membership" % dx
		return ""

	var check_fell := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for dx in 3:
			var i := pk.idx(o.x + 1 + dx, o.y)
			if pk.get_sub(i, TilePacket.K_STONE) != 0 or pk.struct_s[i] != 0:
				return "unfused beam held at tile %d -- authorship must freeze, not adjacency" % dx
		return ""

	var check_cut_pair := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.get_sub(pk.idx(o.x + 2, o.y), TilePacket.K_STONE) != 0:
			return "the cut tile kept matter"
		for dx in [0, 1, 3, 4]:
			var i := pk.idx(o.x + dx, o.y)
			if pk.get_sub(i, TilePacket.K_STONE) != 15 or pk.struct_s[i] != 15:
				return "piece tile %d did not hold as its own structure" % dx
		return ""

	var check_singleton := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for dx in 3:
			var i := pk.idx(o.x + dx, o.y)
			if pk.get_sub(i, TilePacket.K_STONE) != 0:
				return "chain tile %d did not fall" % dx
			if pk.struct_s[i] != 0:
				return "singleton kept membership at tile %d" % dx
		return ""

	var check_wood_joint := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.get_sub(pk.idx(o.x, o.y), TilePacket.K_STONE) != 0:
			return "the lone stone did not fall"
		if s[3].total(TilePacket.K_WOOD) != 0:
			return "the cut wood survives"
		for dx in [2, 3]:
			var i := pk.idx(o.x + dx, o.y)
			if pk.get_sub(i, TilePacket.K_STONE) != 15 or pk.struct_s[i] != 15:
				return "stone pair tile %d did not hold" % dx
		return ""

	var check_diagonal := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var top := pk.idx(o.x + 2, o.y)
		if pk.get_sub(top, TilePacket.K_STONE) != 0:
			return "diagonal-only cells held -- diagonals must not connect"
		if pk.struct_s[top] != 0:
			return "diagonal-only fuse kept membership"
		var mass := 0
		for ty in range(o.y, o.y + 3):
			mass += TilePacket.POPCOUNT[pk.get_sub(pk.idx(o.x + 2, ty), TilePacket.K_STONE)]
		if mass != 2:
			return "diagonal mass in the column is %d, want 2" % mass
		return ""

	var check_soil_moves := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.get_sub(pk.idx(o.x + 1, o.y), TilePacket.K_SOIL) != 0:
			return "soil froze against the structure -- soil never carries membership"
		for dy in [1, 2]:
			var i := pk.idx(o.x + 1, o.y + dy)
			if pk.get_sub(i, TilePacket.K_STONE) != 15 or pk.struct_s[i] != 15:
				return "structure tile %d did not hold" % dy
		return ""

	var check_burn_cut := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for dx in 3:
			if pk.get_sub(pk.idx(o.x + dx, o.y), TilePacket.K_WOOD) != 0:
				return "beam tile %d did not burn through" % dx
			if pk.struct_s[pk.idx(o.x + dx, o.y)] != 0:
				return "beam tile %d kept membership after the burn dissolved it" % dx
		if s[3].total(TilePacket.K_WOOD) != 0:
			return "burn mass %d, want 0 -- the burn consumed the beam" % s[3].total(TilePacket.K_WOOD)
		return ""

	var check_chip := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var notch := pk.idx(o.x, o.y + 1)
		var w := pk.get_pool(notch, TilePacket.Mat.WATER)
		if w == 0:
			return "the notch stayed dry -- capacity did not open"
		if w > 63:
			return "the notch holds %d, over its 63 capacity" % w
		var below := pk.idx(o.x, o.y + 2)
		if pk.get_sub(below, TilePacket.K_STONE) != 15 or pk.struct_s[below] != 15:
			return "the wall below the notch did not hold"
		return ""

	var row := func(offs: Array, cut: Vector2i, kind: int) -> Callable:
		return func(s: Array) -> void:
			fuse_and_cut(s, offs, cut, kind)

	_test("BK0 a fused beam holds", KEY_F1, check_held, row.call([Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], Vector2i(-9, -9), TilePacket.K_STONE))
	_test("BK1 an unfused beam falls", KEY_F1, check_fell)
	_test("BK2 a cut splits a beam into two structures", KEY_F3, check_cut_pair, row.call([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)], Vector2i(2, 0), TilePacket.K_STONE))
	_test("BK3 a cut leaves singletons loose", KEY_F2, check_singleton, func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		# the end tiles carry one orthogonally-attached cell each, so the cut leaves true single-cell pieces
		pk.set_sub(pk.idx(o.x, o.y), TilePacket.K_STONE, GridSand.BR)
		pk.set_sub(pk.idx(o.x + 2, o.y), TilePacket.K_STONE, GridSand.BL)
		for dx in 3:
			s[3].structures.fuse(o.x + dx, o.y)
		pk.set_sub(pk.idx(o.x + 1, o.y), TilePacket.K_STONE, 0)
		s[3].structures.repartition_around(o.x + 1, o.y))
	_test("BK4 cutting the wood joint splits the mix", KEY_F4, check_wood_joint, func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		# the far tile carries one attached cell, so cutting the joint leaves a true singleton on the left
		pk.set_sub(pk.idx(o.x, o.y), TilePacket.K_STONE, GridSand.BR)
		for dx in 4:
			s[3].structures.fuse(o.x + dx, o.y)
		pk.set_sub(pk.idx(o.x + 1, o.y), TilePacket.K_WOOD, 0)
		s[3].structures.repartition_around(o.x + 1, o.y))
	_test("BK5 diagonals never connect", KEY_F5, check_diagonal, func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		# the diagonal-only nibble: BL | TR -- two cells sharing a corner, never an edge; the tile sits clear of the shell
		pk.set_sub(pk.idx(o.x + 2, o.y), TilePacket.K_STONE, GridSand.BL | GridSand.TR)
		s[3].structures.fuse(o.x + 2, o.y))
	_test("BK6 soil never freezes", KEY_F6, check_soil_moves, row.call([Vector2i(1, 1), Vector2i(1, 2)], Vector2i(-9, -9), TilePacket.K_STONE))
	_example("BK7 restore returns the frozen set", _persistence_check)
	run_ticks = 45   # BK8's window: the full burn -- three tiles at the flat rate, catches staggered by the ignition delay
	wood_burns = true   # the burn consumes kind-2 mass
	drift_watch = false   # the burn creates smoke inside the tick
	_test("BK8 the burn dissolves the structure", KEY_F8, check_burn_cut, func(s: Array) -> void:
		var o: Vector2i = s[2]
		var st: GridStructures = s[3].structures
		for dx in 3:
			st.fuse(o.x + dx, o.y)
		s[4].ignite(o.x, o.y))
	drift_watch = true
	wood_burns = false
	run_ticks = TEST_TICKS
	_test("BK9 a chipped wall admits water", KEY_F9, check_chip, func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		# chip the upper wall tile's top-left cell: capacity 63 where 0 used to be, facing the water above
		pk.set_sub(pk.idx(o.x, o.y + 1), TilePacket.K_STONE, 15 & ~GridSand.TL))
	var setup_smoke_drop := func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		# a 128 smoke column under a wood cell and a stone cell: both must fall through the gas to the floor
		for ty in [1, 2]:
			pk.set_pool(pk.idx(o.x + 2, o.y + ty), TilePacket.Mat.SMOKE, 128)
			pk.set_pool(pk.idx(o.x + 3, o.y + ty), TilePacket.Mat.SMOKE, 128)
		pk.set_sub(pk.idx(o.x + 2, o.y), TilePacket.K_WOOD, 1)
		pk.set_sub(pk.idx(o.x + 3, o.y), TilePacket.K_STONE, 1)
	var check_smoke_drop := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for xoff in [2, 3]:
			var kind := TilePacket.K_WOOD if xoff == 2 else TilePacket.K_STONE
			var top := pk.idx(o.x + xoff, o.y)
			if pk.get_sub(top, kind) != 0:
				return "the %s cell rested on the smoke column -- gas is air to a falling solid" % TilePacket.Mat.keys()[kind].to_lower()
			var land := pk.idx(o.x + xoff, o.y + 2)
			if pk.get_sub(land, kind) != 1:
				return "the %s cell did not land as one cell on the floor" % TilePacket.Mat.keys()[kind].to_lower()
			if pk.struct_s[land] != 0:
				return "the landed cell kept membership"
		return ""

	var check_pin := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		if s[3].total(TilePacket.K_WOOD) != 0:
			return "the burning cell did not burn out where it lay -- wood mass %d remains" % s[3].total(TilePacket.K_WOOD)
		for i in GRID_W * GRID_H:
			if pk.get_fire(i) != 0:
				return "an orphan fire survives at %s -- fire must gutter when its fuel is gone" % pk.xy_of(i)
		return ""
	_test("BK10 wood and stone fall through smoke", KEY_F10, check_smoke_drop, setup_smoke_drop)
	run_ticks = 30   # BK11's window: the ember must burn out in place, never orphan
	wood_burns = true   # the burn consumes kind-2 mass
	drift_watch = false   # the burn creates smoke inside the tick
	_test("BK11 fire pins its fuel", KEY_F11, check_pin, func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		# one loose wood cell mid-air, ignited: it burns out where it lies -- it must not fall and orphan the fire
		pk.set_sub(pk.idx(o.x + 2, o.y), TilePacket.K_WOOD, 1)
		s[4].ignite(o.x + 2, o.y))
	drift_watch = true
	wood_burns = false
	run_ticks = TEST_TICKS
	print("== done ==")

## BK7: membership is census state -- snapshot, cut, restore, and the frozen set returns byte-exact.
func _persistence_check() -> String:
	var r := Room.new(GRID_W, GRID_H, SANDBOX_SEED)
	var pk := r.stone.packet
	var i := pk.idx(7, 7)
	var j := pk.idx(8, 7)
	pk.set_sub(i, TilePacket.K_STONE, 15)
	pk.set_sub(j, TilePacket.K_STONE, 15)
	r.sand.structures.fuse(7, 7)
	r.sand.structures.fuse(8, 7)
	var snap := r.snapshot()
	pk.set_sub(i, TilePacket.K_STONE, 0)
	r.sand.structures.repartition_around(7, 7)
	r.restore(snap)
	if pk.struct_s[i] != 15 or pk.struct_s[j] != 15:
		return "restore lost the membership bits"
	if pk.get_sub(i, TilePacket.K_STONE) != 15:
		return "restore lost the matter"
	for t in 50:
		r.tick()
	if pk.struct_s[i] != 15 or pk.get_sub(i, TilePacket.K_STONE) != 15:
		return "the restored structure did not hold"
	return ""
