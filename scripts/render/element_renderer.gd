## world.md §9: one Image the size of the map, regenerated at tick rate, pushed
## through an ImageTexture, drawn under actors. The sim state *is* the picture.
## Regenerating 240×240 RGBA ten times a second is nothing — keep it dumb.

class_name ElementRenderer
extends RefCounted

const TILE := 16  # pixels per tile
const FLOW_STREAK := 48  # <tune> — downward flow above this draws waterfall streaks
const SUB_QUADS: Array = [[GridSand.TL, 0, 0], [GridSand.TR, 8, 0], [GridSand.BL, 0, 8], [GridSand.BR, 8, 8]]
const BOTTOM_MASK := GridSand.BL | GridSand.BR  # the two lower subtile slots
const TOP_MASK := GridSand.TL | GridSand.TR      # the two upper subtile slots
const LIQ_DRAW: Array[int] = [TilePacket.Mat.LAVA, TilePacket.Mat.ACID, TilePacket.Mat.WATER, TilePacket.Mat.OIL]   # liquids stack from the bottom, densest first
const GAS_DRAW: Array[int] = [TilePacket.Mat.SMOKE, TilePacket.Mat.STEAM]   # density order; the band split walks it reversed -- the lightest gas takes the topmost rows
const MAT_COLORS: Array = [Palette.WATER, Palette.OIL, Palette.WATER, Palette.WATER, Palette.SMOKE, Palette.STEAM]   # indexed by Mat; acid/lava still alias water until their labs; the gases carry their own rows since the fire lab
const MAT_SURFACE: Array[Color] = [Palette.WATER_SURFACE, Palette.OIL_SURFACE, Palette.WATER_SURFACE, Palette.WATER_SURFACE, Palette.SMOKE_SURFACE, Palette.STEAM_SURFACE]

# the sim state this renderer draws
var stone: GridStone
var water: GridWater
var sand: GridSand = null   # optional: bound by scenes that own a solid field

# the picture: one map-sized image pushed through a texture
var image: Image
var texture: ImageTexture

# overlays
var debug := false          # G: air pockets + grid
var hover := Vector2i(-1, -1)

## Bind the sim pair and create the map-sized image and texture.
func _init(terrain: GridStone, field: GridWater) -> void:
	stone = terrain
	water = field
	# Godot 4.3+: swap for Image.create_empty(...) if the deprecation note bothers you
	image = Image.create(terrain.width * TILE, terrain.height * TILE, false, Image.FORMAT_RGBA8)
	texture = ImageTexture.create_from_image(image)

## Repaint every tile plus overlays into the texture; call once per tick.
func redraw() -> void:
	image.fill(Palette.BG)
	for y in stone.height:
		for x in stone.width:
			_draw_tile(x, y)
	if debug:
		_draw_debug()
	if hover.x >= 0 and hover.y >= 0:
		_draw_cursor()
	texture.update(image)

## Paint one tile: beveled stone or planked wood (fire quads ride either), gases dithered from the top, liquids leveling from the bottom over them, soil quads over the fill they displace, fire bits on top of everything the tile holds.
func _draw_tile(x: int, y: int) -> void:
	var px := x * TILE
	var py := y * TILE
	var i := stone.idx(x, y)
	if stone.is_solid(x, y):
		var wood := stone.packet.get_terrain(i) == TilePacket.T.WOOD
		var fill := Palette.WOOD if wood else Palette.STONE
		var dark := Palette.WOOD_DARK if wood else Palette.STONE_DARK
		image.fill_rect(Rect2i(px, py, TILE, TILE), fill)
		image.fill_rect(Rect2i(px, py, TILE, 1), dark)
		image.fill_rect(Rect2i(px, py, 1, TILE), dark)
		image.set_pixel(px + 11, py + 11, dark)
		if wood:
			image.fill_rect(Rect2i(px, py + 8, TILE, 1), dark)   # the plank seam -- minimal wood identity until step 5's real planks
		_draw_fire(x, y, px, py)
		return
	var n := stone.packet.get_sub(i, TilePacket.K_SOIL)
	if _liquid_total(i) >= GridWater.LINE:
		_draw_water(x, y, px, py, n)
	_draw_gas(x, y, px, py)
	if n != 0:
		_draw_soil(x, y, px, py, n)
	_draw_fire(x, y, px, py)

