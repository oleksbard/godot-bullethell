extends RefCounted
## Upgradable-inventory tests: expansion catalog defs, the expansion InventoryItem,
## the two-layer ExpandableGrid, and Inventory pricing. Pure/synchronous. `t` is the
## shared TestContext.

const TestContext := preload("res://test/test_context.gd")
const WeaponCatalogScript := preload("res://src/weapons/weapon_catalog.gd")
const WeaponDefScript := preload("res://src/weapons/weapon_def.gd")
const InventoryItemScript := preload("res://src/inventory/inventory_item.gd")
const ExpandableGridScript := preload("res://src/inventory/expandable_grid.gd")
const InventoryScript := preload("res://src/inventory/inventory.gd")
# Later tasks add their own preloads (ExpandableGrid, Inventory) when
# their test functions need them — a suite that preloads a not-yet-created script
# fails to load and breaks the whole run, so add each preload in the task that uses it.


func run(t: TestContext) -> void:
	_test_catalog(t)
	_test_item(t)
	_test_grid(t)
	_test_inventory(t)
	_test_dup_inflation(t)


func _test_item(t: TestContext) -> void:
	t.suite = "InventoryItem.expansion"
	t.ok(int(InventoryItemScript.Kind.EXPAND_2X2) == WeaponCatalogScript.EXPAND_2X2,
		"InventoryItem.Kind matches the catalog const")
	var e := InventoryItemScript.for_kind(InventoryItemScript.Kind.EXPAND_2X2)
	t.ok(e.item_type == WeaponDefScript.ItemType.EXPANSION, "EXPAND_2X2 is an EXPANSION item")
	t.ok(e.cells().size() == 4, "the 2x2 occupies 4 cells")
	t.ok(e.power() == 0 and e.level() == 0, "an expansion has no power or level")
	t.ok(e.rarity() == "Inventory Expansion", "expansion is labelled 'Inventory Expansion' in the tooltip subtitle")
	t.ok(e.tags().is_empty(), "an expansion shows no header tag pills")
	t.ok(e.buy_price() == 55, "2x2 buy price equals its base 55")
	t.ok(e.sell_price() == roundi(55.0 * InventoryItemScript.SELL_FRACTION), "2x2 sell price is base * 0.65")
	var labels := {}
	for row in e.stats():
		labels[row[0]] = row[1]
	t.ok(labels.get("Size") == "2x2" and labels.get("Slots") == 4, "expansion stats show Size + Slots")
	t.ok(not labels.has("Damage"), "an expansion has no combat stats")


func _test_grid(t: TestContext) -> void:
	t.suite = "ExpandableGrid"
	var base_cells: Array[Vector2i] = [Vector2i(0, 0)]
	var g := ExpandableGridScript.backpack(base_cells, 4, 4)
	t.ok(g.field_cells().size() == 16, "a 4x4 field has 16 potential cells")
	t.ok(g.valid.size() == 1, "only the base cell is active at start")
	t.ok(g.locked_cells().size() == 15, "the rest start locked")

	var e1 := InventoryItemScript.for_kind(InventoryItemScript.Kind.EXPAND_1X1)
	t.ok(g.fits(e1, Vector2i(1, 0)), "a 1x1 extender fits on a locked cell")
	t.ok(not g.fits(e1, Vector2i(0, 0)), "an extender can't sit on an active cell")
	t.ok(not g.fits(e1, Vector2i(4, 0)), "an extender can't sit outside the field")
	g.place(e1, Vector2i(1, 0))
	t.ok(g.valid.has(Vector2i(1, 0)) and g.valid.size() == 2, "placing an extender activates its cell")

	var e2 := InventoryItemScript.for_kind(InventoryItemScript.Kind.EXPAND_2X2)
	t.ok(g.fits(e2, Vector2i(2, 2)), "a 2x2 extender fits a locked 2x2 block")
	g.place(e2, Vector2i(2, 2))
	t.ok(g.valid.size() == 6, "the 2x2 adds four active cells")

	# A gun resting on the 2x2 locks that extender in place.
	var gun := InventoryItemScript.new()
	gun.item_type = WeaponDefScript.ItemType.GUN
	var gun_cells: Array[Vector2i] = [Vector2i(0, 0)]
	gun.base_cells = gun_cells
	t.ok(g.fits(gun, Vector2i(2, 2)), "a gun fits on the unlocked 2x2 area")
	g.place(gun, Vector2i(2, 2))
	t.ok(g.item_at(Vector2i(2, 2)) == gun, "item_at returns the gun on top")
	t.ok(not g.can_pick_up(e2), "an extender with a gun on it can't be picked up")
	t.ok(g.can_pick_up(e1), "an uncovered extender can be picked up")

	g.remove(gun)
	t.ok(g.can_pick_up(e2), "removing the gun frees the extender")
	t.ok(g.item_at(Vector2i(2, 2)) == e2, "item_at now returns the extender beneath")
	g.remove(e2)
	t.ok(g.valid.size() == 2 and not g.valid.has(Vector2i(2, 2)), "removing an extender deactivates its cells")


