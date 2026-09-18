## The water field — a view over the shared TilePacket. One tick, four rules,
## one invariant. GridWater owns the water RULES; the bytes live in pk.
## region labels are one tick stale (deterministic); (c) treats the donor's headspace as freely expandable.

class_name GridWater
extends RefCounted

signal levels_changed(cells)  # Array[Vector2i]: tiles whose broadcast band changed

# coarse broadcast bands for get_level(); fine-grained units stay internal
enum Level { DRY, WET, HALF, FULL }

const LINE := 16              # water units per visible scanline (SACRED)
const AIR_PASSABLE_MAX := 15  # water below one line counts as air for pockets
const PRESSURE_RATE := 64     # units/tick per square of opening
const PRESSURE_MIN_DIFF := 2  # top-up hysteresis (head units; 256 = one cell)
const RISE_MIN_DIFF := 256    # overflow-up needs a full cell of head advantage
const CELL_UNITS := 256       # height units per tile for head math

const W: int = TilePacket.Mat.WATER   # the water code, named once for call sites

# public: grid geometry and bindings
var width: int
var height: int
var stone: GridStone
var pk: TilePacket            # alias of stone.packet — the data lives there

# private: per-tick bookkeeping, rebuilt by _analyze().
# These are OPINION caches, not matter: derived each tick, one tick stale.
var _tick_count := 0           # ticks so far; parity flips the sweep direction
var _region_of: PackedInt32Array
var _regions: Array = []       # per pocket: [{ body_top: { body id -> row } }]
var _escape: PackedByteArray   # per cell: the air here can reach open sky
var _body_of: PackedInt32Array # per cell: connected-water body id, -1 = none
var _next_body_id := 0

## Size the field, bind the packet via the stone facade; everything starts dry.
func _init(w: int, h: int, terrain: GridStone) -> void:
	width = w
	height = h
	stone = terrain
	pk = terrain.packet
	_body_of = PackedInt32Array()
	_body_of.resize(w * h)
	_body_of.fill(-1)
	_region_of = PackedInt32Array()
	_region_of.resize(w * h)
	_region_of.fill(-1)
	_escape = PackedByteArray()
	_escape.resize(w * h)

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

