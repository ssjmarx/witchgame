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
## follow in column order (stone_s, soil_s, ice_s) == SUB_SINK order; FUEL
## closes the book (appended, never inserted -- row indices are arithmetic).
enum Led { WATER, OIL, ACID, LAVA, SMOKE, STEAM, STONE_S, SOIL_S, ICE_S, DAMP, FUEL }
const LED_COUNT := 11

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

## Per-material viscosity: throughput cap on every flow move (units per tick, per rule application). 255 = unthrottled, water-fast. The cap never changes an equilibrium -- only the pace of arriving -- and never binds for water (pool bytes cap at 255).
const VISCOSITY: Array[int] = [255, 32, 255, 16, 255, 255]   # water oil acid lava smoke steam; <tune>

# -- Rule tables -------------------------------------------------------------

## FULL_SOLID[T] -- full-tile terrain holds no pool (capacity 0).
const FULL_SOLID: Array[bool] = [false, true, true, false, true, true, true, true]

## POPCOUNT[nibble] -- bits set, for subtile mass and capacity math.
const POPCOUNT: Array[int] = [0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4]

const POOL_MAX := 255      # world §13 -- the tile budget
const SUB_DISPLACE := 64   # world §13 -- each solid subtile displaces 64
const NIBBLE_MAX := 15     # 4-bit occupancy

# subtile kinds for get_sub/set_sub -- column order matches SUB_SINK
const K_STONE := 0
const K_SOIL := 1
const K_ICE := 2

const DAMP_PER_SUB := 32   # damp capacity per soil subtile (ruling: 1:1 with water and steam)
const WOOD_DAMP_CAP := 64   # a wood tile holds damp flat -- half a full soil tile (128); render-darkens past half
const TAG_WET := 1        # body-tag bits; poisoned/tainted/holy/fertile arrive with the body-state system

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
var damp := PackedByteArray()
var tags := PackedByteArray()
var fuel := PackedByteArray()    # burnable energy attached to solids -- outside the pool, own ledger row
var fire_s := PackedByteArray()  # fire subtile bits -- overlay state: unbooked, displaces nothing

var _booked := PackedInt64Array()   # ledger: booked totals, one per row
var _present := PackedInt32Array()   # per material: count of tiles holding nonzero units -- the absent-pass gate
var _fire_present := 0   # tiles holding fire bits -- has_fire()'s gate (set_fire keeps it honest)

## Allocate the w×h grid: every column resized, ledger zeroed.
func _init(p_w: int, p_h: int) -> void:
	w = p_w
	h = p_h
	var n := w * h
	# Sixteen boring resizes, no clever loop: a packed array passed through a temporary may not resize the member. Boring is bulletproof.
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
	_present.resize(MAT_COUNT)
	damp.resize(n)
	tags.resize(n)
	fuel.resize(n)
	fire_s.resize(n)
	clear()

## Zero every column and the ledger.
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
	_present.fill(0)
	damp.fill(0)
	tags.fill(0)
	fuel.fill(0)
	fire_s.fill(0)
	_fire_present = 0

# -- Indexing ----------------------------------------------------------------

## Flat-array index of tile (x, y).
func idx(x: int, y: int) -> int:
	return y * w + x

## True if (x, y) lies inside the grid.
func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h

