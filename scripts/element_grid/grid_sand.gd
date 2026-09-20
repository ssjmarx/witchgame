## The universal loose-solid field -- falling-sand rules at 8px subtile resolution across
## every subtile column (stone, soil, ice), parameterized per material: FALL for vertical
## rate, SLIDE for sideways willingness. Repose and staircases are emergent, never stored.

class_name GridSand
extends RefCounted

# nibble bit layout (ruling): 1 = bottom-left, 2 = bottom-right, 4 = top-left, 8 = top-right
const BL := 1
const BR := 2
const TL := 4
const TR := 8

# expanded-cell codes: 0 = empty, else TilePacket kind + 1 (K_STONE -> 1, K_SOIL -> 2, K_ICE -> 3)
const EMPTY := 0

# -- Parameter tables (indexed by TilePacket kind: K_STONE, K_SOIL, K_ICE) ----

# vertical 8px steps per tick through open air (ruling: one step, all materials)
const FALL: Array[int] = [1, 1, 1]

# may take diagonal moves -- the viscosity equivalent and the alchemy seam: Lab E's damp mortar gates soil by reading state here, not by a new rule
const SLIDE: Array[bool] = [true, true, true]

const SUB_FLOW_MASS := 64   # one subtile arrival = 64 pool units of displaced liquid -- flow magnitudes stay pool-coherent
const SLIDE_WET: Array[bool] = [false, false, false]   # the sticky row: a wet tile holds every loose kind (mud glues stone)

# -- Geometry and bindings ----------------------------------------------------

var stone: GridStone
var pk: TilePacket
var width: int
var height: int

var water: GridWater

var _sub := PackedByteArray()  # expanded w*2 x h*2 material codes, refilled each tick
var _tick_count := 0

var _flow_mag := PackedByteArray()
var _flow_best := PackedByteArray()
var _flow_dir := PackedByteArray()

## Size the field, bind the packet via the stone facade and the water field for headroom queries.
func _init(w: int, h: int, terrain: GridStone, p_water: GridWater) -> void:
	width = w
	height = h
	stone = terrain
	pk = terrain.packet
	water = p_water
	_sub.resize(w * 2 * h * 2)
	_flow_mag.resize(w * h)
	_flow_best.resize(w * h)
	_flow_dir.resize(w * h)

## Flat-array index of tile (x, y).
func idx(x: int, y: int) -> int:
	return y * width + x

## Total loose-solid subtiles of one kind (K_STONE/K_SOIL/K_ICE) in the field -- the mass checksum.
func total(kind: int) -> int:
	return pk.sub_total(kind)

## Reset: zero every subtile column and the tick counter.
func clear() -> void:
	for i in width * height:
		pk.set_sub(i, TilePacket.K_STONE, 0)
		pk.set_sub(i, TilePacket.K_SOIL, 0)
		pk.set_sub(i, TilePacket.K_ICE, 0)
	_tick_count = 0
	_sub.fill(0)

# -- Tick pipeline ------------------------------------------------------------

## One tick: expand, run the sand pass, repack and book. The paired water tick owns the packet assert -- its displacement pass resolves repack's deficits same-tick.
func tick() -> void:
	_tick_count += 1
	# tick head: last tick's flow dies before any new move stamps (water's pattern)
	_flow_mag.fill(0)
	_flow_best.fill(0)
	_flow_dir.fill(0)
	_expand()
	_pass_all()
	_repack()

## Rebuild the expanded material grid from the packet nibbles (read-only).
func _expand() -> void:
	_sub.fill(0)
	var w2 := width * 2
	for y in height:
		for x in width:
			var base := y * 2 * w2 + x * 2
			for kind in 3:
				_stamp_nibble(base, pk.get_sub(idx(x, y), kind), kind)

## Write one nibble's set bits into the expanded grid as that kind's code.
func _stamp_nibble(base: int, n: int, kind: int) -> void:
	var w2 := width * 2
	if (n & BL) != 0:
		_sub[base + w2] = kind + 1
	if (n & BR) != 0:
		_sub[base + w2 + 1] = kind + 1
	if (n & TL) != 0:
		_sub[base] = kind + 1
	if (n & TR) != 0:
		_sub[base + 1] = kind + 1

