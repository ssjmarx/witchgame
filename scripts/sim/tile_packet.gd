## The unified per-tile packet (world.md §2), stored structure-of-arrays:
## one PackedByteArray column per field, one row per tile. The tile index
## is the row number.

class_name TilePacket
extends RefCounted

# -- Enumerations ------------------------------------------------------------

## Terrain moves here; GridStone re-exports the names for compatibility. AIR plus the
## fixtures only since the retirement cut -- STONE, WOOD, and SOIL terrain became matter.
enum T { AIR, BRAZIER, SPIKE, DOOR, DOOR_CLOSED }

## The content pool (world.md §2). Enum order == density-table order below.
enum Mat { WATER, OIL, ACID, LAVA, SMOKE, STEAM }
const MAT_COUNT := 6

## Ledger rows. The first six line up with Mat; the three subtile rows
## follow in column order (stone_s, soil_s, wood_s) == SUB_SINK order. FUEL
## retired at the cut -- the burn pool rides the reaction overlay (world §3).
enum Led { WATER, OIL, ACID, LAVA, SMOKE, STEAM, STONE_S, SOIL_S, WOOD_S, DAMP }
const LED_COUNT := 10

## Debug furniture (the editor lab, world.md §3): sources and sinks as room markers -- live during play, authored outside the play area in finished rooms.
enum DebugTile { NONE, WATER_SOURCE, DRAIN, STEAM_VENT, OPEN_AIR }

# -- Tuning tables -----------------------------------------------------------

## Higher density sinks lower. Rest stack top->bottom:
##   STEAM(5) SMOKE(10) OIL(20) WATER(30) ACID(40) LAVA(50)
const DENSITY: Array[int] = [30, 20, 40, 50, 10, 5]

## Units per tick a material sorts toward its rest layer. Ruling:
## steam out-climbs acid's sink 8:1.
const SORT_RATE: Array[int] = [2, 2, 1, 1, 3, 8]          # <tune>

## Sink rate through LIQUID for each subtile kind, subtile-steps per tick, column order
## [stone_s, soil_s, wood_s]. The rest/fall decision reads SUB_DENSITY against DENSITY --
## a solid rests in any pool material denser than itself (world §3); this table is the rate once sinking.
const SUB_SINK: Array[int] = [2, 1, -1]                   # <tune> — wood's entry documents the floater; the decision is density, not this row

## Subtile-kind densities on the DENSITY scale -- the medium rule (world §3): a solid rests in
## any pool material denser than itself and falls through the lighter, gas included. Stone and
## soil sink through everything; wood floats on every liquid and falls through both gases.
const SUB_DENSITY: Array[int] = [60, 55, 15]              # stone_s, soil_s, wood_s -- <tune>

## Per-material viscosity: throughput cap on every flow move (units per tick, per rule application). 255 = unthrottled, water-fast. The cap never changes an equilibrium -- only the pace of arriving -- and never binds for water (pool bytes cap at 255).
const VISCOSITY: Array[int] = [255, 32, 255, 16, 255, 255]   # water oil acid lava smoke steam; <tune>

# -- Rule tables -------------------------------------------------------------

## FULL_SOLID[T] -- fixture terrain (braziers, spikes, doors) holds no pool and blocks everything; matter walls read the same through solid_capacity.
const FULL_SOLID: Array[bool] = [false, true, true, true, true]

## POPCOUNT[nibble] -- bits set, for subtile mass and capacity math.
const POPCOUNT: Array[int] = [0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4]

const POOL_MAX := 255      # world §13 -- the tile budget
const SUB_DISPLACE := 64   # world §13 -- each solid subtile displaces 64
const NIBBLE_MAX := 15     # 4-bit occupancy

# subtile kinds for get_sub/set_sub -- column order matches SUB_SINK
const K_STONE := 0
const K_SOIL := 1
const K_WOOD := 2

const DAMP_PER_SUB := 32   # damp capacity per soil subtile (ruling: 1:1 with water and steam)
const DAMP_WOOD_PER_SUB := 16   # damp capacity per wood_s subtile since the cut -- half a soil subtile; replaces the retired WOOD_DAMP_CAP
const BURN_POOL_PER_SUB := 64   # fuel-equivalents per wood_s subtile in the burn pool -- the flat per-subtile timer the doc promises
const TAG_WET := 1        # body-tag bits; poisoned/tainted/holy/fertile arrive with the body-state system

# -- Columns -----------------------------------------------------------------

var w: int
var h: int

