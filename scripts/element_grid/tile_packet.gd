## The unified per-tile packet (world.md §2), stored structure-of-arrays:
## one PackedByteArray column per field, one row per tile. The tile index
## is the row number.

class_name TilePacket
extends RefCounted

# -- Enumerations ------------------------------------------------------------

## Terrain moves here; GridStone re-exports the names for compatibility.
enum T { AIR, STONE, WOOD, SOIL, BRAZIER, SPIKE, DOOR, DOOR_CLOSED }

## The content pool (world.md §2). Enum order == density-table order below.
enum Mat { WATER, OIL, ACID, LAVA, SMOKE, STEAM }
const MAT_COUNT := 6

## Ledger rows. The first six line up with Mat; the three subtile rows
## follow in column order (stone_s, soil_s, ice_s) == SUB_SINK order.
enum Led { WATER, OIL, ACID, LAVA, SMOKE, STEAM, STONE_S, SOIL_S, ICE_S }
const LED_COUNT := 9

# -- Tuning tables -----------------------------------------------------------

## Higher density sinks lower. Rest stack top->bottom:
##   STEAM(5) SMOKE(10) OIL(20) WATER(30) ACID(40) LAVA(50)
const DENSITY: Array[int] = [30, 20, 40, 50, 10, 5]

## Units per tick a material sorts toward its rest layer. Ruling:
## steam out-climbs acid's sink 8:1.
const SORT_RATE: Array[int] = [2, 2, 1, 1, 3, 8]          # <tune>

## Loose-subtile buoyancy through liquid, subtile-steps per tick, indexed by
## column order [stone_s, soil_s, ice_s]. Negative = floats (ice floats).
const SUB_SINK: Array[int] = [2, 1, -1]                   # <tune>

# -- Rule tables -------------------------------------------------------------

## FULL_SOLID[T] -- full-tile terrain holds no pool (capacity 0).
const FULL_SOLID: Array[bool] = [false, true, true, false, true, true, true, true]

## POPCOUNT[nibble] -- bits set, for subtile mass and capacity math.
const POPCOUNT: Array[int] = [0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4]

const POOL_MAX := 255      # world §13 -- the tile budget
const SUB_DISPLACE := 64   # world §13 -- each solid subtile displaces 64
const NIBBLE_MAX := 15     # 4-bit occupancy

# -- Columns -----------------------------------------------------------------

var w: int
var h: int

var terrain := PackedByteArray()
var stone_s := PackedByteArray()
var soil_s := PackedByteArray()
var ice_s := PackedByteArray()

var water := PackedByteArray()
var oil := PackedByteArray()
var acid := PackedByteArray()
var lava := PackedByteArray()
var smoke := PackedByteArray()
var steam := PackedByteArray()

var _booked := PackedInt64Array()   # ledger: booked totals, one per row

func _init(p_w: int, p_h: int) -> void:
	w = p_w
	h = p_h
	var n := w * h
	# Ten boring resizes, no clever loop: a packed array passed through a
	# temporary may not resize the member. Boring is bulletproof.
	terrain.resize(n)
	stone_s.resize(n)
	soil_s.resize(n)
	ice_s.resize(n)
	water.resize(n)
	oil.resize(n)
	acid.resize(n)
	lava.resize(n)
	smoke.resize(n)
	steam.resize(n)
	_booked.resize(LED_COUNT)
	clear()

func clear() -> void:
	terrain.fill(T.AIR)
	stone_s.fill(0)
	soil_s.fill(0)
	ice_s.fill(0)
	water.fill(0)
	oil.fill(0)
	acid.fill(0)
	lava.fill(0)
	smoke.fill(0)
	steam.fill(0)
	_booked.fill(0)

# -- Indexing ----------------------------------------------------------------

func idx(x: int, y: int) -> int:
	return y * w + x

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h