## Gather the expanded grid back into per-kind nibbles; set_sub books every popcount delta.
func _repack() -> void:
	var w2 := width * 2
	for y in height:
		for x in width:
			var base := y * 2 * w2 + x * 2
			for kind in 3:
				var code := kind + 1
				var n := 0
				if _sub[base] == code: n |= TL
				if _sub[base + 1] == code: n |= TR
				if _sub[base + w2] == code: n |= BL
				if _sub[base + w2 + 1] == code: n |= BR
				pk.set_sub(idx(x, y), kind, n)

# -- The sand pass ------------------------------------------------------------

## Run _sub_pass over every subtile cell, bottom-up, sweep alternating per tick.
func _pass_all() -> void:
	var w2 := width * 2
	var h2 := height * 2
	var ltr := (_tick_count % 2 == 0)
	for sy in range(h2 - 1, -1, -1):
		if ltr:
			for sx in w2:
				_sub_pass(sx, sy)
		else:
			for sx in range(w2 - 1, -1, -1):
				_sub_pass(sx, sy)

## Apply fall / slide to one subtile; d is the medium-dependent rate -- FALL[kind] through air, SUB_SINK[kind] through liquid -- taken as gated single-cell sub-steps so a fast sinker cannot tunnel. d <= 0 (buoyant kinds) rests: rising is the float lab, not this one.
func _sub_pass(sx: int, sy: int) -> void:
	var w2 := width * 2
	var code := _sub[sy * w2 + sx]
	if code == EMPTY:
		return
	var kind := code - 1
	var d := FALL[kind] if not _in_liquid(sx, sy) else TilePacket.SUB_SINK[kind]
	if d <= 0:
		return
	var flip := -1 if (_tick_count % 2 == 0) else 1
	var cy := sy
	for _step in d:
		if not _try_move(sx, cy, sx, cy + 1, kind):
			break
		cy += 1
	if cy == sy:
		if not _try_move(sx, cy, sx + flip, cy + 1, kind):
			_try_move(sx, cy, sx - flip, cy + 1, kind)

## Move a subtile: target cell empty, tile enterable, diagonals also need the side cell clear and the slide policy; a tile crossing exports flow and hands off the mover's share of damp.
func _try_move(sx: int, sy: int, tx: int, ty: int, kind: int) -> bool:
	var w2 := width * 2
	if tx < 0 or tx >= w2 or ty < 0 or ty >= height * 2:
		return false
	var tc := ty * w2 + tx
	if _sub[tc] != EMPTY:
		return false
	if not _enterable(tx >> 1, ty >> 1):
		return false
	if tx != sx:
		if not _side_clear(tx, sy):
			return false
		if not _can_slide(kind, idx(sx >> 1, sy >> 1)):
			return false
	_sub[sy * w2 + sx] = EMPTY
	_sub[tc] = kind + 1
	if (tx >> 1) != (sx >> 1) or (ty >> 1) != (sy >> 1):
		_cross_tile(sx, sy, tx, ty, kind)
	return true

## Corner rule: the side cell must hold no subtile of any kind and sit in pool-capable terrain.
func _side_clear(sx: int, sy: int) -> bool:
	if sx < 0 or sx >= width * 2:
		return false
	if _sub[sy * width * 2 + sx] != EMPTY:
		return false
	return not TilePacket.FULL_SOLID[pk.get_terrain(idx(sx >> 1, sy >> 1))]

## Count subtile cells currently in tile (x, y) per the live expanded grid -- pre-repack truth, so same-pass landings are not missed. Caller guarantees in-bounds.
func _cells_in_tile(x: int, y: int) -> int:
	var w2 := width * 2
	var base := (y * 2) * w2 + x * 2
	var n := 0
	if _sub[base] != EMPTY: n += 1
	if _sub[base + 1] != EMPTY: n += 1
	if _sub[base + w2] != EMPTY: n += 1
	if _sub[base + w2 + 1] != EMPTY: n += 1
	return n

