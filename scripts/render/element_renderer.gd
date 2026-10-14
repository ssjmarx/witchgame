## world.md §9: one Image the size of the map, regenerated at tick rate, pushed
## through an ImageTexture, drawn under actors. The sim state *is* the picture.
## Regenerating 240×240 RGBA ten times a second is nothing — keep it dumb.

class_name ElementRenderer
extends RefCounted

const TILE := 16  # pixels per tile
const SUB_QUADS: Array = [[GridSand.TL, 0, 0], [GridSand.TR, 8, 0], [GridSand.BL, 0, 8], [GridSand.BR, 8, 8]]
const BOTTOM_MASK := GridSand.BL | GridSand.BR  # the two lower subtile slots
const TOP_MASK := GridSand.TL | GridSand.TR      # the two upper subtile slots
const EDGE_X: Array[int] = [0, 1, 0, -1]   # the four edges of a subtile cell: top, right, bottom, left -- the neighbor cell across each
const EDGE_Y: Array[int] = [-1, 0, 1, 0]
const EDGE_R: Array = [[0, 0, 8, 1], [7, 0, 1, 8], [0, 7, 8, 1], [0, 0, 1, 8]]   # each edge's pixel rect within the cell
const EDGE_NAME: Array[String] = ["t", "r", "b", "l"]
const TileAtlas = preload("res://scripts/render/tile_atlas.gd")

# the sim state this renderer draws
var stone: GridStone
var water: GridWater
var sand: GridSand = null   # optional: bound by scenes that own a solid field
var fx: CaFx                 # the second painter: ambiance under, effects over (world §9)
var liquids: Liquids

var _base: Image
var _frame_ms := 0
var _atlases := {}   # kind name -> bank-colored atlas Image (the baked PNGs)
var _roles := {}     # kind name -> role name -> atlas rect, resolved once at build

# the picture: one map-sized image pushed through a texture
var image: Image
var texture: ImageTexture

# overlays
var debug := false          # G: air pockets + grid
var hover := Vector2i(-1, -1)
var hover_sub := Vector2i(-1, -1)   # the exact subtile cell under the mouse -- subtile-sized cursor, set by the editor
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
	_atlases = TileAtlas.new().load_atlases()
	_resolve_roles()

## Resolve every blitted role's atlas rect once -- string mashing never rides the frame loop.
func _resolve_roles() -> void:
	var steps := ["25", "50", "75", "full"]
	for kind in ["stone", "wood"]:
		var r := {}
		r["fill"] = TileAtlas.LAYOUT["%s_fill" % kind]
		for e in EDGE_NAME:
			r["lip_" + e] = TileAtlas.LAYOUT["%s_lip_%s" % [kind, e]]
			r["seam_" + e] = TileAtlas.LAYOUT["%s_seam_%s" % [kind, e]]
		_roles[kind] = r
	var sr := {}
	sr["fill"] = TileAtlas.LAYOUT["soil_fill"]
	sr["lip_t"] = TileAtlas.LAYOUT["soil_lip_t"]
	for d in 4:
		sr["damp_%d" % (d + 1)] = TileAtlas.LAYOUT["soil_damp_%s" % steps[d]]
	_roles["soil"] = sr
	for gas in ["smoke", "steam"]:
		var gr := {}
		for d in 4:
			gr["d_%d" % (d + 1)] = TileAtlas.LAYOUT["%s_%s" % [gas, steps[d]]]
		_roles[gas] = gr
	var fr := {}
	for f in 3:
		fr["ember_%d" % f] = TileAtlas.LAYOUT["fire_ember_%d" % f]
		fr["lick_%d" % f] = TileAtlas.LAYOUT["fire_lick_%d" % f]
	_roles["fire"] = fr
	for kind in ["water", "oil", "acid", "lava"]:
		var lr := {}
		for h in [2, 4, 6, 8]:
			lr["lev_%d" % h] = TileAtlas.LAYOUT["%s_lev_%d" % [kind, h]]
		for c in ["crest_2a", "crest_2b", "crest_4a", "crest_4b", "crest_6a", "crest_6b"]:
			lr[c] = TileAtlas.LAYOUT["%s_%s" % [kind, c]]
		for d in 4:
			lr["rain_%d" % (d + 1)] = TileAtlas.LAYOUT["%s_rain_%d" % [kind, d + 1]]
		_roles[kind] = lr

