## The chemical reaction engine -- the third system beside liquid and solid movement: soak
## trades pool water for damp, and the fire solver burns wood_s through the burn-pool overlay (64
## fuel-equivalents per subtile at the flat rate, each emptied subtile's bit clearing through the cut), boils the ladder, vents smoke, engulfs, counts ignition contact, condenses steam off stone, refreshes tags; the packet assert closes the tick (reactions run last).

class_name GridReactions
extends RefCounted

const W: int = TilePacket.Mat.WATER
const OIL: int = TilePacket.Mat.OIL
const SMOKE: int = TilePacket.Mat.SMOKE
const STEAM: int = TilePacket.Mat.STEAM
const SOAK_MAX := 16   # soak-rate ceiling; floor division means 15 is the effective max while w tops at 255

# -- fire tuning (world.md §13, locked) ---------------------------------------

const BURN_RATE := 24        # burn-pool units per tick per burning tile -- constant, never ventilation-modulated
const OIL_PER_FUEL := 4      # one oil unit carries four burn-pool units of energy; 255 oil burns 4x a 255-pool tile
const SMOKE_PER_UNIT := 4    # smoke per material unit burned -- a production rate, not an invariant (un-vented remainder is un-made)
const IGNITE_WOOD := 5       # contact ticks to catch -- the front walks 2 tiles/s
const IGNITE_OIL := 1        # oil flashes on contact
const BOIL_W: Array[int] = [8, 4, 2]   # standing water per fire bit at Manhattan distance 0/1/2
const BOIL_D: Array[int] = [4, 2, 1]   # damp per bit at the same distances -- half the water rate everywhere
const CONDENSE_RATE := 2     # steam -> water per tick off cool stone, fire permitting
const FIRE_DIST := 4         # Chebyshev radius around active fire where condensation is suppressed
const AIR_MIN := 16          # pool_free the fire's tile or any orthogonal must hold -- LINE, the film threshold

# fixed scan orders (deterministic): compass N E S W; ring two, cardinals before diagonals
const N4X: Array[int] = [0, 1, 0, -1]
const N4Y: Array[int] = [-1, 0, 1, 0]
const R2X: Array[int] = [0, 2, 0, -2, 1, 1, -1, -1]
const R2Y: Array[int] = [-2, 0, 2, 0, -1, 1, 1, -1]

# per fire bit, the two corner-facing breath faces as (dx, dy): BL south+west, BR south+east,
# TL north+west, TR north+east -- bit 1<<c reads BREATH[c*2] and BREATH[c*2+1] (world §3)
const BREATH: Array = [
	[0, 1], [-1, 0],
	[0, 1], [1, 0],
	[0, -1], [-1, 0],
	[0, -1], [1, 0],
]

var stone: GridStone
var structures: GridStructures   # burn-out is a cut -- emptied wood cells re-partition through the engine
var pk: TilePacket
var width: int
var height: int

var _ignition := PackedByteArray()   # per-tile contact ticks toward catch -- overlay state, never packet, never booked
var _fire_near := PackedByteArray()  # per-tile: active fire within Chebyshev FIRE_DIST -- condensation's suppression mask, rebuilt per tick
var _wood_burn := PackedByteArray()  # per-tile burn pool: BURN_POOL_PER_SUB fuel-equivalents per wood_s subtile -- overlay state, snapshotted with the ignition timer
var _starved := PackedByteArray()    # per-tile: consecutive ticks the fire could not drink -- the smother timer, overlay state
var burned_units := 0   # diagnostic: burn-pool and oil units consumed since clear -- the fire suite's smoke ceiling reads it

## Bind the packet via the stone facade, take the structure engine for burn-out cuts, and size the overlay state; reactions hold no matter of their own.
func _init(w: int, h: int, terrain: GridStone, p_structures: GridStructures) -> void:
	width = w
	height = h
	stone = terrain
	structures = p_structures
	pk = terrain.packet
	_ignition.resize(w * h)
	_fire_near.resize(w * h)
	_wood_burn.resize(w * h)
	_starved.resize(w * h)

## Reset the reaction state: ignition progress, the burn pool, the smother timer, and the suppression mask. Packet columns clear through their owners.
func clear() -> void:
	_ignition.fill(0)
	_fire_near.fill(0)
	_wood_burn.fill(0)
	_starved.fill(0)
	burned_units = 0

