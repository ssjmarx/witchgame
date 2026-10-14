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

# occlusion cell masks: the near-face unions read these (fixtures and the boundary fill them)
const CELLS_LEFT := GridSand.TL | GridSand.BL
const CELLS_RIGHT := GridSand.TR | GridSand.BR
const CELLS_TOP := GridSand.TL | GridSand.TR
const CELLS_BOTTOM := GridSand.BL | GridSand.BR

## The tile's contribution to a shared edge: the OR'd matter nibbles masked to the near face; fixtures and the virtual boundary read as the whole face filled.
func _face(x: int, y: int, mask: int) -> int:
	if not in_bounds(x, y):
		return mask
	var i := idx(x, y)
	if packet.get_terrain(i) != TilePacket.T.AIR:
		return mask
	return packet.occlusion_bits(i) & mask

## The horizontal edge between (x, y-1) and (x, y): open to vertical crossing unless the near sides seal it -- the upper tile's bottom row united with this tile's top row spans left AND right (world §3).
func edge_v_open(x: int, y: int) -> bool:
	if y <= 0:
		return false
	return not TilePacket.BLOCKS_V[_face(x, y - 1, GridSand.BL | GridSand.BR) | _face(x, y, GridSand.TL | GridSand.TR)]

## The vertical edge between (x-1, y) and (x, y): open to horizontal crossing unless the left tile's right column united with this tile's left column spans top AND bottom (world §3).
func edge_h_open(x: int, y: int) -> bool:
	if x <= 0:
		return false
	return not TilePacket.BLOCKS_H[_face(x - 1, y, GridSand.TR | GridSand.BR) | _face(x, y, GridSand.TL | GridSand.BL)]

## Interior test: may liquid inside (x, y) leave vertically (downward)? The tile's own pattern must leave an open through-column -- some left AND some right cell seals the interior path (world §3). The wetability clause: an open bottom exit cell whose row and column partners are solid still drains when liquid stands in the exterior tile beside it -- a lone notch entered from its side face drinks downward. Fixtures and the boundary never drain.
func drains_v(x: int, y: int) -> bool:
	return _drains_vertical(x, y, true)

## Interior test: may matter inside (x, y) leave vertically upward (gas rise, the seek lift)? The through-column test, with the wetability clause on the TOP exit cells -- liquid or gas escapes a lone top notch it can stand beside.
func drains_up(x: int, y: int) -> bool:
	return _drains_vertical(x, y, false)

## The shared vertical interior: the open-column test, then the wetability clause on the exit row (bottom when falling, top when rising) -- a blocked tile still passes through an open exit cell wetted from its exterior side (world §3).
func _drains_vertical(x: int, y: int, down: bool) -> bool:
	if not in_bounds(x, y) or packet.get_terrain(idx(x, y)) != TilePacket.T.AIR:
		return false
	var p := packet.occlusion_bits(idx(x, y))
	if not TilePacket.BLOCKS_V[p]:
		return true
	if down:
		if (p & GridSand.BL) == 0 and _wet_side(x - 1, y, GridSand.BR):
			return true
		if (p & GridSand.BR) == 0 and _wet_side(x + 1, y, GridSand.BL):
			return true
	else:
		if (p & GridSand.TL) == 0 and _wet_side(x - 1, y, GridSand.TR):
			return true
		if (p & GridSand.TR) == 0 and _wet_side(x + 1, y, GridSand.TL):
			return true
	return false

## Interior test: may liquid inside (x, y) leave horizontally toward dx? An open through-row -- some top AND some bottom cell seals it (world §3). The wetability clause is directional: only the exit face's cells count (rightward reads TR/BR, leftward TL/BL), each wetted from the exterior tile past it (TR/TL from above, BR/BL from below). Fixtures and the boundary never drain.
func drains_h(x: int, y: int, dx: int) -> bool:
	if not in_bounds(x, y) or packet.get_terrain(idx(x, y)) != TilePacket.T.AIR:
		return false
	var p := packet.occlusion_bits(idx(x, y))
	if not TilePacket.BLOCKS_H[p]:
		return true
	if dx > 0:
		if (p & GridSand.TR) == 0 and _wet_side(x, y - 1, GridSand.BR):
			return true
		if (p & GridSand.BR) == 0 and _wet_side(x, y + 1, GridSand.TR):
			return true
	else:
		if (p & GridSand.TL) == 0 and _wet_side(x, y - 1, GridSand.BL):
			return true
		if (p & GridSand.BL) == 0 and _wet_side(x, y + 1, GridSand.TL):
			return true
	return false

## Does tile (x, y) hold liquid in cell `cell`? The wetability source: open matter at the cell and real liquid in the pool (gases wet nothing) -- OC7's dry column and OC2's solid neighbor stay sealed (world §3).
func _wet_side(x: int, y: int, cell: int) -> bool:
	if not in_bounds(x, y) or packet.get_terrain(idx(x, y)) != TilePacket.T.AIR:
		return false
	var i := idx(x, y)
	if (packet.occlusion_bits(i) & cell) != 0:
		return false
	return packet.pool_total(i) - packet.get_pool(i, TilePacket.Mat.SMOKE) - packet.get_pool(i, TilePacket.Mat.STEAM) > 0

## Is corner cell c of (x, y) reachable through the tile's interior? The cell must be open and share a fully open row or column with a partner -- a diagonal pair's open cells never connect, so its corners are unreachable (world §3). Fixtures never reach.
func _corner_reachable(x: int, y: int, c: int) -> bool:
	if not in_bounds(x, y) or packet.get_terrain(idx(x, y)) != TilePacket.T.AIR:
		return false
	var p := packet.occlusion_bits(idx(x, y))
	if (p & c) != 0:
		return false
	var row := CELLS_BOTTOM if (c & CELLS_BOTTOM) != 0 else CELLS_TOP
	var col := CELLS_LEFT if (c & CELLS_LEFT) != 0 else CELLS_RIGHT
	return (p & row) == 0 or (p & col) == 0

## The diagonal crossing from (x, y) into (x + dx, y + dy): the corner law the sand pass obeys, at tile scale -- the source's own exit corner must be open AND reachable through the tile's interior, the side tile's corner beside it and the target's entry corner must each hold no solid cell; any one failed test seals the diagonal (world §3). Fixtures and the boundary read filled.
func blocks_diag(x: int, y: int, dx: int, dy: int) -> bool:
	var sx := GridSand.BL if dy > 0 else GridSand.TL
	if dx > 0:
		sx = GridSand.BR if dy > 0 else GridSand.TR
	var tx := GridSand.TR if dy > 0 else GridSand.BR
	if dx > 0:
		tx = GridSand.TL if dy > 0 else GridSand.BL
	var bx := GridSand.BR if dy > 0 else GridSand.TR
	if dx > 0:
		bx = GridSand.BL if dy > 0 else GridSand.TL
	# own corner, its interior reachability, the side corner (the corner rule), the entry corner
	if _face(x, y, sx) != 0 or not _corner_reachable(x, y, sx):
		return true
	return _face(x + dx, y + dy, tx) != 0 or _face(x + dx, y, bx) != 0

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