## Tile (x, y) of flat index i.
func xy_of(i: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(i % w, i / w)

# -- Terrain and subtile solids ----------------------------------------------

## Terrain value at tile i.
func get_terrain(i: int) -> int:
	return terrain[i]

## Set terrain at tile i; true when the value changed (GridStone's signal rides on this).
func set_terrain(i: int, t: int) -> bool:
	if terrain[i] == t:
		return false
	terrain[i] = t
	return true   # capacity is derived; nothing else to maintain

## Subtile nibble at tile i; kind: 0 stone_s, 1 soil_s, 2 ice_s (matches SUB_SINK order).
func get_sub(i: int, kind: int) -> int:
	match kind:
		0: return stone_s[i]
		1: return soil_s[i]
		_: return ice_s[i]

## Set a nibble column, book the popcount delta; returns the capacity deficit created (ejecting that overflow is the flow engine's job, world §3).
func set_sub(i: int, kind: int, n: int) -> int:
	n = clampi(n, 0, NIBBLE_MAX)
	var old := get_sub(i, kind)
	if old == n:
		return 0
	match kind:
		0: stone_s[i] = n
		1: soil_s[i] = n
		2: ice_s[i] = n
	_book(Led.STONE_S + kind, POPCOUNT[n] - POPCOUNT[old])
	# post-write: stranded damp drains with booking -- sim paths pre-carry it out, so this only catches tool writes (erase, brush, clear)
	var cap := damp_capacity(i)
	if damp[i] > cap:
		_book(Led.DAMP, cap - damp[i])
		damp[i] = cap
	return maxi(0, pool_total(i) - pool_capacity(i))

# -- Capacity ----------------------------------------------------------------

## Full-solid terrain = 0, otherwise 255 minus 64 per solid subtile (stone + soil + ice).
func pool_capacity(i: int) -> int:
	if FULL_SOLID[terrain[i]]:
		return 0
	var n = POPCOUNT[stone_s[i]] + POPCOUNT[soil_s[i]] + POPCOUNT[ice_s[i]]
	return maxi(0, POOL_MAX - SUB_DISPLACE * n)

# -- The content pool --------------------------------------------------------

## Units of material m held at tile i.
func get_pool(i: int, m: int) -> int:
	match m:
		Mat.WATER: return water[i]
		Mat.OIL: return oil[i]
		Mat.ACID: return acid[i]
		Mat.LAVA: return lava[i]
		Mat.SMOKE: return smoke[i]
		_: return steam[i]

## Units of every material held at tile i.
func pool_total(i: int) -> int:
	return water[i] + oil[i] + acid[i] + lava[i] + smoke[i] + steam[i]

## Headroom left at tile i (capacity minus total).
func pool_free(i: int) -> int:
	return pool_capacity(i) - pool_total(i)

## The ONLY place pool bytes are mutated. Pre-clamped by callers.
func _add_units(i: int, m: int, amount: int) -> void:
	var before := get_pool(i, m)
	match m:
		Mat.WATER: water[i] += amount
		Mat.OIL: oil[i] += amount
		Mat.ACID: acid[i] += amount
		Mat.LAVA: lava[i] += amount
		Mat.SMOKE: smoke[i] += amount
		Mat.STEAM: steam[i] += amount
	var after := before + amount
	if before == 0 and after != 0:
		_present[m] += 1
	elif before != 0 and after == 0:
		_present[m] -= 1

## Add up to amount units of m; returns units accepted (refused units are NOT destroyed -- the caller ejects them by flow rules).
func add_pool(i: int, m: int, amount: int) -> int:
	if amount <= 0:
		return 0
	var accepted := mini(amount, maxi(0, pool_free(i)))
	if accepted > 0:
		_add_units(i, m, accepted)
		_book(m, accepted)
	return accepted

## Remove up to amount units; returns units actually taken.
func take_pool(i: int, m: int, amount: int) -> int:
	if amount <= 0:
		return 0
	var taken := mini(amount, get_pool(i, m))
	if taken > 0:
		_add_units(i, m, -taken)
		_book(m, -taken)
	return taken

## Tool path (paint/erase): force tile i's m toward v; returns spill (units refused). Never destroys other materials or pushes past capacity (over-budget stays until flow ejects).
func set_pool(i: int, m: int, v: int) -> int:
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

## Apply delta to the booked total of one ledger row.
func _book(row: int, delta: int) -> void:
	_booked[row] += delta

## Fresh recount of one pool column.
func mat_total(m: int) -> int:
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

## Fresh popcount recount of one subtile column (kind: K_STONE/K_SOIL/K_ICE) -- the mass checksum.
func sub_total(kind: int) -> int:
	var sum := 0
	match kind:
		K_STONE:
			for v in stone_s: sum += POPCOUNT[v]
		K_SOIL:
			for v in soil_s: sum += POPCOUNT[v]
		_:
			for v in ice_s: sum += POPCOUNT[v]
	return sum

## Double-entry check: booked totals vs fresh recounts, plus the per-tile pool constraint. Called at the end of every tick.
func assert_all() -> bool:
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
	var s_fuel := 0
	for v in fuel: s_fuel += v
	if s_fuel != _booked[Led.FUEL]:
		push_error("ledger drift FUEL: booked %d, counted %d" % [_booked[Led.FUEL], s_fuel])
		ok = false
	for i in w * h:
		# the four subtile cells are a shared budget across solid kinds -- two kinds may never claim one cell; fire bits ride above it, overlay by design
		var overlap := POPCOUNT[stone_s[i]] + POPCOUNT[soil_s[i]] + POPCOUNT[ice_s[i]] - POPCOUNT[stone_s[i] | soil_s[i] | ice_s[i]]
		if overlap != 0:
			var q := xy_of(i)
			push_error("subtile overlap at %d,%d" % [q.x, q.y])
			ok = false
		if pool_total(i) > pool_capacity(i):
			var p := xy_of(i)
			push_error("pool overflow at %d,%d: %d > %d" % [p.x, p.y, pool_total(i), pool_capacity(i)])
			ok = false
		if damp[i] > damp_capacity(i):
			var q2 := xy_of(i)
			push_error("damp over capacity at %d,%d: %d" % [q2.x, q2.y, damp[i]])
			ok = false
	return ok

## Zero the damp and tag columns, booking the removal. (Clear/reset path.)
func clear_damp() -> void:
	_book(Led.DAMP, -damp_total())
	damp.fill(0)
	tags.fill(0)

## Material id of the single lowest-density content at tile i; -1 when the pool is empty.
func lightest_mat(i: int) -> int:
	var best := -1
	var best_d := 9999
	for m in MAT_COUNT:
		if get_pool(i, m) > 0 and DENSITY[m] < best_d:
			best = m
			best_d = DENSITY[m]
	return best

## Remove up to amount units of the single lowest-density material present at tile i; returns units taken.
func drain_lightest(i: int, amount: int) -> int:
	var best := lightest_mat(i)
	if best == -1:
		return 0
	return take_pool(i, best, amount)

## Zero one pool column, booking the removal. (Clear/reset path.)
func clear_mat(m: int) -> void:
	_book(m, -mat_total(m))
	_present[m] = 0
	match m:
		Mat.WATER: water.fill(0)
		Mat.OIL: oil.fill(0)
		Mat.ACID: acid.fill(0)
		Mat.LAVA: lava.fill(0)
		Mat.SMOKE: smoke.fill(0)
		Mat.STEAM: steam.fill(0)

## Damp held by the soil at tile i; outside the content pool (world §2), 32 capacity per soil subtile.
func get_damp(i: int) -> int:
	return damp[i]

## Damp capacity at tile i: 32 per soil subtile; a WOOD tile holds a flat 64 (half a full soil tile); everything else holds none.
func damp_capacity(i: int) -> int:
	if terrain[i] == T.WOOD:
		return WOOD_DAMP_CAP
	return DAMP_PER_SUB * POPCOUNT[soil_s[i]]

## Add up to amount of damp, clamped by capacity; returns units accepted (callers pre-compute, refused units are theirs).
func add_damp(i: int, amount: int) -> int:
	if amount <= 0:
		return 0
	var accepted := mini(amount, damp_capacity(i) - damp[i])
	if accepted > 0:
		damp[i] += accepted
		_book(Led.DAMP, accepted)
	return accepted

## Remove up to amount of damp; returns units actually taken.
func take_damp(i: int, amount: int) -> int:
	if amount <= 0:
		return 0
	var taken := mini(amount, damp[i])
	if taken > 0:
		damp[i] -= taken
		_book(Led.DAMP, -taken)
	return taken

## Transfer damp between tiles, no capacity clamp, no booking (net-zero by construction) -- the subtile carry path. The caller guarantees headroom by live subtile counts (GridSand's carry proof); the end-of-tick assert polices the invariant.
func shift_damp(src: int, dst: int, amount: int) -> void:
	var moved := mini(amount, damp[src])
	damp[src] -= moved
	damp[dst] += moved

## Fresh recount of the damp column -- the soak checksum at 1:1 water-equivalent.
func damp_total() -> int:
	var sum := 0
	for v in damp: sum += v
	return sum

## True when the tag bit is set at tile i.
func has_tag(i: int, bit: int) -> bool:
	return (tags[i] & bit) != 0

## Set or clear one tag bit; tags are field state, never matter -- no booking.
func set_tag(i: int, bit: int, on: bool) -> void:
	if on:
		tags[i] |= bit
	else:
		tags[i] &= 255 - bit

## Sum of every pool material plus damp -- the harness conservation base (subtile matter rides its own ledger rows).
func pool_damp_total() -> int:
	var sum := damp_total()
	for m in MAT_COUNT:
		sum += mat_total(m)
	return sum

## True when any tile holds nonzero units of m -- the absent-material pass gate.
func has_mat(m: int) -> bool:
	return _present[m] > 0

## Booked sum of the six pool rows -- O(1). Sound between asserts because a green assert proves booked == counted; a take-without-add leak still moves the booked total.
func booked_pool_total() -> int:
	var sum := 0
	for m in MAT_COUNT:
		sum += _booked[m]
	return sum

# -- Fuel and fire -----------------------------------------------------------

## Fuel held at tile i (0..255) -- burnable energy attached to solids, outside the content pool.
func get_fuel(i: int) -> int:
	return fuel[i]

## Add up to amount of fuel at tile i, clamped to the 255 ceiling; returns units accepted.
func add_fuel(i: int, amount: int) -> int:
	if amount <= 0:
		return 0
	var accepted := mini(amount, POOL_MAX - fuel[i])
	if accepted > 0:
		fuel[i] += accepted
		_book(Led.FUEL, accepted)
	return accepted

## Remove up to amount of fuel at tile i; returns units actually taken.
func take_fuel(i: int, amount: int) -> int:
	if amount <= 0:
		return 0
	var taken := mini(amount, fuel[i])
	if taken > 0:
		fuel[i] -= taken
		_book(Led.FUEL, -taken)
	return taken

## Tool path (paint/erase): force tile i's fuel toward v, booked; 255 is the only ceiling, so no spill exists.
func set_fuel(i: int, v: int) -> void:
	var target := clampi(v, 0, POOL_MAX)
	var delta := target - fuel[i]
	if delta != 0:
		fuel[i] = target
		_book(Led.FUEL, delta)

## Fresh recount of the fuel column -- row eleven's checksum.
func fuel_total() -> int:
	var sum := 0
	for v in fuel: sum += v
	return sum

## Fire subtile bits at tile i, same nibble layout as the solid kinds; overlay state -- coexists with terrain, solid subtiles, and pool alike.
func get_fire(i: int) -> int:
	return fire_s[i]

## Set the fire nibble at tile i -- god hands and the fire solver both route here, the single writer that keeps has_fire honest; no booking, fire is state not matter.
func set_fire(i: int, n: int) -> void:
	n = clampi(n, 0, NIBBLE_MAX)
	var old := fire_s[i]
	if old == n:
		return
	if old == 0:
		_fire_present += 1
	elif n == 0:
		_fire_present -= 1
	fire_s[i] = n

## True when any tile holds fire bits -- the fire solver's absent-pass gate, _present's pattern.
func has_fire() -> bool:
	return _fire_present > 0

## Zero the fuel column, booking the removal. (Clear/reset path.)
func clear_fuel() -> void:
	_book(Led.FUEL, -fuel_total())
	fuel.fill(0)

## Zero the fire nibbles and the present count. (Clear/reset path — overlay state, nothing booked.)
func clear_fire() -> void:
	fire_s.fill(0)
	_fire_present = 0
