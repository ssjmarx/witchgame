## Run ALL test suite tests: Godot ... --headless --path . -s res://scripts/testing/run_all.gd; echo $?
## Targeted mode: append -- and suite substrings to run a slice while iterating one
## module (e.g. ... run_all.gd -- occlusion fire); the full pass stays the gate.

extends SceneTree

const SUITES: Array[String] = [
	"res://scripts/testing/water_test.gd",
	"res://scripts/testing/test_soil.gd",
	"res://scripts/testing/test_oil.gd",
	"res://scripts/testing/test_fire.gd",
	"res://scripts/testing/test_bridge.gd",
	"res://scripts/testing/test_rooms.gd",
	"res://scripts/testing/test_palette.gd",
	"res://scripts/testing/test_debug.gd",
	"res://scripts/testing/test_structures.gd",
	"res://scripts/testing/test_occlusion.gd",
]

## One pass over the registry: fresh instance, suite, tally, free -- nodes outside the tree are not auto-freed (RefCounted engines are; the launcher is not).
func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var failed: Array[String] = []
	if _compile_gate():
		failed.append("compile gate")
	var pick := OS.get_cmdline_user_args()
	for path in SUITES:
		if not _picked(path, pick):
			continue   # targeted mode: run only the named suites (the full pass stays the gate)
		var script: GDScript = load(path)
		var lab: TestSandbox = script.new() as TestSandbox
		if lab == null:
			print("BAD REGISTRY ENTRY: %s" % path)
			failed.append(path)
			continue
		print("\n== %s" % path.get_file())
		var ok := lab.run_suite()
		print("== %s: %d pass, %d fail" % [path.get_file(), lab.suite_pass, lab.suite_fail])
		if not ok:
			failed.append(path)
		elif lab.suite_pass + lab.suite_fail == 0:
			print("VACUOUS SUITE: %s -- zero examples executed" % path.get_file())
			failed.append(path)
		lab.free()
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	for path in failed:
		print("FAILED SUITE: %s" % path)
	print("== REGRESSION: %d suites, %d failed (%.1f s)" % [SUITES.size(), failed.size(), secs])
	quit(1 if not failed.is_empty() else 0)

## True when the suite path matches a pick substring (empty picks run everything; tool flags like --regen are ignored).
func _picked(path: String, pick: PackedStringArray) -> bool:
	if pick.is_empty():
		return true
	for f in pick:
		if f != "--regen" and path.contains(f):
			return true
	return false

## Hard gate: every global class in the project must parse and instantiate before any suite runs -- a broken script (stale class cache, missing dependency) fails the regression here, loudly, instead of surfacing as vacuous passes downstream.
func _compile_gate() -> bool:
	var broken := false
	for gc in ProjectSettings.get_global_class_list():
		var s: GDScript = load(gc.path)
		if s == null or not s.can_instantiate():
			print("BROKEN GLOBAL CLASS: %s (%s)" % [gc.get("class"), gc.path])
			broken = true
	return broken