## Blit one atlas role onto the map at pixel (dx, dy) -- the atlas rect carries the tile or strip size.
func _blit(kind: String, role: String, dx: int, dy: int) -> void:
	var img: Image = _atlases.get(kind)
	if img == null:
		return
	image.blend_rect(img, _roles[kind][role], Vector2i(dx, dy))

## Quarter-step density for a 0-8 row fill: 0 none, then 1-4 by twos.
func _density(fill: int) -> int:
	if fill <= 0:
		return 0
	if fill <= 2:
		return 1
	if fill <= 4:
		return 2
	if fill <= 6:
		return 3
	return 4

## Repaint the tick base and recapture the desires: ambiance and solid terrain only. The dynamic layers paint per frame over a copy of this. Call on every state change -- tick, stroke, restore, overlay toggle.
func redraw() -> void:
	fx.under(image)
	for y in stone.height:
		for x in stone.width:
			var i := stone.idx(x, y)
			if stone.is_solid(x, y) or stone.packet.get_sub(i, TilePacket.K_STONE) != 0 or stone.packet.get_sub(i, TilePacket.K_WOOD) != 0:
				_draw_terrain(x, y)
	_base.blit_rect(image, Rect2i(0, 0, image.get_width(), image.get_height()), Vector2i.ZERO)

## The frame pass: advance the pose on the render clock, restore the tick base, then paint the dynamic layers -- liquids from the pose, gas, soil, and fire from the packet -- then the FX over-pass and overlays. Call from the owning scene's _process.
func frame() -> void:
	var now := Time.get_ticks_msec()
	@warning_ignore("unused_variable")
	var dt := clampi(now - _frame_ms, 0, 250)
	_frame_ms = now
	image.blit_rect(_base, Rect2i(0, 0, image.get_width(), image.get_height()), Vector2i.ZERO)
	for y in stone.height:
		for x in stone.width:
			var px := x * TILE
			var py := y * TILE
			liquids.paint(x, y, px, py, _blit)
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
	if hover_sub.x >= 0 and hover_sub.y >= 0:
		_draw_cursor_sub()
	elif hover.x >= 0 and hover.y >= 0:
		_draw_cursor()
	texture.update(image)

## Paint one tile's matter with the seam rule: each matter subtile blits its fill, and every edge reads its neighbor -- lit lips on exposure, dark seams against loose or foreign matter, and silence between two members (orthogonally adjacent members are one structure, world §3).
func _draw_terrain(x: int, y: int) -> void:
	var i := stone.idx(x, y)
	var s := stone.packet.struct_s[i]
	var sn: int = stone.packet.get_sub(i, TilePacket.K_STONE)
	var wn: int = stone.packet.get_sub(i, TilePacket.K_WOOD)
	for c in 4:
		var bit := 1 << c
		if (sn & bit) != 0:
			_cell_face(x, y, c, "stone", (s & bit) != 0)
		elif (wn & bit) != 0:
			_cell_face(x, y, c, "wood", (s & bit) != 0)

## One matter cell: the fill blit, then each of its four edges -- lip on exposure, seam against matter that is not this structure, silence between two members.
func _cell_face(x: int, y: int, c: int, kind: String, member: bool) -> void:
	var qx := x * TILE + (c & 1) * 8
	var qy := y * TILE + (1 - (c >> 1)) * 8
	_blit(kind, "fill", qx, qy)
	for e in 4:
		var nx: int = x * 2 + (c & 1) + EDGE_X[e]
		var ny: int = y * 2 + (1 - (c >> 1)) + EDGE_Y[e]
		if nx < 0 or ny < 0 or nx >= stone.width * 2 or ny >= stone.height * 2:
			_blit(kind, "lip_" + EDGE_NAME[e], qx + EDGE_R[e][0], qy + EDGE_R[e][1])   # the map edge: an exposed face
			continue
		var ni := (ny >> 1) * stone.width + (nx >> 1)
		var nbit := 1 << ((1 - (ny & 1)) * 2 + (nx & 1))
		var nmat: int = (stone.packet.get_sub(ni, TilePacket.K_STONE) | stone.packet.get_sub(ni, TilePacket.K_WOOD)) & nbit
		if nmat == 0:
			_blit(kind, "lip_" + EDGE_NAME[e], qx + EDGE_R[e][0], qy + EDGE_R[e][1])   # exposed: the lit lip
		elif member and (stone.packet.struct_s[ni] & nbit) != 0:
			pass   # two members, orthogonally adjacent: one structure, no line
		else:
			_blit(kind, "seam_" + EDGE_NAME[e], qx + EDGE_R[e][0], qy + EDGE_R[e][1])   # the seam: loose against structure, or structure against structure

