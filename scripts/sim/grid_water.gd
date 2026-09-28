## The liquid engine — a view over the shared TilePacket. Every pool liquid runs the four
## movement rules as its own densest-first pass (viscosity-throttled), then the sort pass
## trades densities; gases rise, spread laterally when blocked, and hop up-diagonal only around corners — exchanging ratios across horizontal faces — and seek level stays a liquid-only rule.

class_name GridWater
extends RefCounted

signal levels_changed(cells)  # Array[Vector2i]: tiles whose broadcast band changed

# coarse broadcast bands for get_level(); fine-grained units stay internal
enum Level { DRY, WET, HALF, FULL }

const LINE := 16              # water units per visible scanline (SACRED)
const AIR_PASSABLE_MAX := 15  # water below one line counts as air for pockets
const DIFFUSER_FLOW := 96    # <tune> — flow_mag above this marks a diffuser (world §13; game-side consumer)

# flow direction codes (8-way); FLOW_DX/FLOW_DY convert a code to tile steps
enum FlowDir { NONE, UP, UP_RIGHT, RIGHT, DOWN_RIGHT, DOWN, DOWN_LEFT, LEFT, UP_LEFT }
const FLOW_DX: Array[int] = [0, 0, 1, 1, 1, 0, -1, -1, -1]
const FLOW_DY: Array[int] = [0, -1, -1, 0, 1, 1, 1, 0, -1]

const W: int = TilePacket.Mat.WATER   # the water code, named once for call sites

const MOVERS: Array[int] = [TilePacket.Mat.LAVA, TilePacket.Mat.ACID, TilePacket.Mat.WATER, TilePacket.Mat.OIL, TilePacket.Mat.SMOKE, TilePacket.Mat.STEAM]   # densest first: the loop order IS the drain order; the gases ride here but run their own rules (WaterGas)

# public: grid geometry and bindings
var width: int
var height: int
var stone: GridStone
var pk: TilePacket            # alias of stone.packet — the data lives there
var tick_count := 0           # ticks so far; parity flips the sweep direction

# the sibling modules: flow export, gas rules, label pass, pool geometry, and the seek machinery, over this room's packet
var flow: WaterFlow
var gas: WaterGas
var labels: WaterAnalyze
var pools: WaterPools
var seek: WaterSeek
var _level_snap := PackedByteArray()   # reused per tick -- the snapshot allocates nothing

## Size the field, bind the packet via the stone facade; everything starts dry.
func _init(w: int, h: int, terrain: GridStone) -> void:
	width = w
	height = h
	stone = terrain
	pk = terrain.packet
	
	flow = WaterFlow.new(w, h)
	gas = WaterGas.new(w, h, terrain, flow)
	labels = WaterAnalyze.new(w, h, terrain)
	pools = WaterPools.new(w, h, terrain, labels, flow)
	seek = WaterSeek.new(w, h, terrain, labels, pools, flow)
	
	_level_snap.resize(w * h)

## Flat-array index of tile (x, y).
func idx(x: int, y: int) -> int:
	return y * width + x

## True if (x, y) lies inside the grid.
func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