func xy_of(i: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(i % w, i / w)

# -- Terrain and subtile solids ----------------------------------------------

func get_terrain(i: int) -> int:
	return terrain[i]

func set_terrain(i: int, t: int) -> bool:
	## True when the value changed (GridStone's signal rides on this).
	if terrain[i] == t:
		return false
	terrain[i] = t
	return true   # capacity is derived; nothing else to maintain

func get_sub(i: int, kind: int) -> int:
	## kind: 0 stone_s, 1 soil_s, 2 ice_s (matches SUB_SINK order).
	match kind:
		0: return stone_s[i]
		1: return soil_s[i]
		_: return ice_s[i]

func set_sub(i: int, kind: int, n: int) -> int:
	## Set a nibble column. Books the popcount delta. Returns the capacity
	## deficit created (pool now over budget) -- ejecting that overflow is
	## the flow engine's job (displacement, world §3); the packet only reports.
	n = clampi(n, 0, NIBBLE_MAX)
	var old := get_sub(i, kind)
	if old == n:
		return 0
	match kind:
		0: stone_s[i] = n
		1: soil_s[i] = n
		2: ice_s[i] = n
	_book(Led.STONE_S + kind, POPCOUNT[n] - POPCOUNT[old])
	return maxi(0, pool_total(i) - pool_capacity(i))

# -- Capacity ----------------------------------------------------------------

func pool_capacity(i: int) -> int:
	## The packet owns capacity: full-solid terrain = 0, otherwise
	## 255 minus 64 per solid subtile (stone + soil + ice).
	if FULL_SOLID[terrain[i]]:
		return 0
	var n = POPCOUNT[stone_s[i]] + POPCOUNT[soil_s[i]] + POPCOUNT[ice_s[i]]
	return maxi(0, POOL_MAX - SUB_DISPLACE * n)

# -- The content pool --------------------------------------------------------

func get_pool(i: int, m: int) -> int:
	match m:
		Mat.WATER: return water[i]
		Mat.OIL: return oil[i]
		Mat.ACID: return acid[i]
		Mat.LAVA: return lava[i]
		Mat.SMOKE: return smoke[i]
		_: return steam[i]

func pool_total(i: int) -> int:
	return water[i] + oil[i] + acid[i] + lava[i] + smoke[i] + steam[i]

func pool_free(i: int) -> int:
	return pool_capacity(i) - pool_total(i)

func _add_units(i: int, m: int, amount: int) -> void:
	## The ONLY place pool bytes are mutated. Pre-clamped by callers.
	match m:
		Mat.WATER: water[i] += amount
		Mat.OIL: oil[i] += amount
		Mat.ACID: acid[i] += amount
		Mat.LAVA: lava[i] += amount
		Mat.SMOKE: smoke[i] += amount
		Mat.STEAM: steam[i] += amount

func add_pool(i: int, m: int, amount: int) -> int:
	## Add up to `amount` units of m; returns units accepted. Refused units
	## are NOT destroyed -- the caller ejects them by flow rules.
	if amount <= 0:
		return 0
	var accepted := mini(amount, maxi(0, pool_free(i)))
	if accepted > 0:
		_add_units(i, m, accepted)
		_book(m, accepted)
	return accepted

func take_pool(i: int, m: int, amount: int) -> int:
	## Remove up to `amount` units; returns units actually taken.
	if amount <= 0:
		return 0
	var taken := mini(amount, get_pool(i, m))
	if taken > 0:
		_add_units(i, m, -taken)
		_book(m, -taken)
	return taken

func set_pool(i: int, m: int, v: int) -> int:
	## Tool path (paint/erase): force tile i's m toward v. Returns spill --
	## units of v refused. Never destroys other materials; never pushes the
	## tile over capacity (an over-budget tile stays until flow ejects).
	var c := get_pool(i, m)
	var target := clampi(v, 0, POOL_MAX)
	var accepted := target
	if target > c:
		accepted = c + mini(target - c, maxi(0, pool_free(i)))
	var delta := accepted - c
	if delta != 0:
		_add_units(i, m, delta)
		_book(m, delta)
	return target - accepted

# -- The ledger ---------------------------------------------------------------

func _book(row: int, delta: int) -> void:
	_booked[row] += delta

func mat_total(m: int) -> int:
	## Fresh recount of one pool column.
	var sum := 0
	match m:
		Mat.WATER:
			for v in water: sum += v
		Mat.OIL:
			for v in oil: sum += v
		Mat.ACID:
			for v in acid: sum += v
		Mat.LAVA:
			for v in lava: sum += v
		Mat.SMOKE:
			for v in smoke: sum += v
		Mat.STEAM:
			for v in steam: sum += v
	return sum

func assert_all() -> bool:
	## Double-entry check: booked totals vs fresh recounts, plus the
	## per-tile pool constraint. Called at the end of every tick.
	var ok := true
	for m in MAT_COUNT:
		var counted := mat_total(m)
		if counted != _booked[m]:
			push_error("ledger drift row %d: booked %d, counted %d" % [m, _booked[m], counted])
			ok = false
	var s_stone := 0
	for v in stone_s: s_stone += POPCOUNT[v]
	var s_soil := 0
	for v in soil_s: s_soil += POPCOUNT[v]
	var s_ice := 0
	for v in ice_s: s_ice += POPCOUNT[v]
	if s_stone != _booked[Led.STONE_S]:
		push_error("ledger drift STONE_S: booked %d, counted %d" % [_booked[Led.STONE_S], s_stone])
		ok = false
	if s_soil != _booked[Led.SOIL_S]:
		push_error("ledger drift SOIL_S: booked %d, counted %d" % [_booked[Led.SOIL_S], s_soil])
		ok = false
	if s_ice != _booked[Led.ICE_S]:
		push_error("ledger drift ICE_S: booked %d, counted %d" % [_booked[Led.ICE_S], s_ice])
		ok = false
	for i in w * h:
		if pool_total(i) > pool_capacity(i):
			var p := xy_of(i)
			push_error("pool overflow at %d,%d: %d > %d" % [p.x, p.y, pool_total(i), pool_capacity(i)])
			ok = false
	return ok

## remove up to amount units of single lowest density mat at tile i, return units taken
func drain_lightest(i: int, amount: int) -> int:
	## Remove up to `amount` units of the single lowest-density material
	## present at tile i. Returns units taken.
	var best := -1
	var best_d := 9999
	for m in MAT_COUNT:
		if get_pool(i, m) > 0 and DENSITY[m] < best_d:
			best = m
			best_d = DENSITY[m]
	if best == -1:
		return 0
	return take_pool(i, best, amount)

## Zero one pool column, booking the removal. (Clear/reset path.)
func clear_mat(m: int) -> void:
	_book(m, -mat_total(m))
	match m:
		Mat.WATER: water.fill(0)
		Mat.OIL: oil.fill(0)
		Mat.ACID: acid.fill(0)
		Mat.LAVA: lava.fill(0)
		Mat.SMOKE: smoke.fill(0)
		Mat.STEAM: steam.fill(0)