## One tick: soak, then the fire solver, then ignition and condensation, then tags (reactions run last, so the end-of-tick assert is theirs). Soak precedes fire by ruling: the puddle drinks before the flame boils what is left of it.
func tick() -> void:
	if pk.has_mat(W):
		_soak_pass()
	if pk.has_fire():
		_fire_pass()
		_ignition_pass()
	else:
		_ignition.fill(0)
	_condense_pass()
	_tag_pass()
	pk.assert_all()

## God-hand ignite at (x, y): wood_s catches when bone-dry and its gates pass, oil flashes, bare air sparks one dying bit, wet wood refuses. Returns true when something lit (the spark counts).
func ignite(x: int, y: int) -> bool:
	if not stone.in_bounds(x, y):
		return false
	var i := stone.idx(x, y)
	if pk.get_fire(i) != 0:
		return true   # already burning
	_seed_burn(i)   # the pool must exist before burnable asks -- wood ignites into it
	if not _burnable(i):
		pk.set_fire(i, GridSand.BL)   # the tiny spark: no fuel, one bit, dead next tick
		return true
	if not _eligible(i, x, y):
		return false
	var bit := _catch_bit(i, x, y)
	if bit < 0:
		return false   # no breathing cell -- the material refuses to catch here
	pk.set_fire(i, bit)
	_seed_burn(i)
	return true

## Ignition progress at (x, y) -- contact ticks toward catch; the HUD's window into the timer.
func get_ignition(x: int, y: int) -> int:
	if not stone.in_bounds(x, y):
		return 0
	return _ignition[stone.idx(x, y)]

## Burn pool remaining at (x, y) -- the HUD's and the pace tests' window into the wood timer.
func get_woodburn(x: int, y: int) -> int:
	if not stone.in_bounds(x, y):
		return 0
	return _wood_burn[stone.idx(x, y)]

# -- The fire solver -----------------------------------------------------------

## The fire solver, every burning tile in index order: starve unfed flame, smother without air, burn constant, engulf one bit, boil each bit up the ladder, vent smoke by capacity. Bits pace everything but the burn -- burn is per tile and never reads ventilation. No projection: the flame above fuel is the renderer's lick, and a tile's fire lives exactly as long as its own fuel.
func _fire_pass() -> void:
	for i in width * height:
		var f := pk.get_fire(i)
		if f == 0:
			continue
		var p := pk.xy_of(i)
		# 1) gutter: fire lives only on burnable matter beneath it -- the spark dies this tick, and a fire whose wood is gone gutters even with pool left (the pool is meaningless without fuel)
		if not _fuel_here(i):
			pk.set_fire(i, 0)
			continue
		# 2) breathe: a starving fire pauses -- no burn, no boil, no engulf, no stimulus -- and dies after its material's smother delay (world §3)
		if not _can_drink(i, p.x, p.y):
			_starved[i] += 1
			if _starved[i] >= _smother_delay(i):
				if pk.get_pool(i, W) >= AIR_MIN:
					pk.take_pool(i, W, AIR_MIN)   # the drowning wisp: one steam puff as the flame dies
					pk.add_pool(i, STEAM, AIR_MIN)
				pk.set_fire(i, 0)
			continue
		_starved[i] = 0
		# 3) burn: the wood pool first -- 64 fuel-equivalents per subtile drained at the flat rate, each emptied subtile's bit clearing through the cut -- then oil at 4:1
		var units := 0
		var wbits := pk.get_sub(i, TilePacket.K_WOOD) & f
		if wbits != 0:
			if _wood_burn[i] == 0:
				_seed_burn(i)   # defensive: fire on wood without a seeded pool (direct set_fire paths)
			if _wood_burn[i] > 0:
				units = mini(BURN_RATE, _wood_burn[i])
				_wood_burn[i] -= units
			# burnout: the pool can carry fewer subtiles than still burn -- clear the lowest burning wood bits through the single writer; each clear is a cut
			@warning_ignore("integer_division")
			var want := (_wood_burn[i] + TilePacket.BURN_POOL_PER_SUB - 1) / TilePacket.BURN_POOL_PER_SUB
			while TilePacket.POPCOUNT[wbits] > want:
				for bit in [GridSand.BL, GridSand.BR, GridSand.TL, GridSand.TR]:
					if (wbits & bit) != 0:
						pk.set_sub(i, TilePacket.K_WOOD, pk.get_sub(i, TilePacket.K_WOOD) & ~bit)
						pk.set_fire(i, pk.get_fire(i) & ~bit)
						structures.repartition_around(p.x, p.y)
						wbits &= ~bit
						f = pk.get_fire(i)
						break
		if units < BURN_RATE:
			units += pk.take_pool(i, OIL, (BURN_RATE - units) >> 2)
		burned_units += units
		# 4) engulf: one new bit per tick while burnable matter remains, bottom cells first (the diagram's fill order)
		if _burnable(i):
			for bit in [GridSand.BL, GridSand.BR, GridSand.TL, GridSand.TR]:
				if (f & bit) == 0:
					pk.set_fire(i, f | bit)
					f |= bit
					break
		# 5) boil: each bit walks the tiered ladder once, first passing check, on live state
		for _b in TilePacket.POPCOUNT[f]:
			_boil_one(i, p.x, p.y)
		# 6) smoke: four per unit burned, into whatever capacity the neighborhood holds
		if units > 0:
			_emit(i, p.x, p.y, SMOKE, units * SMOKE_PER_UNIT)

