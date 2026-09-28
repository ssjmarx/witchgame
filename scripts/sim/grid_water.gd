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
const PRESSURE_RATE := 64     # units/tick per square of opening
const PRESSURE_MIN_DIFF := 2  # top-up hysteresis, in donor-material quanta -- the actionable floor is this × density[m]
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

# the sibling modules: the flow export, the gas rules, and the label pass, over this room's packet
var flow: WaterFlow
var gas: WaterGas
var labels: WaterAnalyze
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
			_seek_level_pass(m)
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

## Topmost row of the contiguous visible-material-m segment containing (x, y). Caller guarantees m >= LINE at (x, y); with no visible segment the walk returns y + 1 -- a sentinel row, not a coordinate.
func _segment_top(x: int, y: int, m: int) -> int:
	var t := y
	while t >= 0 and pk.get_pool(idx(x, t), m) >= LINE:
		t -= 1
	return t + 1

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
	var top := _segment_top(sp.x, sp.y, m)
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

## Rule four: try to equalize pressure across each run of liquid tiles (any material — mixtures are one conduit) for material m.
func _seek_level_pass(m: int) -> void:
	for y in range(height - 1, -1, -1):
		var x := 0
		while x < width:
			if pk.pool_total(idx(x, y)) >= LINE:
				var x1 := x
				while x1 + 1 < width and pk.pool_total(idx(x1 + 1, y)) >= LINE:
					x1 += 1
				_seek_level_run(x, x1, y, m)
				x = x1 + 1
			else:
				x += 1

## Level one horizontal run of material m by pressure: heads are density-weighted column integrals from each surface to the run row -- true hydrostatic pressure at the choke. Donors must carry m at the conduit row; every column of the run may receive.
func _seek_level_run(x0: int, x1: int, y: int, m: int) -> void:
	var rho := TilePacket.DENSITY[m]
	var ptops := PackedInt32Array()
	ptops.resize(width)
	ptops.fill(-1)
	var heads := PackedInt32Array()
	heads.resize(width)
	var cols: Array = []
	for x in range(x0, x1 + 1):
		ptops[x] = _pool_top(x, y)
		var h := 0
		for yy in range(ptops[x], y + 1):
			for m2 in TilePacket.MAT_COUNT:
				var v := pk.get_pool(idx(x, yy), m2)
				if v > 0:
					h += v * TilePacket.DENSITY[m2]
		heads[x] = h
		cols.append(x)
	if cols.size() < 2:
		return   # a single-column conduit has no pair to trade
	cols.sort_custom(func(a, b): return heads[a] < heads[b])
	# receivers lowest-pressure first, donors highest first; a failed transfer falls through to the next pair
	for ti in cols.size():
		var t: int = cols[ti]
		for si in range(cols.size() - 1, ti, -1):
			var s: int = cols[si]
			if pk.get_pool(idx(s, y), m) < LINE:
				continue   # donors must carry m at the conduit row
			var diff := heads[s] - heads[t]
			if diff < PRESSURE_MIN_DIFF * rho:
				break   # donors only get shorter from here
			if _transfer_level(s, t, y, diff, ptops, m) > 0:
				return

## Move volume of material m from column s to receiver t so their pressures converge; returns units moved. Capped by half the pressure difference (no overshoot) and viscosity; the deposit lands at m's surface, the pool floor when m sinks, or the pool surface when m floats -- a full entry makes room by displacement: lighter residents yield in place, a pure-m entry thickens at the interface above, and air above an m-surface is the threshold-gated rise.
@warning_ignore("integer_division")
func _transfer_level(s: int, t: int, y: int, diff: int, ptops: PackedInt32Array, m: int) -> int:
	var rho := TilePacket.DENSITY[m]
	var s_top := _segment_top(s, y, m)
	# giving side: the column must be able to recede (air replaces the liquid)
	if s_top > 0 and stone.is_solid(s, s_top - 1):
		# capped by stone, but it may still recede if a side pocket expands into the vacated cells
		var surf := idx(s, s_top)
		var side_air := (s > 0 and not stone.is_solid(s - 1, s_top) and pk.pool_total(surf - 1) <= AIR_PASSABLE_MAX) \
				or (s < width - 1 and not stone.is_solid(s + 1, s_top) and pk.pool_total(surf + 1) <= AIR_PASSABLE_MAX)
		if not side_air:
			return 0
	var avail := 0
	for yy in range(s_top, y + 1):
		avail += pk.get_pool(idx(s, yy), m)
	if avail <= 0:
		return 0
	# the receiver's entry: m's own surface when the column carries m; else the pool floor (m sinks) or the pool surface (m floats)
	var pt: int = ptops[t]
	var pb := _pool_bottom(t, y)
	var entry := idx(t, pt)
	var same_mat := false
	for yy in range(pt, pb + 1):
		if pk.get_pool(idx(t, yy), m) >= LINE:
			entry = idx(t, _segment_top(t, yy, m))
			same_mat = true
			break
	if not same_mat:
		var surf_light := pk.lightest_mat(idx(t, pt))
		if TilePacket.DENSITY[m] > TilePacket.DENSITY[surf_light]:
			entry = idx(t, pb)
		else:
			entry = idx(t, pt)
	# receiving capacity: room at the entry, the gated rise above an m-surface, or displacement
	var target := entry
	var room := pk.pool_free(entry)
	if room <= 0 and same_mat and diff >= TilePacket.POOL_MAX * rho:
		var e_p := _xy_of(entry)
		if e_p.y > 0:
			var above := idx(t, e_p.y - 1)
			if not stone.is_solid(t, e_p.y - 1) and pk.pool_total(above) <= AIR_PASSABLE_MAX \
					and _pocket_vented_for(above, s, s_top):
				var r2 := pk.pool_free(above)
				if r2 > 0:
					target = above
					room = r2
	@warning_ignore("integer_division")
	var want := mini(mini(mini(PRESSURE_RATE, diff / (2 * rho)), avail), TilePacket.VISCOSITY[m])
	if want <= 0:
		return 0
	if target == entry and room <= 0:
		var lm := pk.lightest_mat(entry)
		if lm >= 0 and TilePacket.DENSITY[lm] < rho:
			room += _eject_lightest_up(entry, want - room)
		else:
			var e_y := _xy_of(entry)
			if e_y.y == 0:
				return 0   # no column above to yield
			var iface := entry - width
			if pk.pool_total(iface) < LINE:
				return 0
			var if_room := pk.pool_free(iface)
			room = if_room + _eject_lightest_up(iface, want - if_room)
			target = iface
	var move := mini(want, room)
	if move <= 0:
		return 0
	# remove from the donor's surface, walking down toward the junction; take_pool reports what it got, so the walk cannot over-draw
	var remaining := move
	var yy2 := s_top
	while remaining > 0:
		remaining -= pk.take_pool(idx(s, yy2), m, remaining)
		yy2 += 1
	# deposit at the target (the entry, the interface above it, or one above when the rise fired)
	pk.add_pool(target, m, move)
	if target != entry:
		flow_stamp(target, FlowDir.UP, move)
	else:
		flow_stamp(target, FlowDir.RIGHT if s < t else FlowDir.LEFT, move)
	return move

