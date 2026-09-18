## GDD §3: one Image the size of the map, regenerated at tick rate, pushed
## through an ImageTexture, drawn under actors. The sim state *is* the picture.
## Regenerating 240×240 RGBA ten times a second is nothing — keep it dumb.

class_name ElementRenderer
extends RefCounted

const TILE := 16  # pixels per tile

# the sim state this renderer draws
var stone: GridStone
var water: GridWater

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

## Paint one tile: beveled stone, or a water column with crest.
func _draw_tile(x: int, y: int) -> void:
	var px := x * TILE
	var py := y * TILE
	if stone.is_solid(x, y):
		image.fill_rect(Rect2i(px, py, TILE, TILE), Palette.STONE)
		image.fill_rect(Rect2i(px, py, TILE, 1), Palette.STONE_DARK)
		image.fill_rect(Rect2i(px, py, 1, TILE), Palette.STONE_DARK)
		image.set_pixel(px + 11, py + 11, Palette.STONE_DARK)
		return
	var w := water.get_water(x, y)
	if w < GridWater.LINE:
		return
	# a tile under visible water is solid blue; only the surface tile draws level and crest
	var covered: bool = y > 0 and water.get_water(x, y - 1) >= GridWater.LINE
	if covered:
		image.fill_rect(Rect2i(px, py, TILE, TILE), Palette.WATER)
		return
	var lines := w >> 4
	var top := py + TILE - lines
	image.fill_rect(Rect2i(px, top, TILE, lines), Palette.WATER)
	image.fill_rect(Rect2i(px, top, TILE, 1), Palette.WATER_SURFACE)

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
