## Static terrain layer. One byte per tile.
## Out-of-bounds reads as STONE: the test world is a sealed box. Only the water sim's air-pocket logic treats row 0 as open sky.
## Roadmap (GDD §2): WOOD, SOIL, BRAZIER, SPIKE, DOOR. DOOR is solid to CA flow even when open to bodies — that rule will live in is_solid().

class_name GridStone
extends RefCounted

signal terrain_changed(cells)  # Array[Vector2i]

# tile values; STONE is solid to water and air, AIR is passable
enum Terrain { AIR, STONE }

var width: int
var height: int
var cells: PackedByteArray

## Allocate the w×h cell grid, every tile air.
func _init(w: int, h: int) -> void:
	width = w
	height = h
	cells = PackedByteArray()
	cells.resize(w * h)

## Flat-array index of tile (x, y).
func idx(x: int, y: int) -> int:
	return y * width + x

## True if (x, y) lies inside the grid.
func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

## Terrain value at (x, y); out-of-bounds reads as STONE.
func get_terrain(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return Terrain.STONE
	return cells[y * width + x]

## True if the tile blocks flow (STONE, or outside the grid).
func is_solid(x: int, y: int) -> bool:
	return get_terrain(x, y) == Terrain.STONE

## Set terrain at (x, y); true (with emit) only when the value changed.
func set_terrain(x: int, y: int, t: int) -> bool:
	if not in_bounds(x, y):
		return false
	var i := y * width + x
	if cells[i] == t:
		return false
	cells[i] = t
	terrain_changed.emit([Vector2i(x, y)])
	return true

## Reset every tile to AIR.
func clear() -> void:
	cells.fill(Terrain.AIR)