## May this tile's own flame burn: wood burn pool or pool oil -- the spark's bit carries neither and dies at the starve.
func _burnable(i: int) -> bool:
	return _wood_burn[i] > 0 or pk.get_pool(i, OIL) > 0

## Does burnable matter exist here at all -- unlit wood or oil -- the contact-ignition gate: the burn pool is the meter, not the fuel's existence, so unburnt wood answers yes with an empty pool.
func _fuel_here(i: int) -> bool:
	return TilePacket.POPCOUNT[pk.get_sub(i, TilePacket.K_WOOD)] > 0 or pk.get_pool(i, OIL) > 0

## A fire drinks through each burning subtile's own cell and its two corner-facing faces: TL breathes north and west, BR south and east, and so on -- but a fire on woodless ground is oil, pool matter with no position: it breathes the tile and all four orthogonals (world §3). Full 4/4 wood fire unions to the tile plus all four orthogonals -- the shipped geometry, exactly.
func _can_drink(i: int, x: int, y: int) -> bool:
	var f := pk.get_fire(i)
	if pk.pool_free(i) + 64 * pk.actor_s[i] >= AIR_MIN:
		return true
	if pk.get_sub(i, TilePacket.K_WOOD) == 0:
		# oil fire: pool matter is not positioned -- the tile-wide drink, the shipped geometry
		for k in N4X.size():
			var ox := x + N4X[k]
			var oy := y + N4Y[k]
			if stone.in_bounds(ox, oy):
				var oi := stone.idx(ox, oy)
				if pk.pool_free(oi) + 64 * pk.actor_s[oi] >= AIR_MIN:
					return true
		return false
	for c in 4:
		var bit := 1 << c
		if (f & bit) == 0:
			continue
		for half in 2:
			var dx: int = BREATH[c * 2 + half][0]
			var dy: int = BREATH[c * 2 + half][1]
			var nx := x + dx
			var ny := y + dy
			if not stone.in_bounds(nx, ny):
				continue
			var ni := stone.idx(nx, ny)
			if pk.pool_free(ni) + 64 * pk.actor_s[ni] >= AIR_MIN:
				return true
	return false

## The catch-side drink for an unlit tile: its matter cells' breath union -- a full 4/4 tile reads self plus all four orthogonals, today's eligibility.
func _can_drink_matter(i: int, x: int, y: int) -> bool:
	var wbits := pk.get_sub(i, TilePacket.K_WOOD)
	if pk.pool_free(i) + 64 * pk.actor_s[i] >= AIR_MIN:
		return true
	if wbits == 0:
		for k in N4X.size():
			var nx := x + N4X[k]
			var ny := y + N4Y[k]
			if stone.in_bounds(nx, ny):
				var ni := stone.idx(nx, ny)
				if pk.pool_free(ni) + 64 * pk.actor_s[ni] >= AIR_MIN:
					return true
		return false
	for c in 4:
		var bit := 1 << c
		if (wbits & bit) == 0:
			continue
		for half in 2:
			var dx: int = BREATH[c * 2 + half][0]
			var dy: int = BREATH[c * 2 + half][1]
			var nx := x + dx
			var ny := y + dy
			if not stone.in_bounds(nx, ny):
				continue
			var ni := stone.idx(nx, ny)
			if pk.pool_free(ni) + 64 * pk.actor_s[ni] >= AIR_MIN:
				return true
	return false

