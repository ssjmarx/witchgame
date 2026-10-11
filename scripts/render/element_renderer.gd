## world.md §9: one Image the size of the map, regenerated at tick rate, pushed
## through an ImageTexture, drawn under actors. The sim state *is* the picture.
## Regenerating 240×240 RGBA ten times a second is nothing — keep it dumb.

class_name ElementRenderer
extends RefCounted

const TILE := 16  # pixels per tile
const FALL_MIN := 16    # <tune> — downflow arrivals before a tile renders as falling (one line's worth)
const SUB_QUADS: Array = [[GridSand.TL, 0, 0], [GridSand.TR, 8, 0], [GridSand.BL, 0, 8], [GridSand.BR, 8, 8]]
const GAS_DRAW: Array[int] = [TilePacket.Mat.SMOKE, TilePacket.Mat.STEAM]   # density order; the band split walks it reversed -- the lightest gas takes the topmost rows
const BOTTOM_MASK := GridSand.BL | GridSand.BR  # the two lower subtile slots
const TOP_MASK := GridSand.TL | GridSand.TR      # the two upper subtile slots

# the sim state this renderer draws
var stone: GridStone
var water: GridWater
var sand: GridSand = null   # optional: bound by scenes that own a solid field
var fx: CaFx                 # the second painter: ambiance under, effects over (world §9)
var liquids: Liquids

var _base: Image
var _frame_ms := 0

# the picture: one map-sized image pushed through a texture
var image: Image
var texture: ImageTexture

# overlays
var debug := false          # G: air pockets + grid
var hover := Vector2i(-1, -1)
var furniture := false       # editor: draw debug-tile glyphs without the full G overlay

## Bind the sim pair, the room's seed for the FX domain, and create the map-sized image and texture.
func _init(terrain: GridStone, field: GridWater, p_seed := 0) -> void:
	stone = terrain
	water = field
	fx = CaFx.new(terrain, field, p_seed)
	image = Image.create(terrain.width * TILE, terrain.height * TILE, false, Image.FORMAT_RGBA8)
	texture = ImageTexture.create_from_image(image)
	liquids = Liquids.new(terrain, field)
	_base = Image.create(terrain.width * TILE, terrain.height * TILE, false, Image.FORMAT_RGBA8)

## Repaint the tick base and recapture the desires: ambiance and solid terrain only. The dynamic layers paint per frame over a copy of this. Call on every state change -- tick, stroke, restore, overlay toggle.
func redraw() -> void:
	liquids.capture()
	fx.under(image)
	for y in stone.height:
		for x in stone.width:
			if stone.is_solid(x, y):
				_draw_terrain(x, y)
	_base.blit_rect(image, Rect2i(0, 0, image.get_width(), image.get_height()), Vector2i.ZERO)

## The frame pass: advance the pose on the render clock, restore the tick base, then paint the dynamic layers -- liquids from the pose, gas, soil, and fire from the packet -- then the FX over-pass and overlays. Call from the owning scene's _process.
func frame() -> void:
	var now := Time.get_ticks_msec()
	var dt := clampi(now - _frame_ms, 0, 250)
	_frame_ms = now
	liquids.advance(dt)
	image.blit_rect(_base, Rect2i(0, 0, image.get_width(), image.get_height()), Vector2i.ZERO)
	for y in stone.height:
		for x in stone.width:
			var px := x * TILE
			var py := y * TILE
			liquids.paint(image, x, y, px, py)
			_draw_gas(x, y, px, py)
			var n := stone.packet.get_sub(stone.idx(x, y), TilePacket.K_SOIL)
			if n != 0:
				_draw_soil(x, y, px, py, n)
			_draw_fire(x, y, px, py)
	fx.over(image)
	if debug:
		_draw_debug()
	if debug or furniture:
		_draw_furniture()
	if hover.x >= 0 and hover.y >= 0:
		_draw_cursor()
	texture.update(image)

## Paint one solid tile: beveled stone or planked wood -- the terrain face the base layer keeps.
func _draw_terrain(x: int, y: int) -> void:
	var px := x * TILE
	var py := y * TILE
	var i := stone.idx(x, y)
	var wood := stone.packet.get_terrain(i) == TilePacket.T.WOOD
	var fill := Palette.BANK_WOOD[1] if wood else Palette.BANK_STONE[1]
	var dark := Palette.BANK_WOOD[0] if wood else Palette.BANK_STONE[0]
	image.fill_rect(Rect2i(px, py, TILE, TILE), fill)
	image.fill_rect(Rect2i(px, py, TILE, 1), dark)
	image.fill_rect(Rect2i(px, py, 1, TILE), dark)
	image.set_pixel(px + 11, py + 11, dark)
	if wood:
		image.fill_rect(Rect2i(px, py + 8, TILE, 1), dark)   # the plank seam -- minimal wood identity

## Overlay air pockets, per-segment level lines, and the tile grid (G).
func _draw_debug() -> void:
	# air-pocket states: sealed vs vented
	for y in stone.height:
		for x in stone.width:
			if water.is_air_passable(x, y):
				var c := Palette.DEBUG_SEALED if water.is_air_sealed(x, y) else Palette.DEBUG_OPEN
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
				image.fill_rect(Rect2i(x * TILE, t * TILE + TILE - lines, TILE, 1), Palette.DEBUG_LEVEL)
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
				image.set_pixel(cx + GridWater.FLOW_DX[d] * s, cy + GridWater.FLOW_DY[d] * s, Palette.DEBUG_FLOW)
				
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
					image.set_pixel(cx + GridWater.FLOW_DX[d] * s, cy + GridWater.FLOW_DY[d] * s, Palette.DEBUG_SOIL_FLOW)
	
	# the tile grid
	var wpx := stone.width * TILE
	var hpx := stone.height * TILE
	for x in range(0, wpx, TILE):
		image.fill_rect(Rect2i(x, 0, 1, hpx), Palette.DEBUG_GRID)
	for y in range(0, hpx, TILE):
		image.fill_rect(Rect2i(0, y, wpx, 1), Palette.DEBUG_GRID)

