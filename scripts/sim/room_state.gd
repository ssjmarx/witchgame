## A room's persistent census as value copies (world.md §8): fourteen packet
## columns, the ignition overlay, both sweep-parity counters. Derived state
## is never stored -- every engine rebuilds it at its tick head.

class_name RoomState
extends RefCounted

var cols: Array[PackedByteArray] = []
var ignition := PackedByteArray()
var water_ticks := 0
var sand_ticks := 0

## Byte-exact census comparison -- the restore proofs' one call.
func same_bytes(b: RoomState) -> bool:
	if water_ticks != b.water_ticks or sand_ticks != b.sand_ticks:
		return false
	if ignition != b.ignition:
		return false
	if cols.size() != b.cols.size():
		return false
	for i in cols.size():
		if cols[i] != b.cols[i]:
			return false
	return true
