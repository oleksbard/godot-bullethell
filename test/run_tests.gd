extends SceneTree
## Zero-dependency headless test runner (mirrors the sibling godot-prototype).
##
## Run:  ./test/run_tests.sh
##  (or:  godot --headless --path . --script res://test/run_tests.gd)
##
## Exits 0 if all checks pass, 1 otherwise — CI-friendly. Pure logic runs
## synchronously; node behaviour needs the node in the tree + `await process_frame`
## so `_ready()` fires. See docs/guidelines/testing.md.

const IslandShape := preload("res://src/lib/island_shape.gd")
const MarineScript := preload("res://src/marine/marine.gd")

var _passed := 0
var _failed := 0
var _suite := ""


func _initialize() -> void:
	print("── running tests ──")
	_test_island_shape()
	_test_marine_clamp()
	await _test_marine_model()
	print("──")
	print("%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _test_island_shape() -> void:
	_suite = "IslandShape"
	var in_bounds := true
	for i in 360:
		var r := IslandShape.radius(deg_to_rad(float(i)))
		if r < IslandShape.BASE * 0.6 or r > IslandShape.BASE * 1.4:
			in_bounds = false
	_ok(in_bounds, "radius() stays within [0.6, 1.4] * BASE for all angles")
	_ok(is_equal_approx(IslandShape.radius(0.5), IslandShape.radius(0.5 + TAU)),
		"radius() is periodic over TAU")


func _test_marine_clamp() -> void:
	_suite = "Marine.clamp"
	var m: Node3D = MarineScript.new()       # not added to tree: _ready/rig not needed
	m.position = Vector3(50.0, 0.0, 30.0)    # far outside the island
	m._clamp_to_island()
	var d := Vector2(m.position.x, m.position.z).length()
	var ang := atan2(m.position.z, m.position.x)
	var max_r: float = IslandShape.radius(ang) - MarineScript.EDGE_MARGIN
	_ok(d <= max_r + 0.01, "clamp pulls an outside point onto the island")

	var inside := Vector3(1.0, 0.0, 1.0)
	m.position = inside
	m._clamp_to_island()
	_ok(m.position.is_equal_approx(inside), "clamp leaves an inside point untouched")
	m.free()


func _test_marine_model() -> void:
	_suite = "Marine.model"
	var m: Node3D = MarineScript.new()
	get_root().add_child(m)
	await process_frame                      # _ready() instances the glb + finds bones

	_ok(m._skel != null, "instances a Skeleton3D from marine_01.glb")
	_ok(m._b_lup != -1 and m._b_rup != -1 and m._b_larm != -1 and m._b_rarm != -1,
		"resolves the walk bones (LeftUpLeg/RightUpLeg/LeftArm/RightArm)")
	m.free()


func _ok(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("  ok   [%s] %s" % [_suite, message])
	else:
		_failed += 1
		printerr("  FAIL [%s] %s" % [_suite, message])