## Overlay air pockets, per-segment level lines, and the tile grid (G).
func _draw_debug() -> void:
	# air-pocket states: sealed vs vented
	for y in stone.height:
		for x in stone.width:
			if water.is_air_passable(x, y):
				var c := Palette.DBG_SEALED if water.is_air_sealed(x, y) else Palette.DBG_OPEN
				image.fill_rect(Rect2i(x * TILE, y * TILE, TILE, TILE), c)
	
	# level lines: one per contiguous water segment per column
	for x in stone.width:
		var y := 0
		while y < stone.height:
			if water.get_water(x, y) >= GridWater.LINE:
				var t := y
				while t > 0 and water.get_water(x, t - 1) >= GridWater.LINE:
					t -= 1
				var lines := water.get_water(x, t) >> 4
				image.fill_rect(Rect2i(x * TILE, t * TILE + TILE - lines, TILE, 1), Palette.LEVEL_DBG)
				while y < stone.height and water.get_water(x, y) >= GridWater.LINE:
					y += 1
			else:
				y += 1
				
	# flow arrows: tail from tile center, direction of dominant arrival, length ~ strength
	for y in stone.height:
		for x in stone.width:
			var mag := water.get_flow_mag(x, y)
			if mag <= 0:
				continue
			var d := water.get_flow_dir(x, y)
			var cx := x * TILE + (TILE >> 1)
			var cy := y * TILE + (TILE >> 1)
			var ln := clampi(2 + (mag >> 6), 2, 6)
			for s in ln + 1:
				image.set_pixel(cx + GridWater.FLOW_DX[d] * s, cy + GridWater.FLOW_DY[d] * s, Palette.FLOW_DBG)
				
	# solid flow arrows: subtile arrivals at 64 pool-units each, same style as water
	if sand != null:
		for y in stone.height:
			for x in stone.width:
				var mag := sand.get_flow_mag(x, y)
				if mag <= 0:
					continue
				var d := sand.get_flow_dir(x, y)
				var cx := x * TILE + (TILE >> 1)
				var cy := y * TILE + (TILE >> 1)
				var ln := clampi(2 + (mag >> 6), 2, 6)
				for s in ln + 1:
					image.set_pixel(cx + GridWater.FLOW_DX[d] * s, cy + GridWater.FLOW_DY[d] * s, Palette.SOIL_FLOW_DBG)
	
	# the tile grid
	var wpx := stone.width * TILE
	var hpx := stone.height * TILE
	for x in range(0, wpx, TILE):
		image.fill_rect(Rect2i(x, 0, 1, hpx), Palette.GRID)
	for y in range(0, hpx, TILE):
		image.fill_rect(Rect2i(0, y, wpx, 1), Palette.GRID)

## Draw the hover cursor as a tile outline.
func _draw_cursor() -> void:
	var px := hover.x * TILE
	var py := hover.y * TILE
	image.fill_rect(Rect2i(px, py, TILE, 1), Palette.CURSOR)
	image.fill_rect(Rect2i(px, py + TILE - 1, TILE, 1), Palette.CURSOR)
	image.fill_rect(Rect2i(px, py, 1, TILE), Palette.CURSOR)
	image.fill_rect(Rect2i(px + TILE - 1, py, 1, TILE), Palette.CURSOR)

## Waterfall streaks: downward flow at mag >= FLOW_STREAK with dir DOWN draws hashed vertical streaks keyed on (tile, tick_count) — hash-based, never the sim PRNG (world §1). Returns true when streaks were drawn; the caller then draws no fill or crest -- falling water is streaks, not pooled lines.
func _draw_flow(x: int, y: int, px: int, py: int) -> bool:
	if water.get_flow_mag(x, y) < FLOW_STREAK:
		return false
	if water.get_flow_dir(x, y) != GridWater.FlowDir.DOWN:
		return false
	var hsh := (x * 92837111 + y * 689287499 + water.tick_count * 283923481) & 0x7FFFFFFF
	var ln := 3 + ((hsh >> 14) % 3)
	var s1 := px + (hsh % TILE)
	var s2 := px + ((hsh >> 7) % TILE)
	var mat := MAT_SURFACE[_majority(stone.idx(x, y))]
	image.fill_rect(Rect2i(s1, py, 1, ln), mat)
	if s2 != s1:
		image.fill_rect(Rect2i(s2, py, 1, ln), mat)
	return true