## True if the cell is not solid and holds at most a sub-visible film.
func is_air_passable(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	var i := idx(x, y)
	return not stone.is_solid(x, y) and pk.get_pool(i, W) <= AIR_PASSABLE_MAX

## Air-pocket id at (x, y), or -1 when none or out of bounds.
func get_region_of(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return -1
	return _region_of[y * width + x]

## Debug/renderer helper: true if this cell's air cannot reach open sky.
func is_air_sealed(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	return not _escape[idx(x, y)]

## Total water units in the field — the leak-check checksum.
func total() -> int:
	return pk.mat_total(W)

## Reset the water column and all bookkeeping to a dry, unlabelled state.
func clear() -> void:
	pk.clear_mat(W)
	_body_of.fill(-1)
	_next_body_id = 0
	_region_of.fill(-1)
	_regions.clear()
	_escape.fill(false)

## One simulation tick: relabel, run the four rules, verify volume, verify the ledger, emit band changes.
func tick() -> void:
	_tick_count += 1
	var snap := _levels_snapshot()
	_analyze()
	var checksum := total()
	_cell_pass_all()
	_seek_level_pass()
	# the invariant: a tick may move water, never create or destroy it
	if total() != checksum:
		push_error("GridWater: volume leaked — %d units" % (checksum - total()))
	pk.assert_all()   # the packet ledger rides every tick, load-bearing now
	_emit_level_changes(snap)

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
	var snap := PackedByteArray()
	snap.resize(width * height)
	for i in width * height:
		snap[i] = _band(pk.get_pool(i, W) >> 4)
	return snap

## Emit levels_changed listing every cell whose band changed this tick.
func _emit_level_changes(before: PackedByteArray) -> void:
	var changed: Array = []
	for i in width * height:
		if _band(pk.get_pool(i, W) >> 4) != before[i]:
			changed.append(_xy_of(i))
	if not changed.is_empty():
		levels_changed.emit(changed)

## Rebuild this tick's labels: water bodies, air pockets, escape flags.
func _analyze() -> void:
	_body_of.fill(-1)
	_next_body_id = 0
	_region_of.fill(-1)
	_regions.clear()
	for i in width * height:
		if pk.get_pool(i, W) >= LINE and _body_of[i] == -1:
			_flood_body(i)
	for i in width * height:
		if _is_air_idx(i) and _region_of[i] == -1:
			_flood_region(i)
	_compute_escape()

## Flood-fill one connected-water body, stamping its id as we go.
func _flood_body(start: int) -> void:
	var id := _next_body_id
	_next_body_id += 1
	var stack := PackedInt32Array()
	stack.push_back(start)
	_body_of[start] = id
	while not stack.is_empty():
		var i: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		for n in _neighbors4(i):
			if pk.get_pool(n, W) >= LINE and _body_of[n] == -1:
				_body_of[n] = id
				stack.push_back(n)

## Label one air pocket; record its highest contact per body (a rotation's upper junction).
func _flood_region(start: int) -> void:
	var id := _regions.size()
	var body_top := {}   # body id -> row of its highest cell touching us
	var stack := PackedInt32Array()
	stack.push_back(start)
	_region_of[start] = id
	while not stack.is_empty():
		var i: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		for n in _neighbors4(i):
			if _is_air_idx(n) and _region_of[n] == -1:
				_region_of[n] = id
				stack.push_back(n)
			elif pk.get_pool(n, W) >= LINE:
				var b := _body_of[n]
				if b >= 0:
					var np := _xy_of(n)
					if not body_top.has(b) or np.y < int(body_top[b]):
						body_top[b] = np.y
	_regions.append({ "body_top": body_top })

## Mark every cell whose air can reach open sky; a monotone fixpoint, so order never matters.
func _compute_escape() -> void:
	_escape.fill(false)
	var changed := true
	while changed:
		changed = false
		for y in height:
			for x in width:
				var i := idx(x, y)
				if _escape[i] or stone.is_solid(x, y):
					continue
				var ok := y == 0  # open sky above the map
				if not ok and _escape[i - width]:
					ok = true  # rise through air, or bubble up through water
				if not ok and y > 0 and stone.is_solid(x, y - 1):
					if (x > 0 and _escape[i - 1]) or (x < width - 1 and _escape[i + 1]):
						ok = true  # pinned under a ceiling: slide sideways
				if not ok and pk.get_pool(i, W) <= AIR_PASSABLE_MAX:
					for n in _neighbors4(i):
						if pk.get_pool(n, W) <= AIR_PASSABLE_MAX and _escape[n]:
							ok = true  # air flows through air
							break
				if ok:
					_escape[i] = true
					changed = true

## Orthogonal neighbors of cell i that stay inside the grid.
func _neighbors4(i: int) -> Array:
	var p := _xy_of(i)
	var out: Array = []
	if p.x > 0:
		out.append(i - 1)
	if p.x < width - 1:
		out.append(i + 1)
	if p.y > 0:
		out.append(i - width)
	if p.y < height - 1:
		out.append(i + width)
	return out

## Flat-index form of is_air_passable.
func _is_air_idx(i: int) -> bool:
	var p := _xy_of(i)
	return not stone.is_solid(p.x, p.y) and pk.get_pool(i, W) <= AIR_PASSABLE_MAX

## Tile coordinates of flat index i.
func _xy_of(i: int) -> Vector2i:
	# integer division is intentional
	@warning_ignore("integer_division")
	return Vector2i(i % width, i / width)

## Topmost row of the contiguous visible-water segment containing (x, y).
func _segment_top(x: int, y: int) -> int:
	var t := y
	while t >= 0 and pk.get_pool(idx(x, t), W) >= LINE:
		t -= 1
	return t + 1

## Run _cell_pass over every cell in this tick's sweep order.
func _cell_pass_all() -> void:
	# bottom-up scanline, sweep alternating per tick: columns fall coherently, no lateral bias
	var ltr := (_tick_count % 2 == 0)
	for y in range(height - 1, -1, -1):
		if ltr:
			for x in width:
				_cell_pass(idx(x, y))
		else:
			for x in range(width - 1, -1, -1):
				_cell_pass(idx(x, y))

## Apply the fall / pour / creep rules to one cell, in priority order.
func _cell_pass(i: int) -> void:
	var w := pk.get_pool(i, W)
	if w == 0:
		return
	var p := _xy_of(i)
	var flip := -1 if (_tick_count % 2 == 0) else 1

	# 1) FALL — everything that fits goes straight down
	if p.y + 1 < height:
		var b := i + width
		var free := pk.pool_free(b)
		if not stone.is_solid(p.x, p.y + 1) and free > 0:
			var move := mini(w, free)
			var taken := pk.take_pool(i, W, move)  # take-give: conservation
			pk.add_pool(b, W, taken)               #   by construction
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
			if pk.pool_total(t) < LINE and free > 0 and _gate(t, i):
				var move := mini(w, free)
				var taken := pk.take_pool(i, W, move)
				pk.add_pool(t, W, taken)
				return

	# 3) CREEP — advance into dry space, both sides, half-difference each
	for k in 2:
		var dx := flip if k == 0 else -flip
		var nx := p.x + dx
		if nx < 0 or nx >= width:
			continue
		if stone.is_solid(nx, p.y):
			continue
		var n := idx(nx, p.y)
		var nw := pk.get_pool(n, W)
		if nw < LINE and nw < w - 1 and _gate(n, i):
			var move := (w - nw) >> 1
			var taken := pk.take_pool(i, W, move)
			pk.add_pool(n, W, taken)
			w = pk.get_pool(i, W)  # refresh: side two reads what side one left

## May water from src enter dry cell t? Only if the displaced air has somewhere to go.
func _gate(t: int, src: int) -> bool:
	var region := _region_of[t]
	if region < 0:
		return true
	if pk.get_pool(src, W) < LINE:
		return true  # sub-visible film: same pocket, internal shuffle
	# (a) the displaced air can reach open sky
	if _escape[t]:
		return true
	# (c) the donor's own headspace is this pocket: it recedes as water moves
	var sp := _xy_of(src)
	var top := _segment_top(sp.x, sp.y)
	if top > 0:
		var above := idx(sp.x, top - 1)
		if not stone.is_solid(sp.x, top - 1) and pk.get_pool(above, W) <= AIR_PASSABLE_MAX \
				and _region_of[above] == region:
			return true
	# (d) rotation: pocket and body also touch higher up — air out high, water in low
	var b := _body_of[src]
	if b >= 0:
		var bt: Dictionary = _regions[region].body_top
		if bt.has(b) and int(bt[b]) < sp.y:
			return true
	return false

## Rule four: try to equalize levels across each run of visible water.
func _seek_level_pass() -> void:
	for y in range(height - 1, -1, -1):
		var x := 0
		while x < width:
			if pk.get_pool(idx(x, y), W) >= LINE:
				var x1 := x
				while x1 + 1 < width and pk.get_pool(idx(x1 + 1, y), W) >= LINE:
					x1 += 1
				_seek_level_run(x, x1, y)
				x = x1 + 1
			else:
				x += 1

## Level one horizontal run: move volume from high-head columns to low-head ones.
func _seek_level_run(x0: int, x1: int, y: int) -> void:
	var heads := PackedInt32Array()
	heads.resize(width)
	var tops := PackedInt32Array()
	tops.resize(width)
	tops.fill(-1)
	for x in range(x0, x1 + 1):
		tops[x] = _segment_top(x, y)
		heads[x] = (height - tops[x]) * CELL_UNITS + pk.get_pool(idx(x, tops[x]), W)
	var cols: Array = []
	for x in range(x0, x1 + 1):
		cols.append(x)
	cols.sort_custom(func(a, b): return heads[a] < heads[b])
	# receivers lowest-head first, donors highest-head first — first workable pair wins
	for ti in cols.size():
		var t: int = cols[ti]
		for si in range(cols.size() - 1, ti, -1):
			var s: int = cols[si]
			var diff := heads[s] - heads[t]
			if diff < PRESSURE_MIN_DIFF:
				break
			if _transfer_level(s, t, y, diff, tops) > 0:
				return

## Move volume from column s's surface to t's so their levels converge; returns units moved.
func _transfer_level(s: int, t: int, y: int, diff: int, tops: PackedInt32Array) -> int:
	var t_top: int = tops[t]
	var t_i := idx(t, t_top)
	# receiving capacity: room at the surface, or gated headroom above it
	var room := pk.pool_free(t_i)
	if room <= 0 and diff >= RISE_MIN_DIFF and t_top > 0:
		var above := idx(t, t_top - 1)
		if not stone.is_solid(t, t_top - 1) and pk.get_pool(above, W) <= AIR_PASSABLE_MAX \
				and _pocket_vented_for(above, s, tops):
			room = pk.pool_free(above)
	if room <= 0:
		return 0
	# giving side: the column must be able to recede (air replaces the water)
	var s_top: int = tops[s]
	if s_top > 0 and stone.is_solid(s, s_top - 1):
		# capped by stone, but it may still recede if a side pocket expands into the vacated cells
		var surf := idx(s, s_top)
		var side_air := (s > 0 and not stone.is_solid(s - 1, s_top) and pk.get_pool(surf - 1, W) <= AIR_PASSABLE_MAX) \
				or (s < width - 1 and not stone.is_solid(s + 1, s_top) and pk.get_pool(surf + 1, W) <= AIR_PASSABLE_MAX)
		if not side_air:
			return 0
	var avail := 0
	for yy in range(s_top, y + 1):
		avail += pk.get_pool(idx(s, yy), W)
	var move := mini(mini(PRESSURE_RATE, diff >> 1), mini(room, avail))
	if move <= 0:
		return 0
	# remove from the donor's surface, walking down toward the junction; take_pool reports what it got, so the walk cannot over-draw
	var remaining := move
	var yy2 := s_top
	while remaining > 0:
		remaining -= pk.take_pool(idx(s, yy2), W, remaining)
		yy2 += 1
	# deposit at the receiver's surface (or one above, if it overflowed)
	if pk.pool_free(t_i) > 0:
		pk.add_pool(t_i, W, move)
	else:
		pk.add_pool(idx(t, t_top - 1), W, move)
	return move

## Can the air above the receiver's surface give way to this transfer?
func _pocket_vented_for(cell: int, s: int, tops: PackedInt32Array) -> bool:
	if _escape[cell]:
		return true
	var s_top: int = tops[s]
	if s_top > 0:
		var s_above := idx(s, s_top - 1)
		if not stone.is_solid(s, s_top - 1) and pk.get_pool(s_above, W) <= AIR_PASSABLE_MAX \
				and _region_of[s_above] == _region_of[cell]:
			return true  # the donor's own receding headspace
	return false