## Draw the hover cursor as a tile outline.
func _draw_cursor() -> void:
	var px := hover.x * TILE
	var py := hover.y * TILE
	image.fill_rect(Rect2i(px, py, TILE, 1), Palette.DEBUG_CURSOR)
	image.fill_rect(Rect2i(px, py + TILE - 1, TILE, 1), Palette.DEBUG_CURSOR)
	image.fill_rect(Rect2i(px, py, 1, TILE), Palette.DEBUG_CURSOR)
	image.fill_rect(Rect2i(px + TILE - 1, py, 1, TILE), Palette.DEBUG_CURSOR)

## Loose soil: one 8x8 quad per set nibble bit, light lip on subtiles with no soil directly above, damp darkening from the top of the occupied region (8 damp per pixel line -- the creeping front).
func _draw_soil(x: int, y: int, px: int, py: int, n: int) -> void:
	var n_up := 0
	if y > 0:
		n_up = stone.packet.get_sub(stone.idx(x, y - 1), TilePacket.K_SOIL)
	for c in SUB_QUADS:
		if (n & c[0]) == 0:
			continue
		image.fill_rect(Rect2i(px + c[1], py + c[2], 8, 8), Palette.BANK_SOIL[1])
		var covered := false
		if c[0] == GridSand.BL:
			covered = (n & GridSand.TL) != 0
		elif c[0] == GridSand.BR:
			covered = (n & GridSand.TR) != 0
		elif y > 0:
			var want := GridSand.BL if c[0] == GridSand.TL else GridSand.BR
			covered = (n_up & want) != 0
		if not covered:
			image.fill_rect(Rect2i(px + c[1], py + c[2], 8, 1), Palette.BANK_SOIL[2])
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
				image.fill_rect(Rect2i(px + c[1], y0, 8, y1 - y0), Palette.BANK_SOIL[0])

## Bind the solid field for its flow export; scenes without one skip the arrows.
func bind_sand(p_sand: GridSand) -> void:
	sand = p_sand

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
		var col: Color = Palette.MAT_FILL[m]
		var solid_h := mini(rm, maxi(0, solid - rcur))
		if solid_h > 0:
			image.fill_rect(Rect2i(px, py + rcur, TILE, solid_h), col)
		for r in range(rcur + solid_h, rcur + rm):
			var off := r & 1
			for xx in range(off, TILE, 2):
				image.set_pixel(px + xx, py + r, col)
		rcur += rm

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
		@warning_ignore("shadowed_variable")
		var frame := hsh % 3
		var col := Palette.BANK_FIRE[1] if frame == 0 else (Palette.BANK_FIRE[2] if frame == 1 else Palette.BANK_FIRE[3])
		image.fill_rect(Rect2i(px + c[1], py + c[2], 8, 8), col)
		if lick_ok:
			var tx: int = px + c[1] + 2 + ((hsh >> 8) % 4)
			var th := 5 + ((hsh >> 16) % 4)
			image.fill_rect(Rect2i(px + c[1], lick_y, 8, 8), Palette.BANK_FIRE[1])
			image.fill_rect(Rect2i(tx, lick_y + 8 - th, 2, th), Palette.BANK_FIRE[2])
			image.set_pixel(tx, lick_y + 8 - th, Palette.BANK_FIRE[3])
		b += 1

## Debug furniture glyphs: source spout, drain grate, steam vent, and the open-air brackets -- author furniture, drawn over everything, never part of the world picture (finished rooms keep furniture outside the play area).
func _draw_furniture() -> void:
	for y in stone.height:
		for x in stone.width:
			var d := stone.packet.get_debug(stone.idx(x, y))
			if d == TilePacket.DebugTile.NONE:
				continue
			var px := x * TILE
			var py := y * TILE
			match d:
				TilePacket.DebugTile.WATER_SOURCE:
					image.fill_rect(Rect2i(px + 2, py + 1, 12, 2), Palette.BANK_WATER[0])
					for k in 3:
						image.fill_rect(Rect2i(px + 3 + k * 4, py + 5 + (k % 2) * 2, 2, 3), Palette.BANK_WATER[2])
				TilePacket.DebugTile.DRAIN:
					for k in 3:
						image.fill_rect(Rect2i(px + 2, py + 5 + k * 3, 12, 1), Palette.BANK_WATER[0])
				TilePacket.DebugTile.STEAM_VENT:
					image.fill_rect(Rect2i(px + 2, py + 13, 12, 2), Palette.BANK_STEAM[0])
					for k in 3:
						image.fill_rect(Rect2i(px + 4 + k * 4, py + 8 - (k % 2) * 2, 2, 3), Palette.BANK_STEAM[1])
				TilePacket.DebugTile.OPEN_AIR:
					var c := Palette.DEBUG_LEVEL
					image.fill_rect(Rect2i(px + 3, py + 3, 3, 1), c)
					image.fill_rect(Rect2i(px + 3, py + 4, 1, 2), c)
					image.fill_rect(Rect2i(px + 10, py + 3, 3, 1), c)
					image.fill_rect(Rect2i(px + 12, py + 4, 1, 2), c)
					image.fill_rect(Rect2i(px + 3, py + 12, 3, 1), c)
					image.fill_rect(Rect2i(px + 3, py + 10, 1, 2), c)
					image.fill_rect(Rect2i(px + 10, py + 12, 3, 1), c)
					image.fill_rect(Rect2i(px + 12, py + 10, 1, 2), c)
