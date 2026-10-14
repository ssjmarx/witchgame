## The liquid layer (world §9, tileset lab 2b): the state IS the picture -- paint reads
## the settled CA and flow export directly, snaps per tick; the pose model died. Level tiles,
## synchronized crests, the two-band rain field, per-cell volume distribution, rain-through.

class_name Liquids
extends RefCounted

const TILE := 16   # pixels per tile, the renderer's constant mirrored
const BOTTOM_MASK := GridSand.BL | GridSand.BR   # the open-row counts' reads
const TOP_MASK := GridSand.TL | GridSand.TR
const LIQ_DRAW: Array[int] = [TilePacket.Mat.LAVA, TilePacket.Mat.ACID, TilePacket.Mat.WATER, TilePacket.Mat.OIL]   # density order: densest sinks to the bottom band
const SUB_QUADS: Array = [[GridSand.TL, 0, 0], [GridSand.TR, 8, 0], [GridSand.BL, 0, 8], [GridSand.BR, 8, 8]]   # the four cells: bit, px, py within the tile
const FLOW_STREAK := 48     # downflow at or above this draws the waterfall read -- the FLOW_BLOCK telegraph
const KIND: Array[String] = ["water", "oil", "acid", "lava", "", ""]   # Mat id -> atlas kind (the gases read empty)

var stone: GridStone
var water: GridWater
var pk: TilePacket

## Bind the sim pair the renderer binds; the layer reads state, it never writes it.
func _init(terrain: GridStone, field: GridWater) -> void:
	stone = terrain
	water = field
	pk = terrain.packet


## Paint one tile's liquid: thin falling streams draw the rain field; a solid falling column (half capacity or more) draws its fill with rain over it -- the waterfall read; resting bodies distribute their volume across the open subtile rows (per-cell compositing: solid cells draw nothing), the crest rides the surface row of a body deeper than one full tile; a standing surface under a falling column draws the rain through to its waterline; a pool mouth under strong downflow keeps the read.
func paint(x: int, y: int, px: int, py: int, blit: Callable) -> void:
	var i := stone.idx(x, y)
	if stone.is_solid(x, y):
		return
	var liq := _liquid_total(i)
	if liq <= 0:
		return   # a flow stamp with no liquid beneath it is gas in transit -- rain is never made of gas (world §9)
	var mag := water.get_flow_mag(x, y)
	var can_fall := stone.drains_v(x, y) and stone.edge_v_open(x, y + 1)
	var below := i + stone.width if y < stone.height - 1 else -1
	var below_full := below >= 0 and not stone.is_solid(x, y + 1) and _liquid_total(below) >= 240
	var supported := not can_fall or below_full
	var waterfall_col := not supported and liq >= 128
	var pattern := pk.occlusion_bits(i)
	if not supported and not waterfall_col:
		_draw_rain(x, y, px, py, liq, mag, blit, pattern)
		return
	var kind := KIND[_band_top(i, liq)]
	var crest_v := (water.tick_count >> 3) & 1   # the synchronized ping-pong: one wave every eight ticks, every crest in lockstep
	var deep := supported and below_full   # the crest means a body deeper than one full tile (world §9)
	var open_b := 2 - TilePacket.POPCOUNT[pattern & BOTTOM_MASK]
	var open_t := 2 - TilePacket.POPCOUNT[pattern & TOP_MASK]
	@warning_ignore("integer_division")
	var d_b := clampi(liq / maxi(8 * open_b, 8), 0, 8)
	var rem := maxi(liq - 64 * open_b, 0)
	@warning_ignore("integer_division")
	var d_t := clampi(rem / maxi(8 * open_t, 8), 0, 8)
	# the standing body: the open bottom row shares the volume, the remainder rides the top -- the squeeze is physical, no lift fiction
	_blit_cells(blit, kind, pattern, px, py + 8, d_b, deep and d_t == 0 and d_b > 0 and d_b < 8, crest_v, BOTTOM_MASK)
	_blit_cells(blit, kind, pattern, px, py, d_t, deep and d_t > 0 and d_t < 8, crest_v, TOP_MASK)
	# rain falls through to the waterline: the column above continues down this tile's open cells to the surface fill
	var rain_a := _raining_above(x, y, kind)
	if rain_a > 0:
		_rain_through(blit, kind, pattern, rain_a >= 64, px, py)
	# the waterfall read: a solid falling column or a pool mouth under strong downflow draws rain over its fill (world §9)
	if waterfall_col or (water.get_flow_dir(x, y) == GridWater.FlowDir.DOWN and mag >= FLOW_STREAK):
		_draw_rain(x, y, px, py, liq, mag, blit, pattern)

