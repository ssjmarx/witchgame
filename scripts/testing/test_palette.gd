## The palette law's acceptance suite (world.md §9): the DB16 canon plus
## documented guests, tile banks of at most four and sprite banks of at most
## three, banks sorted dark to light -- law, machine-checked, not memory.

class_name TestPalette
extends TestSandbox

const PAL_PATH := "res://scripts/render/palette.gd"
const DB16: Array[String] = ["#140c1c", "#442434", "#30346d", "#4e4a4e", "#854c30", "#346524", "#d04648", "#757161", "#597dce", "#d27d2c", "#8595a1", "#6daa2c", "#d2aa99", "#6dc2ca", "#dad45e", "#deeed6"]

## The lab's example set: the palette proofs, in order.
func run_tests() -> void:
	_example("PT0  master is the DB16 canon, sixteen and unique", _pt0_master)
	_example("PT1  every tile bank draws from master+guest, at most four", _pt1_banks)
	_example("PT2  every sprite bank the same pool, at most three", _pt2_sprites)
	_example("PT3  banks sort dark to light -- index 0 is darkest", _pt3_luminance)

## PT0: MASTER equals the canonical DB16 hex for hex -- a master change is a law change and fails here by design.
func _pt0_master() -> String:
	if Palette.MASTER.size() != 16:
		return "master holds %d colors, the canon is 16" % Palette.MASTER.size()
	var seen := {}
	for k in Palette.MASTER.size():
		var c: Color = Palette.MASTER[k]
		if c != Color(DB16[k]):
			return "master[%d] is %s, the canon says %s" % [k, c.to_html(false), DB16[k]]
		if seen.has(c):
			return "master holds %s twice" % c.to_html(false)
		seen[c] = true
	return ""

## PT1: every BANK_* constant holds 1-4 colors from master+guest, found by reflection -- a new bank is checked the day it is typed.
func _pt1_banks() -> String:
	var consts := _pal_map()
	var pool := _pool()
	for key in consts:
		if not String(key).begins_with("BANK_"):
			continue
		var bank: Array = consts[key]
		if bank.size() < 1 or bank.size() > 4:
			return "%s holds %d colors, the ceiling is 4" % [key, bank.size()]
		for c in bank:
			if not pool.has(c):
				return "%s draws %s, outside master+guest" % [key, c.to_html(false)]
	return ""

## PT2: every SPRITE_* constant holds 1-3 colors from the same pool -- the witch's bank today, her sisters' tomorrow.
func _pt2_sprites() -> String:
	var consts := _pal_map()
	var pool := _pool()
	for key in consts:
		if not String(key).begins_with("SPRITE_"):
			continue
		var bank: Array = consts[key]
		if bank.size() < 1 or bank.size() > 3:
			return "%s holds %d colors, the ceiling is 3" % [key, bank.size()]
		for c in bank:
			if not pool.has(c):
				return "%s draws %s, outside master+guest" % [key, c.to_html(false)]
	return ""

## PT3: tile-bank luminance never decreases brightward -- index 0 darkest is the convention every renderer read trusts.
func _pt3_luminance() -> String:
	var consts := _pal_map()
	for key in consts:
		if not String(key).begins_with("BANK_"):
			continue
		var bank: Array = consts[key]
		var last := -1.0
		for c: Color in bank:
			var lum := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			if lum < last - 0.001:
				return "%s darkens after luminance %.3f -- banks run dark to light" % [key, last]
			last = lum
	return ""

## The lawful pool every bank draws from: master plus guests, compared by value.
func _pool() -> Array:
	var pool := Palette.MASTER.duplicate()
	pool.append_array(Palette.GUEST)
	return pool

## Palette's declared constants by reflection: the class name is a type to the analyzer, so the script resource is loaded and cast -- the cast forces the receiver to GDScript, the one shape every analyzer accepts.
func _pal_map() -> Dictionary:
	return (load(PAL_PATH) as GDScript).get_script_constant_map()
