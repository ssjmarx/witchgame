## The matter-to-physics half of the contact contract (world.md §5): the CA
## is truth, so colliders mirror the packet's solid map at subtile resolution,
## re-diffed every tick -- fire burns the floor out from under her.

class_name CollisionMirror
extends Node

var stone: GridStone
var pk: TilePacket
var width: int
var height: int

var _body: StaticBody2D
var _box: RectangleShape2D
var _cells: PackedByteArray
var _shapes: Array = []

## Bind the packet and size the cell mirror (w and h live on the packet).
func _init(p_stone: GridStone) -> void:
	stone = p_stone
	pk = p_stone.packet
	width = pk.w
	height = pk.h
	_cells.resize(width * 2 * height * 2)
	_shapes.resize(width * 2 * height * 2)

## Build the static body, the shared 8x8 box, and the boundary walls -- out-of-bounds is stone on three sides, open sky above (world.md §3).
func _ready() -> void:
	_body = StaticBody2D.new()
	add_child(_body)
	_box = RectangleShape2D.new()
	_box.size = Vector2(8.0, 8.0)
	_boundary_walls()

## One-time boundary colliders: left, right, and below the grid; the top stays open.
func _boundary_walls() -> void:
	var wpx := float(width * 16)
	var hpx := float(height * 16)
	var rects: Array[Rect2] = [Rect2(-16.0, -32.0, 16.0, hpx + 64.0), Rect2(wpx, -32.0, 16.0, hpx + 64.0), Rect2(0.0, hpx, wpx, 16.0)]
	for r in rects:
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = r.size
		shape.shape = box
		shape.position = r.position + r.size / 2.0
		_body.add_child(shape)

## One diff per tick: read the packet's solid map, patch colliders where it changed -- no signals (set_sub never emitted one, and wholesale restore wouldn't either).
func sync() -> void:
	var w2 := width * 2
	var h2 := height * 2
	for cy in h2:
		for cx in w2:
			var solid := _cell_solid(cx, cy)
			var i := cy * w2 + cx
			if solid == (_cells[i] != 0):
				continue
			_cells[i] = 1 if solid else 0
			if solid:
				var shape := CollisionShape2D.new()
				shape.shape = _box
				shape.position = Vector2(cx * 8.0 + 4.0, cy * 8.0 + 4.0)
				_body.add_child(shape)
				_shapes[i] = shape
			else:
				var old: CollisionShape2D = _shapes[i]
				if old != null:
					_body.remove_child(old)
					old.queue_free()
				_shapes[i] = null

## Is subtile cell (cx, cy) solid: full-solid terrain claims the whole tile; otherwise any subtile kind's bit claims the cell.
func _cell_solid(cx: int, cy: int) -> bool:
	var i := (cx >> 1) + (cy >> 1) * width
	if TilePacket.FULL_SOLID[pk.get_terrain(i)]:
		return true
	var n := pk.stone_s[i] | pk.soil_s[i] | pk.ice_s[i]
	var bit := 1 if (cy & 1) == 1 else 4   # bottom cells read BL/BR, top cells TL/TR
	if (cx & 1) == 1:
		bit <<= 1
	return (n & bit) != 0
