## The structure engine (world.md §3, the bedrock lab): authored membership over
## stone_s and wood_s subtile cells -- the editor's fuse brush writes, the sim destroys
## and never creates; a cut re-partitions (runs of >=2 stay structures, singletons revert loose).

class_name GridStructures
extends RefCounted

const N4X: Array[int] = [0, 1, 0, -1]   # fixed compass order -- derived passes never roll the PRNG (world §0)
const N4Y: Array[int] = [-1, 0, 1, 0]

var stone: GridStone
var pk: TilePacket
var width: int
var height: int

var _visited := PackedByteArray()   # scratch, expanded-grid sized, filled per repartition

## Size the field and bind the packet via the stone facade; membership holds no matter of its own.
func _init(w: int, h: int, terrain: GridStone) -> void:
	width = w
	height = h
	stone = terrain
	pk = terrain.packet
	_visited.resize(w * 2 * h * 2)

## Reset: zero the membership column through the packet's single writer. (Clear/reset path.)
func clear() -> void:
	for i in width * height:
		pk.set_struct(i, 0)

## The fuse brush at tile (x, y): paint membership onto every stone/wood cell present, then re-partition -- a lone fused cell is a singleton and reverts loose, so fusing isolated matter does nothing. True when the tile gained membership.
func fuse(x: int, y: int) -> bool:
	if not stone.in_bounds(x, y):
		return false
	var i := stone.idx(x, y)
	var n: int = pk.struct_s[i] | pk.get_sub(i, TilePacket.K_STONE) | pk.get_sub(i, TilePacket.K_WOOD)
	if n == pk.struct_s[i]:
		return false
	pk.set_struct(i, n)
	repartition_around(x, y)
	return true

## Re-partition every membership component seeded in the 3×3 tile neighborhood around a cut: each piece floods whole at subtile resolution -- orthogonal steps only, fixed compass order -- and a piece of one cell loses its membership (the loose rules take it from there).
func repartition_around(x: int, y: int) -> void:
	_visited.fill(0)
	for ty in range(maxi(0, y - 1), mini(height - 1, y + 1) + 1):
		for tx in range(maxi(0, x - 1), mini(width - 1, x + 1) + 1):
			var n: int = pk.struct_s[stone.idx(tx, ty)]
			for c in 4:
				if (n & (1 << c)) != 0:
					_flood_piece(tx * 2 + (c & 1), ty * 2 + (c >> 1))

## Flood one membership component whole from subtile cell (cx, cy); a singleton piece drops its bit -- the cut rule's teeth.
func _flood_piece(cx: int, cy: int) -> void:
	var w2 := width * 2
	var start := cy * w2 + cx
	if _visited[start] != 0:
		return
	var cells := PackedInt32Array()
	var stack := PackedInt32Array()
	stack.push_back(start)
	_visited[start] = 1
	while not stack.is_empty():
		var cur: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		cells.push_back(cur)
		@warning_ignore("integer_division")
		var x := cur % w2
		@warning_ignore("integer_division")
		var y := cur / w2
		for k in 4:
			var nx := x + N4X[k]
			var ny := y + N4Y[k]
			if nx < 0 or ny < 0 or nx >= w2 or ny >= height * 2:
				continue
			var n := ny * w2 + nx
			if _visited[n] != 0:
				continue
			if not _is_member(nx, ny):
				continue
			_visited[n] = 1
			stack.push_back(n)
	if cells.size() == 1:
		var only: int = cells[0]
		@warning_ignore("integer_division")
		var ti := (only / w2 >> 1) * width + ((only % w2) >> 1)
		@warning_ignore("integer_division")
		var bit := 1 << (((only / w2) & 1) * 2 + (only % w2 & 1))
		pk.set_struct(ti, pk.struct_s[ti] & ~bit)

## True when subtile cell (cx, cy) carries membership -- the invariant says membership rides matter, so the bit alone decides.
func _is_member(cx: int, cy: int) -> bool:
	@warning_ignore("integer_division")
	var i := (cy >> 1) * width + (cx >> 1)
	return (pk.struct_s[i] & (1 << ((cy & 1) * 2 + (cx & 1)))) != 0