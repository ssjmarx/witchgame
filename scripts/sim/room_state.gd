## A room's persistent census as value copies (world.md §8): fifteen packet columns, the
## ignition overlay, the burn pool, the smother timer, both sweep-parity counters. Derived
## state is never stored -- every engine rebuilds it at its tick head.

class_name RoomState
extends RefCounted

var cols: Array[PackedByteArray] = []
var ignition := PackedByteArray()
var woodburn := PackedByteArray()
var starved := PackedByteArray()
var water_ticks := 0
var sand_ticks := 0

## Byte-exact census comparison -- the restore proofs' one call.
func same_bytes(b: RoomState) -> bool:
	if water_ticks != b.water_ticks or sand_ticks != b.sand_ticks:
		return false
	if ignition != b.ignition or woodburn != b.woodburn or starved != b.starved:
		return false
	if cols.size() != b.cols.size():
		return false
	for i in cols.size():
		if cols[i] != b.cols[i]:
			return false
	return true