func _test_inventory(t: TestContext) -> void:
	t.suite = "Inventory.expand"
	var inv := InventoryScript.build()
	t.ok(inv.backpack.field_cells().size() == 48, "backpack field is 8x6 = 48 cells")
	t.ok(inv.backpack.valid.size() == 14, "the centered base has 14 active cells")
	t.ok(inv.backpack.locked_cells().size() == 34, "34 locked cells remain")
	t.ok(inv.backpack.valid.has(Vector2i(3, 1)) and inv.backpack.valid.has(Vector2i(5, 4)),
		"base is offset by (2,1) into the field")
	t.ok(inv.equipped_guns().size() == 2, "both starting pistols are equipped in the centered base")
	t.ok(inv.expansion_count() == 0, "no expansions owned at start")
	t.ok(inv.expansion_price(WeaponCatalogScript.EXPAND_2X2) == 55, "the first 2x2 costs its base price")

	# Price tracks field fullness, not the count owned: a stashed expansion (no field
	# cells unlocked) leaves the price at base.
	var growth: float = InventoryScript.EXPANSION_PRICE_GROWTH
	var e_a := InventoryItemScript.for_kind(InventoryItemScript.Kind.EXPAND_1X1)
	inv.add_to_stash(e_a)
	t.ok(inv.expansion_count() == 1, "a stashed expansion is counted")
	t.ok(inv.expansion_price(WeaponCatalogScript.EXPAND_2X2) == 55,
		"a stashed expansion does not raise the price (no field slots unlocked)")

	# Placing a 2x2 unlocks 4 slots -> the next price scales by growth^4.
	var plate := InventoryItemScript.for_kind(InventoryItemScript.Kind.EXPAND_2X2)
	var spot := Vector2i(0, 0)
	for cell in inv.backpack.locked_cells():
		if inv.backpack.fits(plate, cell):
			spot = cell
			break
	inv.backpack.place(plate, spot)
	t.ok(inv.expansion_price(WeaponCatalogScript.EXPAND_2X2) == roundi(55.0 * pow(growth, 4.0)),
		"price escalates with unlocked slots (4 cells -> growth^4)")

	# Reversible: lift the expansion back out and the freed slots drop the price to base.
	inv.backpack.remove(plate)
	t.ok(inv.expansion_price(WeaponCatalogScript.EXPAND_2X2) == 55,
		"removing the expansion drops the price back to base (reversible)")
	t.ok(inv.equipped_guns().size() == 2, "a stashed expansion is never equipped as a gun")
	inv.free()


func _test_dup_inflation(t: TestContext) -> void:
	t.suite = "Inventory.dup_price"
	var inv := InventoryScript.build()   # starts with 2 pistols equipped in the backpack
	# Guns inflate per-kind, gently. Two pistols already owned -> a 3rd is x(growth^2).
	var gg: float = InventoryScript.GUN_DUP_GROWTH
	var pistol := InventoryItemScript.pistol()
	t.ok(inv.owned_count(InventoryItemScript.Kind.PISTOL) == 2, "the two starting pistols are counted")
	t.ok(inv.shop_price(pistol) == roundi(float(pistol.buy_price()) * pow(gg, 2.0)),
		"a 3rd pistol is inflated by the two already owned")
	var sawed := InventoryItemScript.for_kind(InventoryItemScript.Kind.SAWED_OFF)
	t.ok(inv.shop_price(sawed) == sawed.buy_price(), "an unowned gun kind sits at its base price")

	# Artifacts inflate per-kind, steeply. First is base; owning one inflates the next.
	var ag: float = InventoryScript.ARTIFACT_DUP_GROWTH
	var rune := InventoryItemScript.for_kind(InventoryItemScript.Kind.RUNE_OF_WRATH)
	t.ok(inv.shop_price(rune) == rune.buy_price(), "the first artifact of a kind is at base price")
	inv.add_to_stash(InventoryItemScript.for_kind(InventoryItemScript.Kind.RUNE_OF_WRATH))
	t.ok(inv.shop_price(rune) == roundi(float(rune.buy_price()) * ag),
		"owning one rune inflates the next by the artifact growth")
	var coil := InventoryItemScript.for_kind(InventoryItemScript.Kind.HELLFIRE_COIL)
	t.ok(inv.shop_price(coil) == coil.buy_price(), "a different artifact kind is not inflated")
	inv.free()


func _test_catalog(t: TestContext) -> void:
	t.suite = "WeaponCatalog.expansions"
	var wk := WeaponCatalogScript.weapon_kinds()
	t.ok(not wk.has(WeaponCatalogScript.EXPAND_1X1) and not wk.has(WeaponCatalogScript.EXPAND_2X2),
		"weapon_kinds() excludes expansions")
	var ek := WeaponCatalogScript.expansion_kinds()
	t.ok(ek.size() == 4 and ek.has(WeaponCatalogScript.EXPAND_1X1) and ek.has(WeaponCatalogScript.EXPAND_2X2)
			and ek.has(WeaponCatalogScript.EXPAND_1X3) and ek.has(WeaponCatalogScript.EXPAND_1X4),
		"expansion_kinds() returns all four expansion kinds")
	var d := WeaponCatalogScript.get_def(WeaponCatalogScript.EXPAND_2X2)
	t.ok(d.item_type == WeaponDefScript.ItemType.EXPANSION, "the 2x2 def is an EXPANSION")
	t.ok(d.cells.size() == 4 and d.base_price == 55, "the 2x2 def has 4 cells and base price 55")