## Overlay air pockets, per-segment level lines, and the tile grid (G).
func _draw_debug() -> void:
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

## The subtile cursor: an 8x8 bracket at the exact cell -- what you point at is what you paint (world §3 authoring).
func _draw_cursor_sub() -> void:
	var px := hover_sub.x * 8
	var py := hover_sub.y * 8
	image.fill_rect(Rect2i(px, py, 8, 1), Palette.DEBUG_CURSOR)
	image.fill_rect(Rect2i(px, py + 7, 8, 1), Palette.DEBUG_CURSOR)
	image.fill_rect(Rect2i(px, py, 1, 8), Palette.DEBUG_CURSOR)
	image.fill_rect(Rect2i(px + 7, py, 1, 8), Palette.DEBUG_CURSOR)

## Loose soil: one fill blit per set nibble bit, light lip where uncovered above, damp quantized to subtile bands from the top of the occupied region -- full bands then a quarter-step boundary (the tileset lab's coarsened creep front).
func _draw_soil(x: int, y: int, px: int, py: int, n: int) -> void:
	var n_up := 0
	if y > 0:
		n_up = stone.packet.get_sub(stone.idx(x, y - 1), TilePacket.K_SOIL)
	for c in SUB_QUADS:
		if (n & c[0]) == 0:
			continue
		_blit("soil", "fill", px + c[1], py + c[2])
		var covered := false
		if c[0] == GridSand.BL:
			covered = (n & GridSand.TL) != 0
		elif c[0] == GridSand.BR:
			covered = (n & GridSand.TR) != 0
		elif y > 0:
			var want := GridSand.BL if c[0] == GridSand.TL else GridSand.BR
			covered = (n_up & want) != 0
		if not covered:
			_blit("soil", "lip_t", px + c[1], py + c[2])
	var d := stone.packet.get_damp(stone.idx(x, y))
	if d <= 0:
		return
	var band_top := py if (n & TOP_MASK) != 0 else py + 8
	var rows := d >> 3
	for k in range((rows >> 3) + 1):
		var fill := 8 if (k + 1) * 8 <= rows else rows - k * 8
		var dens := _density(fill)
		if dens <= 0:
			break
		var ry := band_top + k * 8
		for c in SUB_QUADS:
			if (n & c[0]) != 0 and ry >= py + c[2] and ry < py + c[2] + 8:
				_blit("soil", "damp_%d" % dens, px + c[1], ry)

## Bind the solid field for its flow export; scenes without one skip the arrows.
func bind_sand(p_sand: GridSand) -> void:
	sand = p_sand

## Gases draw top-down, quantized to 8px subtile bands: smoke's band from the tile's top, steam's below it, and a boundary subtile where the two complementary dither phases mix by their fractional shares -- no blending, the DMG way. Row count from the tile's total gas, split by share; sub-eight films draw nothing.
func _draw_gas(x: int, y: int, px: int, py: int) -> void:
	var i := stone.idx(x, y)
	var smoke := stone.packet.get_pool(i, TilePacket.Mat.SMOKE)
	var steam := stone.packet.get_pool(i, TilePacket.Mat.STEAM)
	var total := smoke + steam
	if total < 8:
		return
	var rows := mini(total >> 3, TILE)
	@warning_ignore("integer_division")
	var smoke_rows := rows * smoke / total
	for s in 2:
		var top8 := s * 8
		var so: int = clampi(smoke_rows - top8, 0, 8)
		var se: int = clampi(rows - maxi(smoke_rows, top8), 0, 8)
		if so + se == 0:
			break
		# the pool is tile-granular: each band spans both subtile columns, the 8px dither repeating -- the intended coarsening
		if so > 0:
			_blit("smoke", "d_%d" % _density(so), px, py + top8)
			_blit("smoke", "d_%d" % _density(so), px + 8, py + top8)
		if se > 0:
			_blit("steam", "d_%d" % _density(se), px, py + top8)
			_blit("steam", "d_%d" % _density(se), px + 8, py + top8)

## Fire bits draw as ember tiles on the fuel cell plus licks -- one per bit, in the bottom subtile row of the non-solid tile above, hash-keyed on (tile, tick, bit) so every flame tongues on its own phase; never the sim PRNG (world §1). The lick is pure render: flame is picture, air is rules.
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
		_blit("fire", "ember_%d" % frame, px + c[1], py + c[2])
		if lick_ok:
			_blit("fire", "lick_%d" % frame, px + c[1], lick_y)
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