var terrain := PackedByteArray()
var stone_s := PackedByteArray()
var soil_s := PackedByteArray()
var wood_s := PackedByteArray()
var water := PackedByteArray()
var oil := PackedByteArray()
var acid := PackedByteArray()
var lava := PackedByteArray()
var smoke := PackedByteArray()
var steam := PackedByteArray()
var damp := PackedByteArray()
var tags := PackedByteArray()
var fire_s := PackedByteArray()  # fire subtile bits -- overlay state: unbooked, displaces nothing
var debug_s := PackedByteArray()  # debug furniture markers -- overlay state: unbooked, census column fifteen (the editor lab)
var struct_s := PackedByteArray()  # structure membership nibble-pairs over the subtile layout -- overlay state: unbooked, census column fifteen since the retirement cut (the bedrock lab); a set bit fuses that cell into an authored structure
var actor_s := PackedByteArray()

var _booked := PackedInt64Array()   # ledger: booked totals, one per row
var _present := PackedInt32Array()   # per material: count of tiles holding nonzero units -- the absent-pass gate
var _fire_present := 0   # tiles holding fire bits -- has_fire()'s gate (set_fire keeps it honest)
var _debug_present := 0   # tiles carrying furniture -- has_debug()'s gate (set_debug keeps it honest)
var _struct_present := 0   # tiles carrying membership -- has_structures()'s gate (set_struct and the cut invariant keep it honest)

## Allocate the w×h grid: every column resized, ledger zeroed.
func _init(p_w: int, p_h: int) -> void:
	w = p_w
	h = p_h
	var n := w * h
	# Sixteen boring resizes, no clever loop: a packed array passed through a temporary may not resize the member. Boring is bulletproof.
	terrain.resize(n)
	stone_s.resize(n)
	soil_s.resize(n)
	wood_s.resize(n)
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
	fire_s.resize(n)
	debug_s.resize(n)
	struct_s.resize(n)
	actor_s.resize(n)
	clear()

## Zero every column and the ledger.
func clear() -> void:
	terrain.fill(T.AIR)
	stone_s.fill(0)
	soil_s.fill(0)
	wood_s.fill(0)
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
	fire_s.fill(0)
	debug_s.fill(0)
	struct_s.fill(0)
	actor_s.fill(0)
	_fire_present = 0
	_debug_present = 0
	_struct_present = 0

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

## Subtile nibble at tile i; kind: 0 stone_s, 1 soil_s, 2 wood_s (matches SUB_SINK order).
func get_sub(i: int, kind: int) -> int:
	match kind:
		0: return stone_s[i]
		1: return soil_s[i]
		_: return wood_s[i]

## Set a nibble column, book the popcount delta; returns the capacity deficit created (ejecting that overflow is the flow engine's job, world §3).
func set_sub(i: int, kind: int, n: int) -> int:
	n = clampi(n, 0, NIBBLE_MAX)
	var old := get_sub(i, kind)
	if old == n:
		return 0
	match kind:
		0: stone_s[i] = n
		1: soil_s[i] = n
		2: wood_s[i] = n
	_book(Led.STONE_S + kind, POPCOUNT[n] - POPCOUNT[old])
	# membership dies with its matter (world §3, the cut invariant) -- soil never carries membership, and a tile dropping its last bit drops the gate count
	if kind != K_SOIL:
		var dead := old & ~n
		if dead != 0 and struct_s[i] != 0:
			struct_s[i] &= ~dead
			if struct_s[i] == 0:
				_struct_present -= 1
	# post-write: stranded damp drains with booking -- sim paths pre-carry it out, so this only catches tool writes (erase, brush, clear)
	var cap := damp_capacity(i)
	if damp[i] > cap:
		_book(Led.DAMP, cap - damp[i])
		damp[i] = cap
	return maxi(0, pool_total(i) - pool_capacity(i))

# -- Capacity ----------------------------------------------------------------

## Capacity against matter only: terrain and subtiles -- the ledger's legality line; the claim is overlay and never audited.
func solid_capacity(i: int) -> int:
	if FULL_SOLID[terrain[i]]:
		return 0
	return maxi(0, POOL_MAX - SUB_DISPLACE * (POPCOUNT[stone_s[i]] + POPCOUNT[soil_s[i]] + POPCOUNT[wood_s[i]]))

## Full-solid terrain = 0, otherwise the solid capacity minus the actor claim -- the bridge's ejection target (world.md §4).
func pool_capacity(i: int) -> int:
	return maxi(0, solid_capacity(i) - SUB_DISPLACE * actor_s[i])

## Actor-claimed occupancy nibbles at tile i -- the bridge is the single writer, rebuilding the column every tick head.
func get_actor_claim(i: int) -> int:
	return actor_s[i]

## Add to the tile's actor claim, clamped to a full tile's worth; capacity reads it live.
func add_actor_claim(i: int, n: int) -> void:
	actor_s[i] = clampi(actor_s[i] + n, 0, 4)