## Water units at (x, y), 0..255; out-of-bounds reads as 0.
func get_water(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return pk.get_pool(idx(x, y), W)

## Overwrite the water at (x, y) toward v, clamped 0..255; refuses on full solids by capacity (pool_free = 0); false only when out of bounds.
func set_water(x: int, y: int, v: int) -> bool:
	if not in_bounds(x, y):
		return false
	pk.set_pool(idx(x, y), W, v)
	return true

## Add water units at (x, y); respects tile capacity; false if solid or OOB.
func add_water(x: int, y: int, amount: int) -> bool:
	if not in_bounds(x, y):
		return false
	return pk.add_pool(idx(x, y), W, amount) > 0

## Visible scanlines at (x, y) — water units per LINE.
func get_lines(x: int, y: int) -> int:
	return get_water(x, y) >> 4

## Coarse broadcast band (Level) at (x, y); DRY outside the grid.
func get_level(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return Level.DRY
	return _band(pk.get_pool(idx(x, y), W) >> 4)

## True if the cell is not solid and holds at most a sub-visible film of any liquid.
func is_air_passable(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	var i := idx(x, y)
	return not stone.is_solid(x, y) and pk.pool_total(i) <= AIR_PASSABLE_MAX

## Air-pocket id at (x, y), or -1 when none or out of bounds.
func get_region_of(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return -1
	return labels.region_at(y * width + x)

## Debug/renderer helper: true if this cell's air cannot reach open sky.
func is_air_sealed(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	return not labels.escape_at(idx(x, y))

## Escape-gated headroom walk, delegated to the pool module -- the sand rules' entry gate reads it (the signature stays GridWater's public API).
func headroom_above(x: int, y: int) -> bool:
	return pools.headroom_above(x, y)

## Register matter arriving at tile i (mag units, dir code); magnitudes sum, direction follows the largest single arrival (first stamp wins ties — sweep order is fixed, so deterministic); sim moves stamp inline, room sources like rain stamp at tick head.
func flow_stamp(i: int, dir: int, mag: int) -> void:
	flow.stamp(i, dir, mag)

## Flow strength at (x, y): total units that arrived this tick; 0 outside.
func get_flow_mag(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return flow.mag[idx(x, y)]

## Dominant flow direction at (x, y); NONE outside.
func get_flow_dir(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return FlowDir.NONE
	return flow.dir[idx(x, y)]

## Total water units in the field — the leak-check checksum.
func total() -> int:
	return pk.mat_total(W)

## Reset every pool column, the tick counter, and all bookkeeping to a dry, unlabelled state.
func clear() -> void:
	tick_count = 0   # reloads reproduce: the sweep phase resets with the world
	for m in TilePacket.MAT_COUNT:
		pk.clear_mat(m)
	labels.reset()

## One simulation tick: relabel, eject displacement, run every mover's rules densest-first (liquids fall and seek level, gases rise), stratify densities, verify volume, verify the ledger, emit band changes.
func tick() -> void:
	tick_count += 1
	# tick head: last tick's flow dies before any new move stamps
	flow.reset()
	var snap := _levels_snapshot()
	var checksum := _checksum_all()
	labels.analyze()
	_displacement_pass()
	for m in MOVERS:
		if not pk.has_mat(m):
			continue   # globally absent: its cell pass and seek level are no-ops
		if gas.is_gas(m):
			gas.cell_pass_all(m, tick_count)
		else:
			_cell_pass_all(m)
			seek.pass_all(m)
	gas.exchange_pass(tick_count)
	if _two_mats_present():
		_sort_pass()   # a trade needs two materials; a single-material field has no pair
	if _checksum_all() != checksum:
		push_error("GridWater: volume leaked — %d units" % (checksum - _checksum_all()))
	_emit_level_changes(snap)

## True when at least two materials hold units anywhere -- the sort pass needs a pair to trade.
func _two_mats_present() -> bool:
	var kinds := 0
	for m in TilePacket.MAT_COUNT:
		if pk.has_mat(m):
			kinds += 1
			if kinds > 1:
				return true
	return false

## Map a scanline count to its coarse Level band.
func _band(lines: int) -> int:
	if lines <= 0:
		return Level.DRY
	if lines <= 6:
		return Level.WET
	if lines <= 12:
		return Level.HALF
	return Level.FULL

## Per-cell Level bands from before the tick, for change detection.
func _levels_snapshot() -> PackedByteArray:
	for i in width * height:
		_level_snap[i] = _band(pk.get_pool(i, W) >> 4)
	return _level_snap

## Emit levels_changed listing every cell whose band changed this tick.
func _emit_level_changes(before: PackedByteArray) -> void:
	var changed: Array = []
	for i in width * height:
		if _band(pk.get_pool(i, W) >> 4) != before[i]:
			changed.append(_xy_of(i))
	if not changed.is_empty():
		levels_changed.emit(changed)

## Tile coordinates of flat index i.
func _xy_of(i: int) -> Vector2i:
	# integer division is intentional
	@warning_ignore("integer_division")
	return Vector2i(i % width, i / width)

## Run _cell_pass over every cell in this tick's sweep order.
func _cell_pass_all(m: int) -> void:
	# bottom-up scanline, sweep alternating per tick: columns fall coherently, no lateral bias
	var ltr := (tick_count % 2 == 0)
	for y in range(height - 1, -1, -1):
		if ltr:
			for x in width:
				_cell_pass(idx(x, y), m)
		else:
			for x in range(width - 1, -1, -1):
				_cell_pass(idx(x, y), m)

## Apply the fall / pour / creep rules to one cell for material m, in priority order; every move is capped by m's viscosity.
func _cell_pass(i: int, m: int) -> void:
	var w := pk.get_pool(i, m)
	if w == 0:
		return
	var p := _xy_of(i)
	var flip := -1 if (tick_count % 2 == 0) else 1
	var visc := TilePacket.VISCOSITY[m]

	# 1) FALL — up to the viscosity cap of what fits goes straight down
	if p.y + 1 < height:
		var b := i + width
		var free := pk.pool_free(b)
		if not stone.is_solid(p.x, p.y + 1) and free > 0:
			var move := mini(mini(w, free), visc)
			var taken := pk.take_pool(i, m, move)  # take-give: conservation
			pk.add_pool(b, m, taken)               #   by construction
			flow_stamp(b, FlowDir.DOWN, taken)
			return

	# 2) POUR — over a lip into dry space only (leveling is seek-level's job)
	if p.y + 1 < height:
		for k in 2:
			var dx := flip if k == 0 else -flip
			var tx := p.x + dx
			if tx < 0 or tx >= width:
				continue
			if stone.is_solid(tx, p.y) or stone.is_solid(tx, p.y + 1):
				continue  # no leaking through corners
			var t := idx(tx, p.y + 1)
			var free := pk.pool_free(t)
			if pk.pool_total(t) < LINE and free > 0 and _gate(t, i, m):
				var move := mini(mini(w, free), visc)
				var taken := pk.take_pool(i, m, move)
				pk.add_pool(t, m, taken)
				flow_stamp(t, FlowDir.DOWN_RIGHT if dx > 0 else FlowDir.DOWN_LEFT, taken)
				return

	# 3) CREEP -- advance into dry space, both sides, half-difference capped by the target's free capacity and viscosity
	for k in 2:
		var dx := flip if k == 0 else -flip
		var nx := p.x + dx
		if nx < 0 or nx >= width:
			continue
		if stone.is_solid(nx, p.y):
			continue
		var n := idx(nx, p.y)
		var nw := pk.get_pool(n, m)
		var free := pk.pool_free(n)
		if nw < LINE and free > 0 and nw < w - 1 and _gate(n, i, m):
			var move := mini(mini((w - nw) >> 1, free), visc)
			var taken := pk.take_pool(i, m, move)
			pk.add_pool(n, m, taken)
			flow_stamp(n, FlowDir.RIGHT if dx > 0 else FlowDir.LEFT, taken)
			w = pk.get_pool(i, m)

## May material m from src enter dry cell t? Only if the displaced air has somewhere to go.
func _gate(t: int, src: int, m: int) -> bool:
	var region := labels.region_at(t)
	if region < 0:
		return true
	if pk.get_pool(src, m) < LINE:
		return true  # sub-visible film: same pocket, internal shuffle
	# (a) the displaced air can reach open sky
	if labels.escape_at(t):
		return true
	# (c) the donor's own headspace is this pocket: it recedes as material moves
	var sp := _xy_of(src)
	var top := pools.segment_top(sp.x, sp.y, m)
	if top > 0:
		var above := idx(sp.x, top - 1)
		if not stone.is_solid(sp.x, top - 1) and pk.pool_total(above) <= AIR_PASSABLE_MAX \
				and labels.region_at(above) == region:
			return true
	# (d) rotation: pocket and body also touch higher up — air out high, liquid in low
	var b := labels.body_at(src)
	if b >= 0:
		var bt: Dictionary = labels.body_top(region)
		if bt.has(b) and int(bt[b]) < sp.y:
			return true
	return false

## Rule five: every over-budget tile ejects its excess up its column -- solids sink, liquid climbs. Lightest material first; leftover excess persists (the entry gate should have prevented it).
func _displacement_pass() -> void:
	for y in range(height - 1, -1, -1):
		for x in width:
			var i := idx(x, y)
			var excess := pk.pool_total(i) - pk.pool_capacity(i)
			if excess > 0:
				pools.eject_lightest_up(i, excess)

## The all-material volume checksum -- read from the ledger (booked_pool_total); damp changes only in the reaction tick, which owns its own books. The ledger assert is the catch, not this one.
func _checksum_all() -> int:
	return pk.booked_pool_total()

## Density stratification: vertically adjacent tiles trade -- the densest material in the upper tile sinks, the lightest in the lower rises -- when the upper's is denser. Pair rate = the slower material's SORT_RATE. Top-down scan cascades the dense side; the light side rises into scanned rows -- one tile per tick.
func _sort_pass() -> void:
	var ltr := (tick_count % 2 == 0)
	for y in height - 1:
		if ltr:
			for x in width:
				_sort_pair(idx(x, y))
		else:
			for x in range(width - 1, -1, -1):
				_sort_pair(idx(x, y))
				
## Try one trade across the vertical pair at tile u (upper): densest-above vs lightest-below, swapped when denser-above. One trade per pair per tick -- the pacing knob. Take-both-then-add-both, so a full tile's freed budget always covers the incoming units.
func _sort_pair(u: int) -> void:
	var d := u + width
	var mu := -1
	var mu_d := -1
	for m in TilePacket.MAT_COUNT:
		if pk.get_pool(u, m) > 0 and TilePacket.DENSITY[m] > mu_d:
			mu = m
			mu_d = TilePacket.DENSITY[m]
	if mu < 0:
		return
	var ml := -1
	var ml_d := 999
	for m in TilePacket.MAT_COUNT:
		if pk.get_pool(d, m) > 0 and TilePacket.DENSITY[m] < ml_d:
			ml = m
			ml_d = TilePacket.DENSITY[m]
	if ml < 0:
		return
	if mu_d <= ml_d:
		return   # stacked stable: nothing above is denser than anything below
	var amt := mini(mini(TilePacket.SORT_RATE[mu], TilePacket.SORT_RATE[ml]), mini(pk.get_pool(u, mu), pk.get_pool(d, ml)))
	if amt <= 0:
		return
	pk.take_pool(u, mu, amt)
	pk.take_pool(d, ml, amt)
	pk.add_pool(d, mu, amt)
	pk.add_pool(u, ml, amt)

## Total pool content (all materials) at (x, y); 0 outside the grid.
func get_total(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return pk.pool_total(idx(x, y))

## Add liquid units of material m at (x, y); respects tile capacity; false if solid or OOB.
func add_liquid(x: int, y: int, m: int, amount: int) -> bool:
	if not in_bounds(x, y):
		return false
	return pk.add_pool(idx(x, y), m, amount) > 0
