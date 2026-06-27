extends RefCounted
## Shared reporter + SceneTree access for the split test suites (see test/suites/).
## The single-file runner used to keep _passed/_failed/_suite and the assert/helpers
## as members of the SceneTree; that state moved here so each suite can stay its own
## small file. Inject the running SceneTree (`t`) so suites add nodes, await frames,
## and query groups exactly as before. See docs/guidelines/testing.md.

var tree: SceneTree
var passed := 0
var failed := 0
var suite := ""


func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree


## Record one assertion under the current `suite` label.
func ok(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("  ok   [%s] %s" % [suite, message])
	else:
		failed += 1
		printerr("  FAIL [%s] %s" % [suite, message])


## The scene root to parent test nodes under (was get_root()).
func root() -> Node:
	return tree.root


## Await one processed frame so a just-added node's _ready() runs (was `process_frame`).
func frame() -> Signal:
	return tree.process_frame


func nodes_in_group(group: String) -> Array:
	return tree.get_nodes_in_group(group)


## Step the spawner until it has dripped in `target` imps (each _process spawns at
## most one, on the wave's interval).
func pump_spawn(sp: Node, target: int) -> void:
	for i in 500:
		if tree.get_nodes_in_group("imps").size() >= target:
			return
		sp._process(0.2)


## Sort a cell array by (row, col) so set-equality can use ==.
func sorted_cells(cells: Array) -> Array:
	var out: Array = cells.duplicate()
	out.sort_custom(func(a, b): return (a.y < b.y) or (a.y == b.y and a.x < b.x))
	return out