## Blit the level tile into each open cell of the subtile row at (dx, dy) -- row_mask pins the call to one half of the tile so a masked cell's column sibling never paints over it; solid cells draw nothing (per-cell compositing, world §9).
func _blit_cells(blit: Callable, kind: String, pattern: int, dx: int, dy: int, lines: int, surface: bool, crest_v: int, row_mask: int) -> void:
	if kind == "" or lines <= 0:
		return
	var role := _level_role(lines, surface, crest_v)
	for c in SUB_QUADS:
		if (c[0] & row_mask) != 0 and (pattern & c[0]) == 0:
			blit.call(kind, role, dx + c[1], dy)

## The level-tile role for a line count: quantized to the four steps; the crest pair rides the surface's 2/4/6 steps -- a full step stays flat (a brim-full surface has no wave).
func _level_role(lines: int, surface: bool, crest_v: int) -> String:
	var q := clampi((lines + 1) >> 1, 1, 4) * 2
	if surface and q != 8:
		return "crest_%d%s" % [q, "a" if crest_v == 0 else "b"]
	return "lev_%d" % q

## The rain field: two variants only -- light below 64 units, heavy above (the waterfall composite takes heavy) -- blitted across both subtile columns spanning the scroll seam; a fully-solid column draws no dashes; the dashes fall one cell every four ticks, the right strip one phase late so the columns stagger tl->bl then tr->br (world §9).
func _draw_rain(x: int, y: int, px: int, py: int, liq: int, mag: int, blit: Callable, pattern: int) -> void:
	var kind := KIND[_majority(stone.idx(x, y))]
	if kind == "":
		return
	var role := "rain_heavy" if maxi(liq, mag) >= 64 else "rain_light"
	var scroll_l := ((water.tick_count >> 2) & 1) * 8
	var scroll_r := (((water.tick_count >> 2) + 1) & 1) * 8
	if (pattern & (GridSand.TL | GridSand.BL)) == 0:
		blit.call(kind, role, px, py + scroll_l - 8)
		blit.call(kind, role, px, py + scroll_l)
	if (pattern & (GridSand.TR | GridSand.BR)) == 0:
		blit.call(kind, role, px + 8, py + scroll_r - 8)
		blit.call(kind, role, px + 8, py + scroll_r)

## The falling column above (x, y) of the same kind: its liquid amount, or 0 when the tile above pours no rain -- rain falls through to the waterline (world §9).
func _raining_above(x: int, y: int, kind: String) -> int:
	if y == 0 or kind == "":
		return 0
	var a := stone.idx(x, y - 1)
	if stone.is_solid(x, y - 1) or KIND[_majority(a)] != kind:
		return 0
	var liq := _liquid_total(a)
	if liq < 16:
		return 0   # a film pours no rain
	if not (stone.drains_v(x, y - 1) and stone.edge_v_open(x, y)):
		return 0   # the column above rests on something -- its rain already landed
	var below_full := not stone.is_solid(x, y) and _liquid_total(a + stone.width) >= 240
	return 0 if below_full else liq

## Rain dashes over a standing tile's open cells -- the falling column's continuation down to the surface fill (world §9).
func _rain_through(blit: Callable, kind: String, pattern: int, heavy: bool, px: int, py: int) -> void:
	var role := "rain_heavy" if heavy else "rain_light"
	for c in SUB_QUADS:
		if (pattern & c[0]) == 0:
			blit.call(kind, role, px + c[1], py + c[2])

## The tile's top-band material: the lightest material holding more than a quarter of the liquid -- mixed tiles read their top subtile as the lighter phase, the bottom as the denser (the per-line stack, coarsened to subtile rows).
func _band_top(i: int, liq: int) -> int:
	for m in range(LIQ_DRAW.size() - 1, -1, -1):
		if pk.get_pool(i, LIQ_DRAW[m]) > (liq >> 2):
			return LIQ_DRAW[m]
	return TilePacket.Mat.WATER

## Liquid units at tile i -- the pool minus the two gases, the renderer's lines read.
func _liquid_total(i: int) -> int:
	return pk.pool_total(i) - pk.get_pool(i, TilePacket.Mat.SMOKE) - pk.get_pool(i, TilePacket.Mat.STEAM)

## Majority liquid at tile i -- the material desire (ties and empties read as water).
func _majority(i: int) -> int:
	var best := TilePacket.Mat.WATER
	var best_v: int = pk.get_pool(i, best)
	for m in range(1, TilePacket.MAT_COUNT):
		var v := pk.get_pool(i, m)
		if v > best_v:
			best = m as TilePacket.Mat
			best_v = v
	return best