## Loose soil: one 8x8 quad per set nibble bit, light lip on subtiles with no soil directly above, damp darkening from the top of the occupied region (8 damp per pixel line -- the creeping front).
func _draw_soil(x: int, y: int, px: int, py: int, n: int) -> void:
	var n_up := 0
	if y > 0:
		n_up = stone.packet.get_sub(stone.idx(x, y - 1), TilePacket.K_SOIL)
	for c in SUB_QUADS:
		if (n & c[0]) == 0:
			continue
		image.fill_rect(Rect2i(px + c[1], py + c[2], 8, 8), Palette.SOIL)
		var covered := false
		if c[0] == GridSand.BL:
			covered = (n & GridSand.TL) != 0
		elif c[0] == GridSand.BR:
			covered = (n & GridSand.TR) != 0
		elif y > 0:
			var want := GridSand.BL if c[0] == GridSand.TL else GridSand.BR
			covered = (n_up & want) != 0
		if not covered:
			image.fill_rect(Rect2i(px + c[1], py + c[2], 8, 1), Palette.SOIL_LIP)
	var d := stone.packet.get_damp(stone.idx(x, y))
	if d > 0:
		# lines from the top of the occupied region: a bottom-only tile darkens from its own top, so shallow stacks still show a level
		var band_top := py if (n & TOP_MASK) != 0 else py + 8
		var band_bot := band_top + (d >> 3)
		for c in SUB_QUADS:
			if (n & c[0]) == 0:
				continue
			var y0 := maxi(py + c[2], band_top)
			var y1 := mini(py + c[2] + 8, band_bot)
			if y1 > y0:
				image.fill_rect(Rect2i(px + c[1], y0, 8, y1 - y0), Palette.SOIL_WET)

## Waterline lift over the tile's own soil subtiles: a squeezed pool reads higher on the fill. v = raw lines (units >> 4), n = soil nibble; returns the drawn line count, clamped to 15.
func _lifted_lines(v: int, n: int) -> int:
	var bottom := TilePacket.POPCOUNT[n & BOTTOM_MASK]
	var top := TilePacket.POPCOUNT[n & TOP_MASK]
	var shown := v
	if bottom == 2:
		if top == 0:
			shown = v + 4   # 2b: both bottom slots -- flat lift
		else:
			shown = mini(2 * v + 4, v + 6)   # 2c: the 2b lift, plus the original lines doubled, cap +6
	elif bottom == 1:
		var cap := 2
		if top > 0:
			cap = 4   # 2d widens 2a's cap when a top slot is also filled
		shown = mini(2 * v, v + cap)
	return mini(shown, 15)

## Draw one tile's liquids (the gases drew first, top-down; liquids render over gas by ruling): waterfall streaks replace the fill; a tile covered by liquid above fills its full height stacked by share; the surface tile fills by the subtile-lifted line count, stacked densest from the bottom, crest on the topmost material.
func _draw_water(x: int, y: int, px: int, py: int, n: int) -> void:
	if _draw_flow(x, y, px, py):
		return   # falling liquid: streaks stand in for the lines
	var i := stone.idx(x, y)
	var liq := _liquid_total(i)
	if liq < GridWater.LINE:
		return
	var covered := y > 0 and _liquid_total(stone.idx(x, y - 1)) >= GridWater.LINE
	var lines_total := _lifted_lines(liq >> 4, n) if not covered else TILE
	var deficit := lines_total
	for m in LIQ_DRAW:
		@warning_ignore("integer_division")
		deficit -= lines_total * stone.packet.get_pool(i, m) / liq
	var ycur := py + TILE
	var top_m := -1
	for k in LIQ_DRAW.size():
		var m: int = LIQ_DRAW[k]
		var units := stone.packet.get_pool(i, m)
		if units == 0:
			continue
		@warning_ignore("integer_division")
		var lm := lines_total * units / liq
		if top_m < 0:
			lm += deficit   # the densest material present absorbs the partition remainder
		ycur -= lm
		image.fill_rect(Rect2i(px, ycur, TILE, lm), MAT_COLORS[m])
		top_m = m
	if not covered and top_m >= 0:
		image.fill_rect(Rect2i(px, ycur, TILE, 1), MAT_SURFACE[top_m])

## Bind the solid field for its flow export; scenes without one skip the arrows.
func bind_sand(p_sand: GridSand) -> void:
	sand = p_sand

