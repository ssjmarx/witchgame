## The pool-geometry helpers (world.md §3): segment and column walks over the
## visible liquid, and rule five's incompressibility walk -- shared by the
## liquid cell pass, the seek-level machinery, and displacement.

class_name WaterPools
extends RefCounted

var width: int
var height: int
var stone: GridStone
var pk: TilePacket
var labels: WaterAnalyze
var flow: WaterFlow

## Bind the geometry, the packet, the label pass, and the flow field the deposits stamp.
func _init(w: int, h: int, terrain: GridStone, p_labels: WaterAnalyze, p_flow: WaterFlow) -> void:
	width = w
	height = h
	stone = terrain
	pk = terrain.packet
	labels = p_labels
	flow = p_flow

## Topmost row of the contiguous visible-material-m segment containing (x, y). Caller guarantees m >= LINE at (x, y); with no visible segment the walk returns y + 1 -- a sentinel row, not a coordinate.
func segment_top(x: int, y: int, m: int) -> int:
	var t := y
	while t >= 0 and pk.get_pool(pk.idx(x, t), m) >= GridWater.LINE:
		t -= 1
	return t + 1

## Topmost row of the contiguous visible-liquid segment (any material) containing (x, y). Caller guarantees pool_total >= LINE at (x, y); with no segment the walk returns y + 1 -- a sentinel row, never a coordinate (the segment_top contract).
func pool_top(x: int, y: int) -> int:
	var t := y
	while t >= 0 and pk.pool_total(pk.idx(x, t)) >= GridWater.LINE:
		t -= 1
	return t + 1

## Bottom-most row of the contiguous visible-liquid segment (any material) containing (x, y). Caller guarantees pool_total >= LINE at (x, y); the walk is bounded by the grid.
func pool_bottom(x: int, y: int) -> int:
	var b := y
	while b + 1 < height and pk.pool_total(pk.idx(x, b + 1)) >= GridWater.LINE:
		b += 1
	return b

## Escape-gated column walk: does some tile above (x, y) have pool headroom with air that reaches open sky? The entry gate for deficit landings; the escape map is the one-tick-stale opinion.
func headroom_above(x: int, y: int) -> bool:
	var yy := y - 1
	while yy >= 0:
		var i := pk.idx(x, yy)
		if TilePacket.FULL_SOLID[pk.get_terrain(i)]:
			return false
		if pk.pool_free(i) > 0 and labels.escape_at(i):
			return true
		yy -= 1
	return false

## Eject up to amount units of the lightest materials from tile i up its column, depositing at the first free escape-reachable tiles -- rule five's incompressibility walk, factored: the displacement pass and the lateral deposit share it. Returns units ejected; flow-stamped UP per deposit tile.
func eject_lightest_up(i: int, amount: int) -> int:
	var remaining := amount
	var p := pk.xy_of(i)
	var yy := p.y - 1
	while remaining > 0 and yy >= 0:
		var h := pk.idx(p.x, yy)
		if TilePacket.FULL_SOLID[pk.get_terrain(h)]:
			break
		var moved := 0
		if labels.escape_at(h):
			while remaining > 0 and pk.pool_free(h) > 0:
				var m := pk.lightest_mat(i)
				if m < 0:
					break
				var have := pk.get_pool(i, m)
				var room := pk.pool_free(h)
				var chunk := mini(remaining, mini(have, room))
				pk.take_pool(i, m, chunk)
				pk.add_pool(h, m, chunk)
				moved += chunk
				remaining -= chunk
		if moved > 0:
			flow.stamp(h, GridWater.FlowDir.UP, moved)
		yy -= 1
	return amount - remaining
