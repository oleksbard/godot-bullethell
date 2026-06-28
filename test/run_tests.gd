extends SceneTree
## Zero-dependency headless test runner (mirrors the sibling godot-prototype).
##
## The tests live in per-feature suites under test/suites/; this is just the entry
## point — it builds a shared TestContext and runs each suite. The reporter state and
## assert/tree helpers live in test/test_context.gd.
##
## Run:  ./test/run_tests.sh
##  (or:  godot --headless --path . --script res://test/run_tests.gd)
##
## Exits 0 if all checks pass, 1 otherwise — CI-friendly. Pure logic runs
## synchronously; node behaviour needs the node in the tree + `await t.frame()`
## so `_ready()` fires. See docs/guidelines/testing.md.

const TestContext := preload("res://test/test_context.gd")

const WorldSuite := preload("res://test/suites/world_suite.gd")
const InventorySuite := preload("res://test/suites/inventory_suite.gd")
const MarineSuite := preload("res://test/suites/marine_suite.gd")
const EnemiesSuite := preload("res://test/suites/enemies_suite.gd")
const WeaponsSuite := preload("res://test/suites/weapons_suite.gd")
const LootSuite := preload("res://test/suites/loot_suite.gd")
const UiSuite := preload("res://test/suites/ui_suite.gd")
const AudioSuite := preload("res://test/suites/audio_suite.gd")
const ExpansionSuite := preload("res://test/suites/expansion_suite.gd")


func _initialize() -> void:
	var t := TestContext.new(self)
	print("── running tests ──")
	WorldSuite.new().run(t)        # world + inventory suites are pure/synchronous
	InventorySuite.new().run(t)
	ExpansionSuite.new().run(t)     # pure/synchronous, like the inventory suite
	await MarineSuite.new().run(t) # the rest add nodes + await frames for _ready()
	await EnemiesSuite.new().run(t)
	await WeaponsSuite.new().run(t)
	await LootSuite.new().run(t)
	await UiSuite.new().run(t)
	await AudioSuite.new().run(t)
	print("──")
	print("%d passed, %d failed" % [t.passed, t.failed])
	quit(1 if t.failed > 0 else 0)
