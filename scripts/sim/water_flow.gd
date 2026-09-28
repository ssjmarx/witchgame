## The per-tick flow export (world.md §3): the arrival stamps the movers write
## and the renderer reads -- total magnitude, the largest single arrival, and
## its direction, rebuilt wholesale every tick. Derived opinion, never matter.

class_name WaterFlow
extends RefCounted

var mag := PackedByteArray()    # total units arriving per tile this tick
var best := PackedByteArray()   # largest single arrival (the dominant-dir source)
var dir := PackedByteArray()    # direction code of the dominant arrival

## Size the field; every tile starts unstamped.
func _init(w: int, h: int) -> void:
	mag.resize(w * h)
	best.resize(w * h)
	dir.resize(w * h)
	reset()

## The tick head: last tick's flow dies before any new move stamps.
func reset() -> void:
	mag.fill(0)
	best.fill(0)
	dir.fill(0)

## Register matter arriving at tile i (m units, d = the GridWater.FlowDir code): magnitudes sum, direction follows the largest single arrival (first stamp wins ties -- sweep order is fixed, so deterministic).
func stamp(i: int, d: int, m: int) -> void:
	if m <= 0:
		return
	mag[i] = mini(255, mag[i] + m)
	if m > best[i]:
		best[i] = m
		dir[i] = d