## The ember's placement: the first wood cell whose breath set drinks, in fill order -- a fire is born on a subtile that can breathe, never sealed inside its own birth (world §3). -1 when none can (the union gates before this runs, so -1 is a corner, not a path).
func _catch_bit(i: int, x: int, y: int) -> int:
	var wbits := pk.get_sub(i, TilePacket.K_WOOD)
	if wbits == 0:
		return GridSand.BL   # an oil fire is tile-wide, not positioned -- the old default ember
	for c in 4:
		var bit := 1 << c
		if (wbits & bit) == 0:
			continue
		if pk.pool_free(i) + 64 * pk.actor_s[i] >= AIR_MIN:
			return bit
		for half in 2:
			var nx: int = x + BREATH[c * 2 + half][0]
			var ny: int = y + BREATH[c * 2 + half][1]
			if stone.in_bounds(nx, ny):
				var ni := stone.idx(nx, ny)
				if pk.pool_free(ni) + 64 * pk.actor_s[ni] >= AIR_MIN:
					return bit
	return -1

## The smother delay is the igniting material's own catch delay, inverted: wood 5, oil 1, a mixed tile takes the slow burner's 5.
func _smother_delay(i: int) -> int:
	return IGNITE_OIL if TilePacket.POPCOUNT[pk.get_sub(i, TilePacket.K_WOOD)] == 0 else IGNITE_WOOD

## One fire bit walks the boil ladder: W0, D0, W1, D1, W2, D2 -- the first passing check only, capped by what is there, one source per bit. Standing water boils at twice the damp rate at every distance, in place where it stands; damp-steam is created matter and vents from its source tile. The distance rings ignore occlusion by ruling: stone-slowed distant boil is the readable distinction.
func _boil_one(i: int, x: int, y: int) -> void:
	var v := pk.get_pool(i, W)
	if v > 0:
		var amt := mini(BOIL_W[0], v)
		pk.take_pool(i, W, amt)
		pk.add_pool(i, STEAM, amt)
		return
	var d := pk.get_damp(i)
	if d > 0:
		_emit(i, x, y, STEAM, pk.take_damp(i, mini(BOIL_D[0], d)))
		return
	for k in N4X.size():
		var nx := x + N4X[k]
		var ny := y + N4Y[k]
		if not stone.in_bounds(nx, ny):
			continue
		var ni := stone.idx(nx, ny)
		var nv := pk.get_pool(ni, W)
		if nv > 0:
			var amt := mini(BOIL_W[1], nv)
			pk.take_pool(ni, W, amt)
			pk.add_pool(ni, STEAM, amt)
			return
	for k in N4X.size():
		var nx := x + N4X[k]
		var ny := y + N4Y[k]
		if not stone.in_bounds(nx, ny):
			continue
		var ni := stone.idx(nx, ny)
		var nd := pk.get_damp(ni)
		if nd > 0:
			_emit(ni, nx, ny, STEAM, pk.take_damp(ni, mini(BOIL_D[1], nd)))
			return
	for k in R2X.size():
		var nx := x + R2X[k]
		var ny := y + R2Y[k]
		if not stone.in_bounds(nx, ny):
			continue
		var ni := stone.idx(nx, ny)
		var nv := pk.get_pool(ni, W)
		if nv > 0:
			var amt := mini(BOIL_W[2], nv)
			pk.take_pool(ni, W, amt)
			pk.add_pool(ni, STEAM, amt)
			return
	for k in R2X.size():
		var nx := x + R2X[k]
		var ny := y + R2Y[k]
		if not stone.in_bounds(nx, ny):
			continue
		var ni := stone.idx(nx, ny)
		var nd := pk.get_damp(ni)
		if nd > 0:
			_emit(ni, nx, ny, STEAM, pk.take_damp(ni, mini(BOIL_D[2], nd)))
			return

