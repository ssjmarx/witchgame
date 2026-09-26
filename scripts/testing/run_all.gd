## Run ALL test suite tests.  use with the following commands from the project root
## ~/.var/app/io.github.MakovWait.Godots/data/godot/app_userdata/Godots/versions/Godot_v4_7_2-stable_linux_x86_64/Godot_v4.7.2-stable_linux.x86_64 --headless --path . -s res://scripts/testing/run_all.gd
## echo $?

extends SceneTree

const SUITES: Array[String] = [
	"res://scripts/testing/water_test.gd",
	"res://scripts/testing/test_soil.gd",
	"res://scripts/testing/test_oil.gd",
	"res://scripts/testing/test_fire.gd",
]

## One pass over the registry: fresh instance, suite, tally, free -- nodes outside the tree are not auto-freed (RefCounted engines are; the launcher is not).
func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var failed: Array[String] = []
	for path in SUITES:
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
		lab.free()
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	for path in failed:
		print("FAILED SUITE: %s" % path)
	print("== REGRESSION: %d suites, %d failed (%.1f s)" % [SUITES.size(), failed.size(), secs])
	quit(1 if not failed.is_empty() else 0)