## Majority liquid at tile i -- the streak color's proxy (ties and empties read as water).
func _majority(i: int) -> int:
	var best := TilePacket.Mat.WATER
	var best_v: int = stone.packet.get_pool(i, best)
	for m in range(1, TilePacket.MAT_COUNT):
		var v := stone.packet.get_pool(i, m)
		if v > best_v:
			best = m as TilePacket.Mat
			best_v = v
	return best

## Gases draw top-down, eight units per line: checker dither from the tile's top to a full tile at 128, then one solid line per further eight (ceil) until the tile reads fully solid at 255 -- half liquid density, sub-eight films draw nothing. Amount and ratio are separate reads: the row count comes from the tile's TOTAL gas, and the rows split across the gases by share, lightest band on top (the liquid stack partition, mirrored).
func _draw_gas(x: int, y: int, px: int, py: int) -> void:
	var i := stone.idx(x, y)
	var total := 0
	for k in GAS_DRAW.size():
		total += stone.packet.get_pool(i, GAS_DRAW[k])
	if total < 8:
		return
	var rows_total := mini(total >> 3, TILE)
	var solid := clampi((total - 121) >> 3, 0, TILE)
	var deficit := rows_total
	for k in GAS_DRAW.size():
		@warning_ignore("integer_division")
		deficit -= rows_total * stone.packet.get_pool(i, GAS_DRAW[k]) / total
	var rcur := 0
	for k in range(GAS_DRAW.size() - 1, -1, -1):   # lightest first: its band starts at the tile's top
		var m: int = GAS_DRAW[k]
		var units := stone.packet.get_pool(i, m)
		if units == 0:
			continue
		@warning_ignore("integer_division")
		var rm := rows_total * units / total
		if rcur == 0:
			rm += deficit   # the lightest absorbs the partition remainder -- the densest's job in _draw_water, mirrored
		var col: Color = MAT_COLORS[m]
		var solid_h := mini(rm, maxi(0, solid - rcur))
		if solid_h > 0:
			image.fill_rect(Rect2i(px, py + rcur, TILE, solid_h), col)
		for r in range(rcur + solid_h, rcur + rm):
			var off := r & 1
			for xx in range(off, TILE, 2):
				image.set_pixel(px + xx, py + r, col)
		rcur += rm

## Liquid units at tile i -- the pool minus the two gases; lines, crests, and the covered check all read this, never pool_total.
func _liquid_total(i: int) -> int:
	return stone.packet.pool_total(i) - stone.packet.get_pool(i, TilePacket.Mat.SMOKE) - stone.packet.get_pool(i, TilePacket.Mat.STEAM)

## Fire bits draw as 8x8 ember quads on the fuel tile plus dancing licks -- one per bit, in the bottom subtile row of the non-solid tile above, hash-keyed on (tile, tick, bit) so every flame tongues on its own phase; never the sim PRNG (world §1). The lick is pure render: flame is picture, air is rules.
func _draw_fire(x: int, y: int, px: int, py: int) -> void:
	var f := stone.packet.get_fire(stone.idx(x, y))
	if f == 0:
		return
	var lick_y := py - TILE + 8   # the bottom subtile row of the tile above: one subtile of flame, no more
	var lick_ok := y > 0 and not stone.is_solid(x, y - 1)
	var b := 0
	for c in SUB_QUADS:
		if (f & c[0]) == 0:
			continue
		var hsh := (x * 92837111 + y * 689287499 + water.tick_count * 283923481 + b * 40503) & 0x7FFFFFFF
		var frame := hsh % 3
		var col := Palette.FIRE_1 if frame == 0 else (Palette.FIRE_2 if frame == 1 else Palette.FIRE_3)
		image.fill_rect(Rect2i(px + c[1], py + c[2], 8, 8), col)
		if lick_ok:
			var tx: int = px + c[1] + 2 + ((hsh >> 8) % 4)
			var th := 5 + ((hsh >> 16) % 4)
			image.fill_rect(Rect2i(px + c[1], lick_y, 8, 8), Palette.FIRE_1)
			image.fill_rect(Rect2i(tx, lick_y + 8 - th, 2, th), Palette.FIRE_2)
			image.set_pixel(tx, lick_y + 8 - th, Palette.FIRE_3)
		b += 1
