extends RefCounted
## Artifacts: catalog defs + the pure resolver (adjacency, stacking, globals, amps, conduit).

const TestContext := preload("res://test/test_context.gd")
const WeaponDefScript := preload("res://src/weapons/weapon_def.gd")
const WeaponCatalogScript := preload("res://src/weapons/weapon_catalog.gd")
const InventoryItemScript := preload("res://src/inventory/inventory_item.gd")
const InventoryGridScript := preload("res://src/inventory/inventory_grid.gd")
const GunModsScript := preload("res://src/weapons/gun_mods.gd")
const ArtifactResolverScript := preload("res://src/artifacts/artifact_resolver.gd")


func run(t: TestContext) -> void:
	_test_weapon_def_artifact_fields(t)
	_test_artifact_catalog(t)
	_test_gun_mods(t)
	_test_resolver_adjacent(t)
	_test_resolver_global(t)
	_test_resolver_stacking(t)
	_test_resolver_resonator(t)
	_test_resolver_conduit(t)
	_test_resolve_full(t)


func _test_weapon_def_artifact_fields(t: TestContext) -> void:
	t.suite = "WeaponDef.artifact"
	var d: Object = WeaponDefScript.from({
		"item_type": WeaponDefScript.ItemType.ARTIFACT, "tier": 3,
		"effect": {"scope": WeaponDefScript.Scope.ADJACENT, "stat": "damage", "mul": 1.4},
	})
	t.ok(d.tier == 3, "tier is set")
	t.ok(not d.is_amplifier() and not d.is_conduit(), "a plain stat artifact is neither amp nor conduit")
	var amp: Object = WeaponDefScript.from({"effect": {"amp": "neighbors", "mul": 1.4}})
	t.ok(amp.is_amplifier(), "an effect with 'amp' is an amplifier")
	var con: Object = WeaponDefScript.from({"effect": {"conduit": true}})
	t.ok(con.is_conduit(), "an effect with 'conduit' is a conduit")


func _test_artifact_catalog(t: TestContext) -> void:
	t.suite = "WeaponCatalog.artifacts"
	var K := InventoryItemScript.Kind
	t.ok(WeaponCatalogScript.artifact_kinds().size() == 10, "10 artifacts (got %d)" % WeaponCatalogScript.artifact_kinds().size())
	var rune := WeaponCatalogScript.get_def(K.RUNE_OF_WRATH)
	t.ok(rune.item_type == WeaponDefScript.ItemType.ARTIFACT and rune.tier == 1, "Rune is a Tier-1 artifact")
	t.ok(rune.base_price == 20, "Tier-1 artifact price is 20 (got %d)" % rune.base_price)
	t.ok(WeaponCatalogScript.get_def(K.THE_SUN).base_price == 480, "Tier-5 price is 480")
	t.ok(WeaponCatalogScript.tier_first_wave(5) == 15, "Tier 5 first appears wave 15")
	# Catalog int keys line up with the Kind enum (same assertion style as WeaponCatalog suite).
	t.ok(WeaponCatalogScript.RUNE_OF_WRATH == K.RUNE_OF_WRATH and WeaponCatalogScript.THE_SUN == K.THE_SUN,
		"artifact catalog keys match the Kind enum order")
	var w2 := WeaponCatalogScript.kinds_for_wave(2)
	t.ok(not w2.has(K.THE_SUN) and w2.has(K.RUNE_OF_WRATH), "wave-2 artifact pool excludes Mythics, includes Commons")
	t.ok(WeaponCatalogScript.kinds_for_wave(15).size() == 10, "wave 15 unlocks all 10 artifacts")


func _test_gun_mods(t: TestContext) -> void:
	t.suite = "GunMods"
	var m: Object = GunModsScript.new()
	t.ok(m.damage_mul == 1.0 and m.fire_rate_mul == 1.0 and m.reload_mul == 1.0, "GunMods defaults are identity")


func _grid() -> Object:
	return InventoryGridScript.rect(4, 4)


func _gun() -> Object:
	var g := InventoryItemScript.for_kind(InventoryItemScript.Kind.PISTOL)
	g.base_cells = [Vector2i(0, 0)]            # 1x1 for clean adjacency tests
	return g


func _artifact(k: int) -> Object:
	return InventoryItemScript.for_kind(k)     # artifacts are normal 1x1 kinds now


func _test_resolver_adjacent(t: TestContext) -> void:
	t.suite = "ArtifactResolver.adjacent"
	var K := InventoryItemScript.Kind
	var grid := _grid(); var gun := _gun(); grid.place(gun, Vector2i(1, 1))
	grid.place(_artifact(K.RUNE_OF_WRATH), Vector2i(1, 0))
	var far := _gun(); grid.place(far, Vector2i(3, 3))
	var mods: Dictionary = ArtifactResolverScript.resolve(grid)
	t.ok(is_equal_approx(mods[gun].damage_mul, 1.4), "adjacent Rune -> x1.4 dmg (got %.2f)" % mods[gun].damage_mul)
	t.ok(is_equal_approx(mods[far].damage_mul, 1.0), "non-adjacent gun unaffected")


