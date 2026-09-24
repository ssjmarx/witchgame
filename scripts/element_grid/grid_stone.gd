## Static terrain layer — a facade over the room's TilePacket.
## The packet owns every column; this class owns the terrain RULES:
## out-of-bounds reads as STONE, solidity, and the change signal.

class_name GridStone
extends RefCounted

signal terrain_changed(cells)  # Array[Vector2i]

# tile values; STONE and WOOD are solid to water and air, AIR is passable.
# First three of TilePacket.T — kept as aliases so existing callers don't change.
enum Terrain { AIR, STONE, WOOD }

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

## Terrain value at (x, y); out-of-bounds reads as STONE.
func get_terrain(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return Terrain.STONE
	return packet.get_terrain(idx(x, y))

## True if the tile blocks flow (now checks for all solids).
func is_solid(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return true
	return TilePacket.FULL_SOLID[packet.get_terrain(idx(x, y))]

## Set terrain at (x, y); true (with emit) only when the value changed.
func set_terrain(x: int, y: int, t: int) -> bool:
	if not in_bounds(x, y):
		return false
	if packet.set_terrain(idx(x, y), t):
		terrain_changed.emit([Vector2i(x, y)])
		return true
	return false

## Reset every tile to AIR. Terrain only — the pool columns are not ours.
func clear() -> void:
	for i in width * height:
		packet.set_terrain(i, Terrain.AIR)