## Zero the actor claims -- the tick head rebuilds them, and restore must not carry stale ones (the census never stores them: derived state, the flow-array pattern).
func clear_actor_claims() -> void:
	actor_s.fill(0)

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

## Fresh popcount recount of one subtile column (kind: K_STONE/K_SOIL/K_WOOD) -- the mass checksum.
func sub_total(kind: int) -> int:
	var sum := 0
	match kind:
		K_STONE:
			for v in stone_s: sum += POPCOUNT[v]
		K_SOIL:
			for v in soil_s: sum += POPCOUNT[v]
		_:
			for v in wood_s: sum += POPCOUNT[v]
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
	var s_wood := 0
	for v in wood_s: s_wood += POPCOUNT[v]
	if s_stone != _booked[Led.STONE_S]:
		push_error("ledger drift STONE_S: booked %d, counted %d" % [_booked[Led.STONE_S], s_stone])
		ok = false
	if s_soil != _booked[Led.SOIL_S]:
		push_error("ledger drift SOIL_S: booked %d, counted %d" % [_booked[Led.SOIL_S], s_soil])
		ok = false
	if s_wood != _booked[Led.WOOD_S]:
		push_error("ledger drift WOOD_S: booked %d, counted %d" % [_booked[Led.WOOD_S], s_wood])
		ok = false
	var s_damp := damp_total()
	if s_damp != _booked[Led.DAMP]:
		push_error("ledger drift DAMP: booked %d, counted %d" % [_booked[Led.DAMP], s_damp])
		ok = false
	for i in w * h:
		# the four subtile cells are a shared budget across solid kinds -- two kinds may never claim one cell; fire bits ride above it, overlay by design
		var overlap := POPCOUNT[stone_s[i]] + POPCOUNT[soil_s[i]] + POPCOUNT[wood_s[i]] - POPCOUNT[stone_s[i] | soil_s[i] | wood_s[i]]
		if overlap != 0:
			var q := xy_of(i)
			push_error("subtile overlap at %d,%d" % [q.x, q.y])
			ok = false
		if pool_total(i) > solid_capacity(i):
			var p := xy_of(i)
			push_error("pool overflow at %d,%d: %d > %d" % [p.x, p.y, pool_total(i), solid_capacity(i)])
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

## Damp capacity at tile i: 32 per soil subtile plus 16 per wood_s subtile since the cut; fixtures and bare air hold none.
func damp_capacity(i: int) -> int:
	return DAMP_PER_SUB * POPCOUNT[soil_s[i]] + DAMP_WOOD_PER_SUB * POPCOUNT[wood_s[i]]

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

## Transfer pool units between tiles, booked on both sides, no capacity clamp -- the mid-pass swap path: the caller guarantees headroom by live subtile counts, the packet's stale column catches up at repack, and the end-of-tick assert polices the invariant.
func shift_pool(from_i: int, to_i: int, m: int, amount: int) -> int:
	var moved := take_pool(from_i, m, amount)
	if moved > 0:
		_add_units(to_i, m, moved)
		_book(m, moved)
	return moved

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

# -- Fire ---------------------------------------------------------------------

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

## Zero the fire nibbles and the present count. (Clear/reset path — overlay state, nothing booked.)
func clear_fire() -> void:
	fire_s.fill(0)
	_fire_present = 0

# -- Structure membership (the bedrock lab) -----------------------------------

## Membership nibble at tile i -- fused structure bits over the subtile layout; overlay state, coexists with the matter columns, never booked.
func get_struct(i: int) -> int:
	return struct_s[i]

## Set the membership nibble at tile i -- the structure engine's single writer, the set_fire pattern: keeps the present count honest, books nothing.
func set_struct(i: int, n: int) -> void:
	n = clampi(n, 0, NIBBLE_MAX)
	var old := struct_s[i]
	if old == n:
		return
	struct_s[i] = n
	if old == 0:
		_struct_present += 1
	elif n == 0:
		_struct_present -= 1

## True when any tile carries membership -- the sand pass's fused-cell gate, _present's pattern.
func has_structures() -> bool:
	return _struct_present > 0

# -- Snapshot census (world.md §8) ------------------------------------------

## The persistent column count -- the snapshot census: terrain, three subtile nibbles, six pool, damp, tags, fire bits, debug furniture, structure membership (FUEL left at the retirement cut).
const COL_COUNT := 15