## Vent created matter (smoke, damp-steam): the source tile's own headroom first, then the breathiest orthogonal, then the next — descending headroom, compass order breaking ties — so the chimney is a neighbor like any other, never the first-choice dump. Whatever fits is booked; the remainder is un-made -- no debt, no buffer, no rate change.
func _emit(src: int, x: int, y: int, m: int, amount: int) -> void:
	var left := amount - pk.add_pool(src, m, amount)
	for _pick in 4:
		if left <= 0:
			return
		var best := -1
		var best_free := 0
		for k in N4X.size():
			var nx := x + N4X[k]
			var ny := y + N4Y[k]
			if not stone.in_bounds(nx, ny):
				continue
			var ni := stone.idx(nx, ny)
			var free := pk.pool_free(ni)
			if free > best_free:
				best = ni
				best_free = free
		if best < 0:
			return
		left -= pk.add_pool(best, m, left)

# -- Ignition ------------------------------------------------------------------

## Ignition delay: cold fuel in orthogonal contact accrues one progress tick per tick of joint contact and eligibility; any lapse resets it (the timer is the material's, so multiple burning neighbors never stack it). Catches land from a pending list after the sweep -- same-pass catches must not cascade contact, or the stagger drops to four ticks and the front walks 2.5 tiles a second.
func _ignition_pass() -> void:
	var catches := PackedInt32Array()
	for i in width * height:
		if pk.get_fire(i) != 0 or not _fuel_here(i):
			_ignition[i] = 0
			continue
		var p := pk.xy_of(i)
		if not _contact(p.x, p.y) or not _eligible(i, p.x, p.y):
			_ignition[i] = 0
			continue
		_ignition[i] += 1
		var delay := IGNITE_OIL if TilePacket.POPCOUNT[pk.get_sub(i, TilePacket.K_WOOD)] == 0 else IGNITE_WOOD
		if _ignition[i] >= delay:
			_ignition[i] = 0
			if _catch_bit(i, pk.xy_of(i).x, pk.xy_of(i).y) >= 0:
				catches.append(i)
	for i in catches:
		pk.set_fire(i, _catch_bit(i, pk.xy_of(i).x, pk.xy_of(i).y))
		_seed_burn(i)

## True when any orthogonal neighbor carries live (unstarved) fire bits -- the ignition stimulus; no diagonals, a tile's own flame does not count, and a paused fire feeds no one (world §3).
func _contact(x: int, y: int) -> bool:
	for k in N4X.size():
		var nx := x + N4X[k]
		var ny := y + N4Y[k]
		if stone.in_bounds(nx, ny):
			var ni := stone.idx(nx, ny)
			if pk.get_fire(ni) != 0 and _starved[ni] == 0:
				return true
	return false

## Catch gates: wood_s refuses while any damp holds (bone-dry ignition), oil refuses while water sits on top of it (the float layer catches, the submerged waits), and whatever catches needs the air check. Both gates apply when both fuels share a tile.
func _eligible(i: int, x: int, y: int) -> bool:
	if TilePacket.POPCOUNT[pk.get_sub(i, TilePacket.K_WOOD)] > 0 and pk.get_damp(i) > 0:
		return false
	if pk.get_pool(i, OIL) > 0 and y > 0 and pk.get_pool(i - width, W) >= AIR_MIN:
		return false
	return _can_drink_matter(i, x, y)

## Seed the burn pool at catch: BURN_POOL_PER_SUB fuel-equivalents per wood_s subtile, capped at the byte -- bare oil and sparks seed nothing. A fresh ember breathes freely; the smother timer starts clean.
func _seed_burn(i: int) -> void:
	var cells := TilePacket.POPCOUNT[pk.get_sub(i, TilePacket.K_WOOD)]
	if cells > 0:
		_wood_burn[i] = mini(255, TilePacket.BURN_POOL_PER_SUB * cells)
	_starved[i] = 0

# -- Condensation ---------------------------------------------------------------

