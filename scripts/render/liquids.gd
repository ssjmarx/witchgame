## The liquid layer (world §9, tileset lab 2b): the state IS the picture -- paint reads
## the settled CA and flow export directly, snaps per tick; the pose model died. Level tiles,
## synchronized crests, the rain field, the waterfall telegraph; compositing around matter (§3).

class_name Liquids
extends RefCounted

const TILE := 16   # pixels per tile, the renderer's constant mirrored
const BOTTOM_MASK := GridSand.BL | GridSand.BR   # the lift's reads
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


## Paint one tile's liquid: thin falling streams draw the rain field; a solid falling column (half capacity or more) draws its fill with rain over it -- the waterfall read; resting bodies draw bottom-subtile-full, top-subtile-at-level, the crest on the surface subtile of a body deeper than one full tile; a pool mouth under strong downflow keeps the read.
func paint(x: int, y: int, px: int, py: int, blit: Callable) -> void:
	var i := stone.idx(x, y)
	if stone.is_solid(x, y):
		return
	var liq := _liquid_total(i)
	if liq <= 0:
		return   # a flow stamp with no liquid beneath it is gas in transit -- rain is never made of gas (world §9)
	var mag := water.get_flow_mag(x, y)
	var below := i + stone.width if y < stone.height - 1 else -1
	var below_full := below >= 0 and not stone.is_solid(x, y + 1) and _liquid_total(below) >= 240
	var supported := stone.is_solid(x, y + 1) or below_full
	var waterfall_col := not supported and liq >= 128
	if not supported and not waterfall_col:
		_draw_rain(x, y, px, py, liq, mag, blit)
		return
	var lines := _lifted_lines(liq >> 4, pk.get_sub(i, TilePacket.K_SOIL))
	var kind := KIND[_band_top(i, liq)]
	var pattern := pk.occlusion_bits(i)
	var crest_v := (water.tick_count >> 2) & 1   # the synchronized ping-pong: one wave per four ticks, every crest in lockstep
	var deep := supported and below_full   # the crest means a body deeper than one full tile (world §9)
	# the standing body: bottom subtile full-or-level, top subtile at level; the crest rides the surface subtile
	_blit_cells(blit, kind, pattern, px, py + 8, mini(lines, 8), deep and lines <= 8, crest_v)
	_blit_cells(blit, kind, pattern, px, py, maxi(lines - 8, 0), deep and lines > 8 and lines < 15, crest_v)
	# the waterfall read: a solid falling column or a pool mouth under strong downflow draws rain over its fill (world §9)
	if waterfall_col or (water.get_flow_dir(x, y) == GridWater.FlowDir.DOWN and mag >= FLOW_STREAK):
		_draw_rain(x, y, px, py, liq, mag, blit)

## Blit the level tile into each empty cell of the subtile row at (dx, dy) -- per-cell compositing: solid cells draw nothing, empty cells draw the level (the hand-listable table as one loop).
func _blit_cells(blit: Callable, kind: String, pattern: int, dx: int, dy: int, lines: int, surface: bool, crest_v: int) -> void:
	if kind == "" or lines <= 0:
		return
	var role := _level_role(lines, surface, crest_v)
	for c in SUB_QUADS:
		if (pattern & c[0]) == 0:
			blit.call(kind, role, dx + c[1], dy)

## The level-tile role for a line count: quantized to the four steps; the crest pair rides the surface's 2/4/6 steps -- a full step stays flat (a brim-full surface has no wave).
func _level_role(lines: int, surface: bool, crest_v: int) -> String:
	var q := clampi((lines + 1) >> 1, 1, 4) * 2
	if surface and q != 8:
		return "crest_%d%s" % [q, "a" if crest_v == 0 else "b"]
	return "lev_%d" % q

## The rain field: one variant by amount or flow, blitted across both subtile columns spanning the scroll seam -- the dashes fall one cell per two tick windows, the right strip one phase late so the columns stagger tl->bl then tr->br (world §9).
func _draw_rain(x: int, y: int, px: int, py: int, liq: int, mag: int, blit: Callable) -> void:
	var kind := KIND[_majority(stone.idx(x, y))]
	if kind == "":
		return
	var v := clampi(1 + (maxi(liq, mag) >> 5), 1, 4)
	var scroll_l := (water.tick_count & 1) * 8
	var scroll_r := ((water.tick_count + 1) & 1) * 8
	blit.call(kind, "rain_%d" % v, px, py + scroll_l - 8)
	blit.call(kind, "rain_%d" % v, px, py + scroll_l)
	blit.call(kind, "rain_%d" % v, px + 8, py + scroll_r - 8)
	blit.call(kind, "rain_%d" % v, px + 8, py + scroll_r)

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

## Waterline lift over the tile's own soil subtiles: a squeezed pool reads higher on the fill. v = raw lines, n = soil nibble; returns the drawn line count, clamped to 15.
func _lifted_lines(v: int, n: int) -> int:
	var bottom := TilePacket.POPCOUNT[n & BOTTOM_MASK]
	var top := TilePacket.POPCOUNT[n & TOP_MASK]
	var shown := v
	if bottom == 2:
		if top == 0:
			shown = v + 4
		else:
			shown = mini(2 * v + 4, v + 6)
	elif bottom == 1:
		var cap := 2
		if top > 0:
			cap = 4
		shown = mini(2 * v, v + cap)
	return mini(shown, 15)