## Rewrite a legacy census (fifteen columns before the structure pass, sixteen before the retirement cut) into the current fifteen: authored STONE, WOOD, and SOIL terrain convert to 4/4 matter and pre-fused membership, fixture indices renumber, the fuel column drops, and damp clamps to the new per-subtile capacity. Pure on the bytes; the caller rebuilds books and present counts.
func migrate_legacy_cols(cols: Array, p_w: int, p_h: int) -> Array:
	var n := p_w * p_h
	var terrain_c: PackedByteArray = cols[0].duplicate()
	var stone_c: PackedByteArray = cols[1].duplicate()
	var soil_c: PackedByteArray = cols[2].duplicate()
	var wood_c: PackedByteArray = cols[3].duplicate()
	var damp_c: PackedByteArray = cols[10].duplicate()
	var struct_c := PackedByteArray()
	struct_c.resize(n)
	if cols.size() > COL_COUNT:
		struct_c = cols[COL_COUNT].duplicate()   # a Stage 2 save's membership rides along; an older save starts structure-free
	for i in n:
		match terrain_c[i]:
			1:   # legacy STONE
				terrain_c[i] = T.AIR
				stone_c[i] |= 15
				struct_c[i] |= 15
			2:   # legacy WOOD
				terrain_c[i] = T.AIR
				wood_c[i] |= 15
				struct_c[i] |= 15
			3:   # legacy SOIL -- never authored, converted for completeness
				terrain_c[i] = T.AIR
				soil_c[i] |= 15
			4, 5, 6, 7:   # legacy fixtures renumber around the retired kinds
				terrain_c[i] = terrain_c[i] - 3
			_:
				pass
		var cap := DAMP_PER_SUB * POPCOUNT[soil_c[i]] + DAMP_WOOD_PER_SUB * POPCOUNT[wood_c[i]]
		damp_c[i] = mini(damp_c[i], cap)
	return [terrain_c, stone_c, soil_c, wood_c, cols[4].duplicate(), cols[5].duplicate(), cols[6].duplicate(), cols[7].duplicate(), cols[8].duplicate(), cols[9].duplicate(), damp_c, cols[11].duplicate(), cols[13].duplicate(), cols[14].duplicate(), struct_c]

## Live reference to persistent column i, census order (0..COL_COUNT-1) -- duplicate before storing it anywhere: packed arrays are references.
func column(i: int) -> PackedByteArray:
	match i:
		0: return terrain
		1: return stone_s
		2: return soil_s
		3: return wood_s
		4: return water
		5: return oil
		6: return acid
		7: return lava
		8: return smoke
		9: return steam
		10: return damp
		11: return tags
		12: return fire_s
		13: return debug_s
		_: return struct_s

## Point persistent column i at bytes (restore path); the write bypasses books, present counts, and fire_present -- the caller rebuilds them.
func load_column(i: int, b: PackedByteArray) -> void:
	match i:
		0: terrain = b
		1: stone_s = b
		2: soil_s = b
		3: wood_s = b
		4: water = b
		5: oil = b
		6: acid = b
		7: lava = b
		8: smoke = b
		9: steam = b
		10: damp = b
		11: tags = b
		12: fire_s = b
		13: debug_s = b
		_: struct_s = b

## Recompute every booked row from fresh recounts -- the restore path's ledger rebuild; green asserts prove maintained == recounted, so this arrives consistent.
func rebuild_books() -> void:
	for m in MAT_COUNT:
		_booked[m] = mat_total(m)
	for k in 3:
		_booked[Led.STONE_S + k] = sub_total(k)
	_booked[Led.DAMP] = damp_total()

## Recompute the present counts from the columns -- the absent-pass gates' bookkeeping, bypassed by wholesale restore writes; restore-time only, never per tick.
func rebuild_present() -> void:
	for m in MAT_COUNT:
		var count := 0
		for i in w * h:
			if get_pool(i, m) > 0:
				count += 1
		_present[m] = count
	_fire_present = 0
	for i in w * h:
		if fire_s[i] != 0:
			_fire_present += 1
	_debug_present = 0
	for i in w * h:
		if debug_s[i] != 0:
			_debug_present += 1
	_struct_present = 0
	for i in w * h:
		if struct_s[i] != 0:
			_struct_present += 1

# -- Debug furniture ---------------------------------------------------------

## Debug furniture at tile i (DebugTile code) -- overlay markers carried by the census: never matter, never booked.
func get_debug(i: int) -> int:
	return debug_s[i]

## Set the furniture at tile i -- the editor's single writer, the set_fire pattern: keeps the present count honest, books nothing.
func set_debug(i: int, v: int) -> void:
	v = clampi(v, 0, DebugTile.OPEN_AIR)
	var old := debug_s[i]
	if old == v:
		return
	if old == DebugTile.NONE:
		_debug_present += 1
	elif v == DebugTile.NONE:
		_debug_present -= 1
	debug_s[i] = v

## True when any tile carries furniture -- the debug engine's absent-pass gate (L1b's consumer, inert until then).
func has_debug() -> bool:
	return _debug_present > 0

## Zero the furniture column. (Clear/reset path -- overlay state, nothing booked.)
func clear_debug() -> void:
	debug_s.fill(0)
	_debug_present = 0
