## The thermal half of the actor state block (world.md §2): heat, wetness on
## the 1:1 lattice (water, steam, damp, wetness one unit since the retune),
## drip_mul, and tiles. The actor writes at frame speed; the bridge spends.

class_name ThermalBody
extends RefCounted

const HOT := 63                   # SACRED (world.md §13) -- smolder threshold
const HEAT_MAX := 64              # retuned at the witch lab: even maxed, she converts less than she displaces
const WETNESS_MAX := 64           # 1:1 with water since the retune -- the even lattice died with the 2:1
const DRIP_SCALE := 10            # drip_mul is per-10: 10 = full rate, 0 = holds

var heat := 0                     # leaves the body only as steam
var wetness := 0                  # 0..64, 1:1 with water since the retune
var drip_mul := DRIP_SCALE
var tiles: Array[Vector2i] = []   # overlapped tiles, kept fresh by the owner
var support := Vector2i.ZERO      # the underfoot tile (DRY, MELT)
var volume_nibbles := 0              # uniform per-tile default (0 displaces nothing)
var tile_volumes: Array[int] = []    # per-tile nibbles, parallel to tiles -- the hitbox profile; empty falls back to the uniform
var entered_from := Vector2i.ZERO    # the tile it entered its current tile from -- displacement's exit
var last_tiles: Array[Vector2i] = []   # the tiles the body just vacated -- the wake's pour targets, owner-written on tile change

## True at the SACRED threshold -- smolder and the tells key off this.
func is_hot() -> bool:
	return heat >= HOT

## True at saturation -- the carry window's ceiling.
func is_saturated() -> bool:
	return wetness >= WETNESS_MAX

## Per-tile volume in nibbles: the parallel array when the owner wrote one, else the uniform default.
func volume_at(k: int) -> int:
	if k < tile_volumes.size():
		return tile_volumes[k]
	return volume_nibbles