## Condensation: steam rains back into water on cool stone, two units per tick in place, suppressed within Chebyshev FIRE_DIST of any active fire (the mask is rebuilt from the fire bits every tick). In place and net-zero, so it always fits.
func _condense_pass() -> void:
	_fire_near.fill(0)
	if pk.has_fire():
		for i in width * height:
			if pk.get_fire(i) != 0:
				var p := pk.xy_of(i)
				for dy in range(-FIRE_DIST, FIRE_DIST + 1):
					for dx in range(-FIRE_DIST, FIRE_DIST + 1):
						if stone.in_bounds(p.x + dx, p.y + dy):
							_fire_near[stone.idx(p.x + dx, p.y + dy)] = 1
	if not pk.has_mat(STEAM):
		return
	for i in width * height:
		if _fire_near[i] != 0:
			continue
		var v := pk.get_pool(i, STEAM)
		if v <= 0:
			continue
		if not _stone_touch(i):
			continue
		var amt := mini(CONDENSE_RATE, v)
		pk.take_pool(i, STEAM, amt)
		pk.add_pool(i, W, amt)

## True when an orthogonal neighbor holds stone_s -- the cool surface steam condenses against (wood insulates; a chipped wall still counts).
func _stone_touch(i: int) -> bool:
	var p := pk.xy_of(i)
	for k in N4X.size():
		var nx := p.x + N4X[k]
		var ny := p.y + N4Y[k]
		if stone.in_bounds(nx, ny) and TilePacket.POPCOUNT[pk.get_sub(stone.idx(nx, ny), TilePacket.K_STONE)] > 0:
			return true
	return false

# -- Soak and tags (shipped, unchanged) -----------------------------------------

## Soak pass: each water-bearing tile drinks clampi(w/16, 1, 16) per tick into the first headroom down its column -- its own soil, else through saturated soil below. Water never soaks across air, water-only tiles, or solid terrain.
func _soak_pass() -> void:
	for i in width * height:
		var w := pk.get_pool(i, W)
		if w == 0:
			continue
		var d := _soak_target(i)
		if d < 0:
			continue
		var room := pk.damp_capacity(d) - pk.get_damp(d)
		var amt := mini(clampi(w >> 4, 1, SOAK_MAX), mini(room, w))
		if amt > 0:
			pk.take_pool(i, W, amt)
			pk.add_damp(d, amt)

## The walk: drink at the first headroom down the column from i, passing through saturated soil (the percolation skip). Stops at the bottom, at ground that can neither hold water nor absorb it (fixtures and packed stone -- but packed soil and wood drink), or at the first soil-less tile.
func _soak_target(i: int) -> int:
	if pk.get_damp(i) < pk.damp_capacity(i):
		return i
	var d := i
	while d < width * height - width:
		var below := d + width
		if pk.solid_capacity(below) == 0 and pk.damp_capacity(below) == 0:
			return -1
		if TilePacket.POPCOUNT[pk.get_sub(below, TilePacket.K_SOIL)] == 0:
			return -1
		if pk.get_damp(below) < pk.damp_capacity(below):
			return below
		d = below
	return -1

## Refresh wet tags from damp: gain above 50% of capacity, lose below 30% -- hysteresis, so the tag is state that survives the band. Zero-capacity tiles never carry it.
func _tag_pass() -> void:
	for i in width * height:
		var cap := pk.damp_capacity(i)
		if cap == 0:
			pk.set_tag(i, TilePacket.TAG_WET, false)
			continue
		var d := pk.get_damp(i)
		if d * 2 > cap:
			pk.set_tag(i, TilePacket.TAG_WET, true)
		elif d * 10 < cap * 3:
			pk.set_tag(i, TilePacket.TAG_WET, false)

## The ignition overlay, value-copied for a room snapshot; the timer is persistent, the suppression mask is not.
func snapshot_ignition() -> PackedByteArray:
	return _ignition.duplicate()

## Write the ignition overlay back and blank the suppression mask -- it rebuilds from the fire bits on the next tick.
func restore_ignition(b: PackedByteArray) -> void:
	_ignition = b.duplicate()
	_fire_near.fill(0)

## The burn pool, value-copied for a room snapshot -- a burning wall's remaining burnables ride the census discipline.
func snapshot_woodburn() -> PackedByteArray:
	return _wood_burn.duplicate()

## Write the burn pool back -- restore-exact fires resume their timers.
func restore_woodburn(b: PackedByteArray) -> void:
	_wood_burn = b.duplicate()

## The smother timer, value-copied for a room snapshot -- a starving fire's remaining grace rides with it.
func snapshot_starved() -> PackedByteArray:
	return _starved.duplicate()

## Write the smother timer back.
func restore_starved(b: PackedByteArray) -> void:
	_starved = b.duplicate()