## Can the air above the receiver's surface give way to this transfer? s and s_top name the donor's own receding headspace.
func _pocket_vented_for(cell: int, s: int, s_top: int) -> bool:
	if labels.escape_at(cell):
		return true
	if s_top > 0:
		var s_above := idx(s, s_top - 1)
		if not stone.is_solid(s, s_top - 1) and pk.pool_total(s_above) <= AIR_PASSABLE_MAX \
				and labels.region_at(s_above) == labels.region_at(cell):
			return true  # the donor's own receding headspace
	return false

## Escape-gated column walk: does some tile above (x, y) have pool headroom with air that reaches open sky? The entry gate for deficit landings; the escape map is the one-tick-stale opinion (_gate's family).
func headroom_above(x: int, y: int) -> bool:
	var yy := y - 1
	while yy >= 0:
		var i := idx(x, yy)
		if TilePacket.FULL_SOLID[pk.get_terrain(i)]:
			return false
		if pk.pool_free(i) > 0 and labels.escape_at(i):
			return true
		yy -= 1
	return false

## Rule five: every over-budget tile ejects its excess up its column -- solids sink, liquid climbs. Lightest material first; leftover excess persists (the entry gate should have prevented it).
func _displacement_pass() -> void:
	for y in range(height - 1, -1, -1):
		for x in width:
			var i := idx(x, y)
			var excess := pk.pool_total(i) - pk.pool_capacity(i)
			if excess > 0:
				_eject_lightest_up(i, excess)

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

## Topmost row of the contiguous visible-liquid segment (any material) containing (x, y). Caller guarantees pool_total >= LINE at (x, y); with no segment the walk returns y + 1 -- a sentinel row, never a coordinate (the _segment_top contract).
func _pool_top(x: int, y: int) -> int:
	var t := y
	while t >= 0 and pk.pool_total(idx(x, t)) >= LINE:
		t -= 1
	return t + 1

## Bottom-most row of the contiguous visible-liquid segment (any material) containing (x, y). Caller guarantees pool_total >= LINE at (x, y); the walk is bounded by the grid.
func _pool_bottom(x: int, y: int) -> int:
	var b := y
	while b + 1 < height and pk.pool_total(idx(x, b + 1)) >= LINE:
		b += 1
	return b

## Eject up to amount units of the lightest materials from tile i up its column, depositing at the first free escape-reachable tiles -- rule five's incompressibility walk, factored: the displacement pass and the lateral deposit share it. Returns units ejected; flow-stamped UP per deposit tile.
func _eject_lightest_up(i: int, amount: int) -> int:
	var remaining := amount
	var p := _xy_of(i)
	var yy := p.y - 1
	while remaining > 0 and yy >= 0:
		var h := idx(p.x, yy)
		if TilePacket.FULL_SOLID[pk.get_terrain(h)]:
			break
		var moved := 0
		if labels.escape_at(h):
			while remaining > 0 and pk.pool_free(h) > 0:
				var m := pk.lightest_mat(i)
				if m < 0:
					break
				var have := pk.get_pool(i, m)
				var room := pk.pool_free(h)
				var chunk := mini(remaining, mini(have, room))
				pk.take_pool(i, m, chunk)
				pk.add_pool(h, m, chunk)
				moved += chunk
				remaining -= chunk
		if moved > 0:
			flow_stamp(h, FlowDir.UP, moved)
		yy -= 1
	return amount - remaining
