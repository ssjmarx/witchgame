## The debug-furniture engine (world.md §3, the editor lab): sources and
## sinks live at the tick head before the bridge -- dosing books through the
## pool with refused units un-made, drains take what arrives, open air eats gas.

class_name GridDebug
extends RefCounted

const SOURCE_DOSE := 16   # <tune> — units per tick a source emits (one scanline per tick)

var stone: GridStone
var pk: TilePacket
var water: GridWater
var width: int
var height: int

## Bind the packet via the stone facade and the water engine for flow stamps; furniture holds no matter of its own.
func _init(w: int, h: int, terrain: GridStone, p_water: GridWater) -> void:
	width = w
	height = h
	stone = terrain
	pk = terrain.packet
	water = p_water

## The furniture pass, one sweep over the column gated by has_debug: buried furniture is inert (seal a spring and you dam it), sources dose and stamp at the tick head (world §3), and nothing here touches the PRNG.
func tick() -> void:
	if not pk.has_debug():
		return
	for i in width * height:
		var d := pk.get_debug(i)
		if d == TilePacket.DebugTile.NONE or TilePacket.FULL_SOLID[pk.get_terrain(i)]:
			continue
		match d:
			TilePacket.DebugTile.WATER_SOURCE:
				_dose(i, TilePacket.Mat.WATER, GridWater.FlowDir.DOWN)
			TilePacket.DebugTile.DRAIN:
				for m in TilePacket.MAT_COUNT:
					pk.take_pool(i, m, 255)
			TilePacket.DebugTile.STEAM_VENT:
				_dose(i, TilePacket.Mat.STEAM, GridWater.FlowDir.UP)
			TilePacket.DebugTile.OPEN_AIR:
				pk.take_pool(i, TilePacket.Mat.SMOKE, 255)
				pk.take_pool(i, TilePacket.Mat.STEAM, 255)

## Dose one source tile: accepted units book through the pool and stamp the flow export in the feed's direction; refused units are un-made -- no debt, no buffer (the smoke precedent).
func _dose(i: int, m: int, dir: int) -> void:
	var got := pk.add_pool(i, m, SOURCE_DOSE)
	if got > 0:
		water.flow_stamp(i, dir, got)