func _test_resolver_global(t: TestContext) -> void:
	t.suite = "ArtifactResolver.global"
	var K := InventoryItemScript.Kind
	var grid := _grid()
	var g1 := _gun(); grid.place(g1, Vector2i(0, 0))
	var g2 := _gun(); grid.place(g2, Vector2i(3, 3))
	grid.place(_artifact(K.THE_FURNACE), Vector2i(2, 0))
	var mods: Dictionary = ArtifactResolverScript.resolve(grid)
	t.ok(is_equal_approx(mods[g1].damage_mul, 1.4) and is_equal_approx(mods[g2].damage_mul, 1.4),
		"GLOBAL artifact buffs every gun regardless of position")


func _test_resolver_stacking(t: TestContext) -> void:
	t.suite = "ArtifactResolver.stacking"
	var K := InventoryItemScript.Kind
	var grid := _grid()
	grid.place(_artifact(K.CHAIN_SIGIL), Vector2i(1, 1))
	var g1 := _gun(); grid.place(g1, Vector2i(1, 0))   # above chain
	var g2 := _gun(); grid.place(g2, Vector2i(0, 1))   # left of chain (2 adjacent guns)
	var mods: Dictionary = ArtifactResolverScript.resolve(grid)
	t.ok(is_equal_approx(mods[g1].fire_rate_mul, 1.2), "Chain Sigil w/ 2 adjacent guns = +20%% (got %.2f)" % mods[g1].fire_rate_mul)
	var grid2 := _grid()
	grid2.place(_artifact(K.HOARDERS_MARK), Vector2i(1, 1))
	var gun := _gun(); grid2.place(gun, Vector2i(2, 1))
	grid2.place(_artifact(K.RUNE_OF_WRATH), Vector2i(1, 0))
	grid2.place(_artifact(K.RUNE_OF_WRATH), Vector2i(0, 1))
	grid2.place(_artifact(K.RUNE_OF_WRATH), Vector2i(1, 2))
	var mods2: Dictionary = ArtifactResolverScript.resolve(grid2)
	t.ok(is_equal_approx(mods2[gun].damage_mul, 1.36), "Hoarder caps at +36%% w/ 3 neighbours (got %.2f)" % mods2[gun].damage_mul)


func _test_resolver_resonator(t: TestContext) -> void:
	t.suite = "ArtifactResolver.resonator"
	var K := InventoryItemScript.Kind
	var grid := _grid()
	grid.place(_artifact(K.RUNE_OF_WRATH), Vector2i(1, 1))
	grid.place(_artifact(K.RESONATOR), Vector2i(1, 0))
	var gun := _gun(); grid.place(gun, Vector2i(2, 1))
	var mods: Dictionary = ArtifactResolverScript.resolve(grid)
	t.ok(is_equal_approx(mods[gun].damage_mul, 1.56), "Resonator amps Rune to x1.56 (got %.3f)" % mods[gun].damage_mul)


## resolve_full() adds who-buffs-whom both directions for the tooltip + star overlay.
func _test_resolve_full(t: TestContext) -> void:
	t.suite = "ArtifactResolver.full"
	var K := InventoryItemScript.Kind
	var grid := _grid()
	var gun := _gun(); grid.place(gun, Vector2i(1, 1))
	var rune := _artifact(K.RUNE_OF_WRATH); grid.place(rune, Vector2i(1, 0))
	var far := _gun(); grid.place(far, Vector2i(3, 3))
	var full: Dictionary = ArtifactResolverScript.resolve_full(grid)
	t.ok(full["by_gun"][gun] == [rune], "by_gun lists the artifact buffing the gun")
	t.ok(full["by_gun"][far].is_empty(), "an unbuffed gun has no sources")
	t.ok(full["by_artifact"][rune] == [gun], "by_artifact lists the gun the artifact reaches")
	t.ok(is_equal_approx(full["mods"][gun].damage_mul, 1.4), "mods match resolve()")


func _test_resolver_conduit(t: TestContext) -> void:
	t.suite = "ArtifactResolver.conduit"
	var K := InventoryItemScript.Kind
	var grid := _grid()
	grid.place(_artifact(K.RUNE_OF_WRATH), Vector2i(0, 0))
	grid.place(_artifact(K.CONDUIT), Vector2i(1, 0))
	var gun := _gun(); grid.place(gun, Vector2i(2, 0))
	var mods: Dictionary = ArtifactResolverScript.resolve(grid)
	t.ok(is_equal_approx(mods[gun].damage_mul, 1.4), "Conduit relays the Rune to the gun behind it (got %.2f)" % mods[gun].damage_mul)
