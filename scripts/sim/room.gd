## One CA domain (world.md §8): the engine quintet around one packet -- the
## bridge runs at the tick head -- plus the ruling, the per-room PRNG, and
## the snapshot/restore machinery. Unobserved rooms are never ticked.

class_name Room
extends RefCounted

var width: int
var height: int
var stone: GridStone
var water: GridWater
var sand: GridSand
var react: GridReactions
var bridge: ActorBridge
var rng := RandomNumberGenerator.new()

## Construct the quintet (idle engines are nearly free) and seed the room PRNG -- advanced only inside ticks, never from the frame.
func _init(p_w: int, p_h: int, p_seed: int) -> void:
	width = p_w
	height = p_h
	rng.seed = p_seed
	stone = GridStone.new(p_w, p_h)
	water = GridWater.new(p_w, p_h, stone)
	sand = GridSand.new(p_w, p_h, stone, water)
	react = GridReactions.new(p_w, p_h, stone)
	bridge = ActorBridge.new(p_w, p_h, stone, rng)

## One simulation tick in the engine ruling: the bridge at the head (actor exchanges, world.md §4), solids, liquids, reactions last.
func tick() -> void:
	bridge.tick()
	sand.tick()
	water.tick()
	react.tick()

## Copy the persistent census: fourteen packet columns, the ignition overlay, both sweep-parity counters.
func snapshot() -> RoomState:
	var s := RoomState.new()
	var pk := stone.packet
	for i in TilePacket.COL_COUNT:
		s.cols.append(pk.column(i).duplicate())
	s.ignition = react.snapshot_ignition()
	s.water_ticks = water.tick_count
	s.sand_ticks = sand.tick_count
	return s

## Write the census back, rebuild the maintained caches, end on the packet assert -- restore is sound outside the tick, not just before the next one.
func restore(s: RoomState) -> void:
	var pk := stone.packet
	for i in TilePacket.COL_COUNT:
		# duplicate on the way in as well: assignment aliases, and the stored state must survive
		pk.load_column(i, s.cols[i].duplicate())
	pk.clear_actor_claims()
	pk.rebuild_books()
	pk.rebuild_present()
	react.restore_ignition(s.ignition)
	water.tick_count = s.water_ticks
	sand.tick_count = s.sand_ticks
	pk.assert_all()

## Reset to a blank world through every owning clear path, terrain first (a cleared WOOD tile reads no damp cap); ends on the assert.
func reset() -> void:
	stone.clear()
	water.clear()
	sand.clear()
	var pk := stone.packet
	pk.clear_damp()
	pk.clear_fuel()
	pk.clear_fire()
	react.clear()
	pk.assert_all()
