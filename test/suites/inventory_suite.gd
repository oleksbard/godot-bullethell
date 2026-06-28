extends RefCounted
## Grid-inventory tests, split from run_tests.gd. `t` is the shared TestContext.

const TestContext := preload("res://test/test_context.gd")
const InventoryItemScript := preload("res://src/inventory/inventory_item.gd")
const InventoryGridScript := preload("res://src/inventory/inventory_grid.gd")
const InventoryScript := preload("res://src/inventory/inventory.gd")


func run(t: TestContext) -> void:
	_test_inventory_item(t)
	_test_inventory_grid(t)
	_test_grid_adjacency(t)
	_test_artifact_item(t)
	_test_inventory(t)


func _test_grid_adjacency(t: TestContext) -> void:
	t.suite = "InventoryGrid.adjacency"
	var g: Object = InventoryGridScript.rect(3, 3)
	var mk := func() -> Object:
		var it := InventoryItemScript.for_kind(InventoryItemScript.Kind.PISTOL)
		it.base_cells = [Vector2i(0, 0)]
		return it
	var a: Object = mk.call(); var b: Object = mk.call(); var c: Object = mk.call(); var d: Object = mk.call()
	g.place(a, Vector2i(0, 0)); g.place(b, Vector2i(1, 0)); g.place(c, Vector2i(2, 0)); g.place(d, Vector2i(1, 1))
	t.ok(g.adjacent_items(a) == [b], "A (corner) borders only B")
	var nb: Array = g.adjacent_items(b)
	t.ok(nb.size() == 3 and nb.has(a) and nb.has(c) and nb.has(d), "B borders A, C, D (4-neighbour)")
	var e: Object = mk.call(); g.place(e, Vector2i(2, 1))   # diagonal to B
	t.ok(not g.adjacent_items(b).has(e), "a diagonal neighbour does NOT count")
	t.ok(g.adjacent_items(mk.call()).is_empty(), "an unplaced item has no neighbours")


func _test_artifact_item(t: TestContext) -> void:
	t.suite = "InventoryItem.artifact"
	var it: Object = InventoryItemScript.for_kind(InventoryItemScript.Kind.RUNE_OF_WRATH)
	t.ok(it.is_artifact(), "for_kind(artifact) yields an ARTIFACT item")
	t.ok(it.display_name() == "Rune of Wrath", "name from the catalog")
	t.ok(it.cells().size() == 1, "artifact is 1x1")
	t.ok(it.buy_price() == 20, "artifact price = tier base_price (20)")
	t.ok(it.type_name() == "Artifact", "type tag is Artifact")
	t.ok(it.level() == 0 and it.power() == 0, "artifacts have no level or power chip")
	var effect_text: String = it.stats()[0][1]
	t.ok(it.stats().size() >= 1, "artifact tooltip lists its effect")
	t.ok(effect_text.contains("×") and not effect_text.contains("%"),
		"effect text is fully formatted, no leftover specifiers (got '%s')" % effect_text)


func _test_inventory_item(t: TestContext) -> void:
	t.suite = "InventoryItem"
	var p := InventoryItemScript.pistol()
	t.ok(p.kind == InventoryItemScript.Kind.PISTOL, "pistol() is a PISTOL")
	t.ok(t.sorted_cells(p.cells()) == t.sorted_cells([
		Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)]),
		"rot 0 is the base L (X./X./XX)")

	p.rot = 2
	t.ok(t.sorted_cells(p.cells()) == t.sorted_cells([
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2)]),
		"rot 2 (180) is the right-hand pistol (XX/.X/.X)")

	# All four rotations are 4 cells and distinct shapes.
	var shapes := {}
	for r in 4:
		p.rot = r
		t.ok(p.cells().size() == 4, "rot %d keeps 4 cells" % r)
		shapes[str(t.sorted_cells(p.cells()))] = true
	t.ok(shapes.size() == 4, "the four rotations are distinct (%d)" % shapes.size())

	# A catalog weapon flows through generically.
	var sg := InventoryItemScript.for_kind(InventoryItemScript.Kind.SAWED_OFF)
	t.ok(sg.display_name() == "Sawed-Off", "for_kind(SAWED_OFF) names itself from the catalog")
	t.ok(sg.cells().size() == 3, "sawed-off grid shape comes from the catalog (3 cells, vertical)")
	var labels: Array = []
	for row in sg.stats():
		labels.append(row[0])
	t.ok(labels.has("Pellets"), "a SPREAD weapon's stats include a Pellets row")
	t.ok(InventoryItemScript.pistol().display_name() == "Pistol", "pistol() still reads its name from the catalog")

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var rolled := InventoryItemScript.rolled_weapon(InventoryItemScript.Kind.SAWED_OFF, 8, 0.0, rng)
	t.ok(rolled.kind == InventoryItemScript.Kind.SAWED_OFF and rolled.item_level >= 1,
		"rolled_weapon rolls a leveled item of the given kind")


