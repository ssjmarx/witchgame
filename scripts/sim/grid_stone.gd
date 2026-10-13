## Static terrain layer — a facade over the room's TilePacket.
## The packet owns every column; this class owns the terrain RULES: the virtual
## boundary, capacity solidity, and the change signal.

class_name GridStone
extends RefCounted

signal terrain_changed(cells)  # Array[Vector2i]

# tile values since the retirement cut: AIR plus the fixtures; STONE, WOOD, and SOIL
# became matter (world.md §3). Mirrors TilePacket.T so existing callers don't change.
enum Terrain { AIR, BRAZIER, SPIKE, DOOR, DOOR_CLOSED }

var packet: TilePacket
var width: int
var height: int

## Allocate the w×h grid as a fresh TilePacket; every tile air.
func _init(w: int, h: int) -> void:
	width = w
	height = h
	packet = TilePacket.new(w, h)

## Flat-array index of tile (x, y).
func idx(x: int, y: int) -> int:
	return y * width + x

## True if (x, y) lies inside the grid.
func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

## Terrain value at (x, y); out-of-bounds reads AIR -- the virtual boundary lives in is_solid, not in a retired STONE kind.
func get_terrain(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return TilePacket.T.AIR
	return packet.get_terrain(idx(x, y))

## True if the tile blocks flow: fixture terrain or four solid subtiles -- capacity zero either way, so a chipped wall's notch admits water (world §3).
func is_solid(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return true
	return packet.solid_capacity(idx(x, y)) == 0

## Set terrain at (x, y); true (with emit) only when the value changed.
func set_terrain(x: int, y: int, t: int) -> bool:
	if not in_bounds(x, y):
		return false
	if packet.set_terrain(idx(x, y), t):
		terrain_changed.emit([Vector2i(x, y)])
		return true
	return false

## Reset every tile to AIR. Terrain only -- the pool columns are not ours.
func clear() -> void:
	for i in width * height:
		packet.set_terrain(i, Terrain.AIR)