## May a subtile enter tile (x, y): terrain must hold a pool, and the landing either fits the budget or the displaced liquid has escape-reachable headroom up the column (air-gate family, world §3). Caller guarantees in-bounds.
func _enterable(x: int, y: int) -> bool:
	if TilePacket.FULL_SOLID[pk.get_terrain(idx(x, y))]:
		return false
	var free := TilePacket.POOL_MAX - TilePacket.SUB_DISPLACE * (_cells_in_tile(x, y) + 1) - pk.pool_total(idx(x, y))
	if free >= 0:
		return true
	return water.headroom_above(x, y)

## May kind take a diagonal move? The mortar seam: a wet-tagged tile reads the sticky row -- slide-off (and lateral creep, when it exists) gates here, fall never does. Tags are one tick stale (the _escape pattern).
func _can_slide(kind: int, i: int) -> bool:
	if pk.has_tag(i, TilePacket.TAG_WET):
		return SLIDE_WET[kind]
	return SLIDE[kind]

## Is this subtile wetted? Its own tile holds pool content. A full solid tile holds no pool; neighbor reads are the float lab's extension, not soil's.
func _in_liquid(sx: int, sy: int) -> bool:
	return pk.pool_total(idx(sx >> 1, sy >> 1)) > 0

## Register a subtile arrival at tile i (one mass quantum, dir code); magnitudes sum, direction follows the largest single arrival (first stamp wins ties -- fixed sweep order, so deterministic).
func flow_stamp(i: int, dir: int, mag: int) -> void:
	if mag <= 0:
		return
	_flow_mag[i] = mini(255, _flow_mag[i] + mag)
	if mag > _flow_best[i]:
		_flow_best[i] = mag
		_flow_dir[i] = dir

## Flow strength at (x, y): subtile mass arrived this tick, 64 pool-units per subtile; 0 outside.
func get_flow_mag(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return 0
	return _flow_mag[idx(x, y)]

## Dominant flow direction at (x, y); NONE outside.
func get_flow_dir(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return GridWater.FlowDir.NONE
	return _flow_dir[idx(x, y)]

## Book a tile crossing: export the arrival's flow mass, then hand off damp -- soil only (stone and ice hold none), an even share of the source's damp over its remaining soil subtiles, capped at one subtile's worth. Live counts on both sides keep the transfer inside capacity by construction (the carry proof).
@warning_ignore("integer_division")
func _cross_tile(sx: int, sy: int, tx: int, ty: int, kind: int) -> void:
	var src := idx(sx >> 1, sy >> 1)
	var dst := idx(tx >> 1, ty >> 1)
	var dir := GridWater.FlowDir.DOWN
	if tx < sx:
		dir = GridWater.FlowDir.DOWN_LEFT
	elif tx > sx:
		dir = GridWater.FlowDir.DOWN_RIGHT
	flow_stamp(dst, dir, SUB_FLOW_MASS)
	if kind != TilePacket.K_SOIL:
		return
	var count := _soil_in_tile(sx >> 1, sy >> 1)
	@warning_ignore("integer_division")
	var share := mini(TilePacket.DAMP_PER_SUB, pk.get_damp(src) / maxi(1, count))
	if share > 0:
		pk.shift_damp(src, dst, share)

## Count soil subtile cells in tile (x, y) per the live expanded grid -- damp's only carriers and only capacity. Caller guarantees in-bounds.
func _soil_in_tile(x: int, y: int) -> int:
	var w2 := width * 2
	var base := (y * 2) * w2 + x * 2
	var n := 0
	if _sub[base] == TilePacket.K_SOIL + 1: n += 1
	if _sub[base + 1] == TilePacket.K_SOIL + 1: n += 1
	if _sub[base + w2] == TilePacket.K_SOIL + 1: n += 1
	if _sub[base + w2 + 1] == TilePacket.K_SOIL + 1: n += 1
	return n