func _test_inventory_grid(t: TestContext) -> void:
	t.suite = "InventoryGrid"
	# The backpack shape: _OO_ / OOOO / OOOO / OOOO
	var cells: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2),
		Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)]
	var g := InventoryGridScript.from_cells(cells)

	var left := InventoryItemScript.pistol()           # rot 0 down the left column
	t.ok(g.fits(left, Vector2i(0, 1)), "left pistol fits at (0,1)")
	t.ok(not g.fits(left, Vector2i(0, 0)), "pistol at (0,0) hits the top-row hole -> rejected")
	t.ok(not g.fits(left, Vector2i(3, 1)), "pistol off the right edge -> rejected")

	g.place(left, Vector2i(0, 1))
	t.ok(g.item_at(Vector2i(0, 1)) == left, "place records occupancy")

	var right := InventoryItemScript.pistol()
	right.rot = 2                                       # 180° L down the right column
	t.ok(g.fits(right, Vector2i(2, 1)), "right pistol fits at (2,1) beside the left one")
	g.place(right, Vector2i(2, 1))
	t.ok(g.items_in_reading_order().size() == 2, "two distinct items placed")

	var extra := InventoryItemScript.pistol()
	t.ok(not g.fits(extra, Vector2i(0, 1)), "overlapping an existing item -> rejected")
	t.ok(g.fits(left, Vector2i(0, 1), left), "an item fits over its own cells (ignore=self)")

	g.remove(left)
	t.ok(g.item_at(Vector2i(0, 1)) == null, "remove clears occupancy")
	t.ok(g.items_in_reading_order().size() == 1, "one item left after remove")


func _test_inventory(t: TestContext) -> void:
	t.suite = "Inventory"
	var inv: Node = InventoryScript.build()
	t.ok(inv.backpack.items_in_reading_order().size() == 2, "starts with 2 items in the backpack")
	t.ok(inv.equipped_pistols().size() == 2, "both starting pistols are equipped")
	# Exact starting placement matches the spec layout (offset by BASE_OFFSET = (2,1)).
	t.ok(inv.backpack.item_at(Vector2i(2, 2)) != null and inv.backpack.item_at(Vector2i(3, 4)) != null,
		"left pistol occupies the left column + foot")
	t.ok(inv.backpack.item_at(Vector2i(4, 2)) != null and inv.backpack.item_at(Vector2i(5, 4)) != null,
		"right pistol occupies the right column + head")

	var changes := [0]
	inv.changed.connect(func(): changes[0] += 1)

	var left: Object = inv.equipped_pistols()[0]
	inv.pick_up(inv.backpack, left)
	t.ok(inv.equipped_pistols().size() == 1, "picking a pistol out of the backpack unequips it")
	t.ok(changes[0] == 1, "pick_up emits changed")

	t.ok(inv.drop(inv.stash, left, Vector2i(0, 0)), "the pistol drops into the stash")
	t.ok(inv.equipped_pistols().size() == 1, "a stashed pistol is still unequipped")
	t.ok(changes[0] == 2, "drop emits changed")

	t.ok(inv.equipped_guns().size() == inv.equipped_pistols().size(),
		"equipped_guns() returns the equipped weapons (alias parity)")

	inv.free()
