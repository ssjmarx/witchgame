## The chemical reaction engine -- the third system beside liquid and solid
## movement. Soak trades pool water for damp through the percolation-skip walk;
## the tag pass refreshes wet flags with hysteresis; the packet assert closes the tick (reactions run last).

class_name GridReactions
extends RefCounted

const W: int = TilePacket.Mat.WATER
const SOAK_MAX := 16   # soak-rate ceiling; floor division means 15 is the effective max while w tops at 255

var stone: GridStone
var pk: TilePacket
var width: int
var height: int

## Bind the packet via the stone facade; reactions hold no state of their own.
func _init(w: int, h: int, terrain: GridStone) -> void:
	width = w
	height = h
	stone = terrain
	pk = terrain.packet

## One tick: soak every water-bearing tile, refresh tags, assert the packet (reactions run last, so the end-of-tick assert is theirs).
func tick() -> void:
	_soak_pass()
	_tag_pass()
	pk.assert_all()

## Soak pass: each water-bearing tile drinks clampi(w/16, 1, 16) per tick into the first headroom down its column -- its own soil, else through saturated soil below. Water never soaks across air, water-only tiles, or solid terrain.
func _soak_pass() -> void:
	for i in width * height:
		var w := pk.get_pool(i, W)
		if w == 0:
			continue
		var d := _soak_target(i)
		if d < 0:
			continue
		var room := pk.damp_capacity(d) - pk.get_damp(d)
		var amt := mini(clampi(w >> 4, 1, SOAK_MAX), mini(room, w))
		if amt > 0:
			pk.take_pool(i, W, amt)
			pk.add_damp(d, amt)

## The walk: drink at the first headroom down the column from i, passing through saturated soil (the percolation skip). Stops at the bottom, solid terrain, or the first soil-less tile.
func _soak_target(i: int) -> int:
	if pk.get_damp(i) < pk.damp_capacity(i):
		return i
	var d := i
	while d < width * height - width:
		var below := d + width
		if TilePacket.FULL_SOLID[pk.get_terrain(below)]:
			return -1
		if TilePacket.POPCOUNT[pk.get_sub(below, TilePacket.K_SOIL)] == 0:
			return -1
		if pk.get_damp(below) < pk.damp_capacity(below):
			return below
		d = below
	return -1

## Refresh wet tags from damp: gain above 50% of capacity, lose below 30% -- hysteresis, so the tag is state that survives the band. Zero-capacity tiles never carry it.
func _tag_pass() -> void:
	for i in width * height:
		var cap := pk.damp_capacity(i)
		if cap == 0:
			pk.set_tag(i, TilePacket.TAG_WET, false)
			continue
		var d := pk.get_damp(i)
		if d * 2 > cap:
			pk.set_tag(i, TilePacket.TAG_WET, true)
		elif d * 10 < cap * 3:
			pk.set_tag(i, TilePacket.TAG_WET, false)
