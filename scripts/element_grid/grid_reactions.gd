## The chemical reaction engine -- the third system beside liquid and solid
## movement. Soak trades pool water for damp; the fire solver burns fuel, boils
## water and damp up the tiered ladder, vents smoke, and engulfs the tile; ignition counts contact ticks toward catch; condensation rains steam off cool stone away from fire; the tag pass refreshes wet flags; the packet assert closes the tick (reactions run last).

class_name GridReactions
extends RefCounted

const W: int = TilePacket.Mat.WATER
const OIL: int = TilePacket.Mat.OIL
const SMOKE: int = TilePacket.Mat.SMOKE
const STEAM: int = TilePacket.Mat.STEAM
const SOAK_MAX := 16   # soak-rate ceiling; floor division means 15 is the effective max while w tops at 255

# -- fire tuning (world.md §13, locked) ---------------------------------------

const BURN_RATE := 24        # fuel-units per tick per burning tile -- constant, never ventilation-modulated
const OIL_PER_FUEL := 4      # one oil unit carries four fuel-units of energy; 255 oil burns 4x a 255 fuel tile
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

var stone: GridStone
var pk: TilePacket
var width: int
var height: int

var _ignition := PackedByteArray()   # per-tile contact ticks toward catch -- overlay state, never packet, never booked
var _fire_near := PackedByteArray()  # per-tile: active fire within Chebyshev FIRE_DIST -- condensation's suppression mask, rebuilt per tick

## Bind the packet via the stone facade and size the overlay state; reactions hold no matter of their own.
func _init(w: int, h: int, terrain: GridStone) -> void:
	width = w
	height = h
	stone = terrain
	pk = terrain.packet
	_ignition.resize(w * h)
	_fire_near.resize(w * h)

## Reset the reaction state: ignition progress and the suppression mask. Packet columns clear through their owners.
func clear() -> void:
	_ignition.fill(0)
	_fire_near.fill(0)

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

## God-hand ignite at (x, y): fuel catches when its gates pass, bare air sparks one dying bit, wet fuel refuses. Returns true when something lit (the spark counts).
func ignite(x: int, y: int) -> bool:
	if not stone.in_bounds(x, y):
		return false
	var i := stone.idx(x, y)
	if pk.get_fire(i) != 0:
		return true   # already burning
	if not _burnable(i):
		pk.set_fire(i, GridSand.BL)   # the tiny spark: no fuel, one bit, dead next tick
		return true
	if not _eligible(i, x, y):
		return false
	pk.set_fire(i, GridSand.BL)
	return true

## Ignition progress at (x, y) -- contact ticks toward catch; the HUD's window into the timer.
func get_ignition(x: int, y: int) -> int:
	if not stone.in_bounds(x, y):
		return 0
	return _ignition[stone.idx(x, y)]

# -- The fire solver -----------------------------------------------------------

## The fire solver, every burning tile in index order: starve unfed flame, smother without air, burn constant, engulf one bit, boil each bit up the ladder, vent smoke by capacity. Bits pace everything but the burn -- burn is per tile and never reads ventilation. No projection: the flame above fuel is the renderer's lick, and a tile's fire lives exactly as long as its own fuel.
func _fire_pass() -> void:
	for i in width * height:
		var f := pk.get_fire(i)
		if f == 0:
			continue
		var p := pk.xy_of(i)
		# 1) starve: fire lives only on the fuel beneath it -- the spark dies next tick, a guttered tile goes dark, nothing feeds from neighbors anymore
		if not _burnable(i):
			pk.set_fire(i, 0)
			continue
		# 2) smother: air from the tile or any orthogonal, smoke and steam counted as occupancy
		if not _air_ok(i, p.x, p.y):
			pk.set_fire(i, 0)
			if pk.get_pool(i, W) >= AIR_MIN:
				pk.take_pool(i, W, AIR_MIN)   # the drowning wisp: one steam puff as the flame dies
				pk.add_pool(i, STEAM, AIR_MIN)
			continue
		# 3) burn: the fuel field first, then oil at 4:1; a wood tile that runs dry opens the hole
		var units := pk.take_fuel(i, BURN_RATE)
		if units < BURN_RATE:
			units += pk.take_pool(i, OIL, (BURN_RATE - units) >> 2)
		if pk.get_fuel(i) == 0 and pk.get_terrain(i) == TilePacket.T.WOOD:
			stone.set_terrain(p.x, p.y, GridStone.Terrain.AIR)
		# 4) engulf: one new bit per tick while fuel remains, bottom cells first (the diagram's fill order)
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

## May this tile's own flame burn fuel: the FUEL field, pool oil, or both. -- the spark's bit carries neither and dies at the starve.
func _burnable(i: int) -> bool:
	return pk.get_fuel(i) > 0 or pk.get_pool(i, OIL) > 0

## The air check: the tile itself or any orthogonal holds pool_free >= AIR_MIN, smoke and steam counted -- fuel breathes through its neighbors (the all-adjacent doctrine).
func _air_ok(i: int, x: int, y: int) -> bool:
	if pk.pool_free(i) >= AIR_MIN:
		return true
	for k in N4X.size():
		var nx := x + N4X[k]
		var ny := y + N4Y[k]
		if stone.in_bounds(nx, ny) and pk.pool_free(stone.idx(nx, ny)) >= AIR_MIN:
			return true
	return false

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
		if pk.get_fire(i) != 0 or not _burnable(i):
			_ignition[i] = 0
			continue
		var p := pk.xy_of(i)
		if not _contact(p.x, p.y) or not _eligible(i, p.x, p.y):
			_ignition[i] = 0
			continue
		_ignition[i] += 1
		var delay := IGNITE_OIL if pk.get_fuel(i) == 0 else IGNITE_WOOD
		if _ignition[i] >= delay:
			_ignition[i] = 0
			catches.append(i)
	for i in catches:
		pk.set_fire(i, GridSand.BL)

## True when any orthogonal neighbor carries fire bits -- the ignition stimulus; no diagonals, and a tile's own flame does not count.
func _contact(x: int, y: int) -> bool:
	for k in N4X.size():
		var nx := x + N4X[k]
		var ny := y + N4Y[k]
		if stone.in_bounds(nx, ny) and pk.get_fire(stone.idx(nx, ny)) != 0:
			return true
	return false

## Catch gates: solid fuel refuses while any damp holds, oil refuses while water sits on top of it (the float layer catches, the submerged waits), and whatever catches needs the air check. Both gates apply when both fuels share a tile.
func _eligible(i: int, x: int, y: int) -> bool:
	if pk.get_fuel(i) > 0 and pk.get_damp(i) > 0:
		return false
	if pk.get_pool(i, OIL) > 0 and y > 0 and pk.get_pool(i - width, W) >= AIR_MIN:
		return false
	return _air_ok(i, x, y)

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

## True when an orthogonal neighbor is STONE terrain -- the cool surface steam condenses against (wood insulates).
func _stone_touch(i: int) -> bool:
	var p := pk.xy_of(i)
	for k in N4X.size():
		var nx := p.x + N4X[k]
		var ny := p.y + N4Y[k]
		if stone.in_bounds(nx, ny) and pk.get_terrain(stone.idx(nx, ny)) == TilePacket.T.STONE:
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

## The walk: drink at the first headroom down the column from i, passing through saturated soil (the percolation skip). Stops at the bottom, solid terrain, or the first soil-less tile.
func _soak_target(i: int) -> int:
	if pk.get_damp(i) < pk.damp_capacity(i):
		return i
	var d := i
	while d < width * height - width:
		var below := d + width
		if TilePacket.FULL_SOLID[pk.get_terrain(below)]:
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
