extends RefCounted
## UI tests: tooltip, grid view, level-up menu, HUD medals/XP/souls/debuff, status
## icon, shop, sell. Split from run_tests.gd. `t` is the shared TestContext.

const TestContext := preload("res://test/test_context.gd")
const ItemTooltipScript := preload("res://src/ui/item_tooltip.gd")
const GridViewScript := preload("res://src/ui/grid_view.gd")
const StatusIconScript := preload("res://src/ui/status_icon.gd")
const WaveMenuScript := preload("res://src/ui/wave_menu.gd")
const HudScript := preload("res://src/ui/hud.gd")
const InventoryItemScript := preload("res://src/inventory/inventory_item.gd")
const InventoryScript := preload("res://src/inventory/inventory.gd")
const PlayerStatsScript := preload("res://src/marine/player_stats.gd")
const MarineScript := preload("res://src/marine/marine.gd")
const WeaponRingScript := preload("res://src/weapons/weapon_ring.gd")
const WeaponCatalogScript := preload("res://src/weapons/weapon_catalog.gd")
const WeaponDefScript := preload("res://src/weapons/weapon_def.gd")
const GunModsScript := preload("res://src/weapons/gun_mods.gd")
const RecapViewScript := preload("res://src/ui/recap_view.gd")
const WaveStatsScript := preload("res://src/stats/wave_stats.gd")
const CombatTrackerScript := preload("res://src/stats/combat_tracker.gd")


func run(t: TestContext) -> void:
	_test_item_tooltip(t)
	_test_grid_view(t)
	_test_grid_view_colors(t)
	await _test_grid_view_expandable(t)
	await _test_wave_menu(t)
	await _test_hud_clear_medals(t)
	await _test_hud_xp_animation(t)
	await _test_status_icon(t)
	await _test_reload_debuff(t)
	await _test_shop_offers(t)
	await _test_sell_item(t)
	await _test_tooltip_expansion(t)
	await _test_shop_expansion_offers(t)
	await _test_shop_artifacts(t)
	await _test_shop_composition(t)
	await _test_tooltip_artifact_buff(t)
	await _test_grid_view_stars(t)
	await _test_expansion_pickup_move(t)
	await _test_grid_view_substrate(t)
	await _test_shop_lock(t)
	await _test_shop_reroll(t)
	await _test_recap_view(t)
	await _test_wave_menu_recap(t)


func _test_grid_view_colors(t: TestContext) -> void:
	t.suite = "GridView.colors"
	var pistol := InventoryItemScript.pistol()
	var sawed_off := InventoryItemScript.for_kind(InventoryItemScript.Kind.SAWED_OFF)
	t.ok(GridViewScript.color_for(pistol) != GridViewScript.color_for(sawed_off),
		"placeholder colours come from each weapon's catalog def")


func _test_item_tooltip(t: TestContext) -> void:
	t.suite = "ItemTooltip"
	var p := InventoryItemScript.pistol()
	t.ok(p.display_name() == "Pistol", "pistol display name")
	t.ok(p.rarity() == "Normal" and p.level() == 1, "pistol is Normal / Lvl 1")
	t.ok(p.flavor().length() > 0, "pistol has flavour text")

	var rows := ItemTooltipScript.format_stats(p)
	var shown := {}
	for r in rows:
		shown[r[0]] = r[1]
	t.ok(shown.has("Damage") and shown["Damage"] == "5", "Damage shows as 5")
	t.ok(not shown.has("Power"), "Power is no longer a stat row (it's an icon chip)")
	t.ok(not shown.has("Projectile"), "Projectile is no longer a stat row (it's a header tag)")
	t.ok(not shown.has("Piercing") and not shown.has("Ricochet"),
		"zero-valued stats (Piercing/Ricochet) are hidden")
	t.ok(shown.has("Magazine") and shown["Magazine"] == "7", "Magazine shows 7")
	t.ok(shown.has("Reload") and shown["Reload"] == "2", "Reload shows as 2 (base pistol seconds)")

	# Type + tags: pistol is a Gun and is tagged both Projectile and Gun.
	t.ok(p.type_name() == "Gun", "pistol Type is Gun")
	t.ok(p.tags().has("Projectile") and p.tags().has("Gun"), "pistol header tags include Projectile + Gun")

	# Manual flavour wrap: no line exceeds the limit, and no word is lost.
	var wrapped := ItemTooltipScript._wrap(p.flavor(), 20)
	var longest := 0
	for line in wrapped.split("\n"):
		longest = maxi(longest, line.length())
	t.ok(longest <= 20, "wrap keeps lines within the char limit (longest %d)" % longest)
	t.ok(wrapped.replace("\n", " ") == p.flavor(), "wrap preserves the words and order")


func _test_grid_view(t: TestContext) -> void:
	t.suite = "GridView"
	var gv: Control = GridViewScript.new()
	var step := GridViewScript.CELL + GridViewScript.GAP
	t.ok(gv.cell_at(Vector2(5, 5)) == Vector2i(0, 0), "top-left pixels map to cell (0,0)")
	t.ok(gv.cell_at(Vector2(step + 5, 5)) == Vector2i(1, 0), "one step right maps to cell (1,0)")
	t.ok(gv.cell_at(Vector2(5, step * 2 + 5)) == Vector2i(0, 2), "two steps down maps to cell (0,2)")
	t.ok(gv.cell_origin(Vector2i(2, 1)).is_equal_approx(Vector2(step * 2, step)),
		"cell_origin returns the cell's top-left pixel")
	gv.free()

	# Rarity backing: Normal gets none; non-Normal uses the shared rarity colour.
	var normal := InventoryItemScript.pistol()
	t.ok(GridViewScript.rarity_bg(normal).a == 0.0, "Normal item has no rarity background")
	var rare := InventoryItemScript.pistol()
	rare.item_level = 3                                # -> Rare
	var bg := GridViewScript.rarity_bg(rare)
	var rare_col: Color = ItemTooltipScript.RARITY_COLORS["Rare"]
	t.ok(bg.a > 0.0, "a non-Normal item gets a rarity background")
	t.ok(is_equal_approx(bg.r, rare_col.r) and is_equal_approx(bg.g, rare_col.g) and is_equal_approx(bg.b, rare_col.b),
		"the backing uses the existing assigned Rare colour")


func _test_grid_view_expandable(t: TestContext) -> void:
	t.suite = "GridView.expandable"
	var inv: Node = InventoryScript.build()
	var gv: Control = GridViewScript.new()
	gv.setup(inv.backpack)
	var step := GridViewScript.CELL + GridViewScript.GAP
	t.ok(gv.custom_minimum_size.is_equal_approx(Vector2(8 * step, 6 * step)),
		"an expandable grid view spans the full 8x6 field")
	t.root().add_child(gv)
	await t.frame()                       # exercise _draw (locked cells + base); a draw error surfaces in the run log
	gv.free()

	var e := InventoryItemScript.for_kind(InventoryItemScript.Kind.EXPAND_2X2)
	t.ok(GridViewScript.color_for(e) == WeaponCatalogScript.get_def(WeaponCatalogScript.EXPAND_2X2).placeholder_color,
		"an expansion's placeholder colour comes from its catalog def")
	t.ok(GridViewScript.icon_for(InventoryItemScript.for_kind(InventoryItemScript.Kind.EXPAND_1X1)) != null,
		"the 1x1 expansion icon loads once its art exists")
	t.ok(GridViewScript.icon_for(InventoryItemScript.for_kind(InventoryItemScript.Kind.EXPAND_2X2)) != null,
		"the 2x2 expansion icon loads once its art exists")
	t.ok(GridViewScript.icon_for(InventoryItemScript.for_kind(InventoryItemScript.Kind.RUNE_OF_WRATH)) != null,
		"the artifact placeholder icon (artifact_00) loads — guards against an unimported PNG")
	inv.free()


func _test_wave_menu(t: TestContext) -> void:
	t.suite = "WaveMenu"
	var inv: Node = InventoryScript.build()
	var st: Node = PlayerStatsScript.new()
	st.souls = 5
	var menu: CanvasLayer = WaveMenuScript.new()
	menu.inventory = inv
	menu.stats = st
	t.root().add_child(menu)
	await t.frame()                       # _ready builds the UI

	menu.open(2)
	t.ok(t.tree.paused and menu.visible, "open() pauses the tree and shows the menu")
	t.ok(menu._souls_label.text == "5 SOULS", "menu shows the banked soul count (%s)" % menu._souls_label.text)
	menu.open(3)
	t.ok(menu._open, "open() is idempotent while already open")
	menu.close()
	t.ok(not t.tree.paused and not menu.visible, "close() unpauses and hides")

	# Held items are never lost: pick one up, then close returns it to its origin.
	menu.open(4)
	var p: Object = inv.equipped_pistols()[0]
	menu._begin_hold(inv.backpack, p)         # simulate a pick-up (UI click does this)
	t.ok(inv.equipped_pistols().size() == 1, "holding a pistol unequips it")
	menu.close()
	t.ok(inv.equipped_pistols().size() == 2, "close() returns the held pistol -> re-equipped")
	t.tree.paused = false                     # safety: ensure unpaused for later tests
	menu.free()
	inv.free()
	st.free()


func _test_hud_clear_medals(t: TestContext) -> void:
	t.suite = "Hud.medals"
	var stats: Node = PlayerStatsScript.new()
	var hud: CanvasLayer = HudScript.new()
	hud.stats = stats
	t.root().add_child(hud)
	await t.frame()                       # _ready builds the HUD
	hud._add_lvlup_medal()
	hud._add_lvlup_medal()
	t.ok(hud._lvlup_stack.get_child_count() == 2, "two medals on the stack")
	hud.clear_levelup_medals()
	await t.frame()                       # let queue_free run
	t.ok(hud._lvlup_stack.get_child_count() == 0, "clear_levelup_medals empties the stack")
	hud.free()
	stats.free()


func _test_hud_xp_animation(t: TestContext) -> void:
	t.suite = "Hud.xp"
	var stats: Node = PlayerStatsScript.new()
	var hud: CanvasLayer = HudScript.new()
	hud.stats = stats
	t.root().add_child(hud)
	await t.frame()                       # _ready builds the HUD + seeds the bar

	var reached := [0]
	hud.level_reached.connect(func(l: int) -> void: reached[0] = l)

	# Gain less than a level: the bar animates toward it; no level-up.
	stats.add_xp(4.0)
	for i in 40:
		hud._animate_xp(0.05)
	t.ok(reached[0] == 0, "no level_reached while the bar is below 100%")
	t.ok(absf(hud._xp.value - 4.0) < 0.05 and hud._xp_level == 1,
		"bar animates to the gained XP, still level 1 (value %.1f)" % hud._xp.value)

	# Cross the threshold: stats level up at once, but the flourish waits for the bar.
	stats.add_xp(13.0)                        # total 17 > 16 (xp_for(1)) -> stats.level becomes 2 now
	t.ok(stats.level == 2, "stats level up immediately (authoritative)")
	t.ok(reached[0] == 0, "the bar hasn't filled yet -> level_reached still not fired")

	var saw_full := false
	for i in 60:
		hud._animate_xp(0.05)
		if reached[0] != 0:
			saw_full = true
			break
	t.ok(saw_full and reached[0] == 2, "level_reached(2) fires only when the bar hits 100%")
	t.ok(hud._xp_level == 2, "the bar advances to level 2 after filling")

	hud.free()
	stats.free()


func _test_status_icon(t: TestContext) -> void:
	t.suite = "StatusIcon"
	var s: Control = StatusIconScript.new()
	t.root().add_child(s)
	await t.frame()
	s.set_state(3, 0.5, 1.2)
	t.ok(s._stacks == 3 and is_equal_approx(s._frac, 0.5) and is_equal_approx(s._seconds, 1.2),
		"set_state stores stacks / cooldown fraction / seconds")
	s.set_state(1, 2.0, 5.0)
	t.ok(is_equal_approx(s._frac, 1.0), "cooldown fraction is clamped to 1")
	s.free()


func _test_reload_debuff(t: TestContext) -> void:
	t.suite = "Hud.debuff"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var m: Node3D = MarineScript.new()
	holder.add_child(m)
	var inv: Node = InventoryScript.build()
	m.add_child(inv)
	m.inventory = inv
	var wr: Node3D = WeaponRingScript.new()
	wr.player = m
	holder.add_child(wr)
	await t.frame()                           # ring builds 2 guns from the 2 pistols

	t.ok(wr.reload_state()["count"] == 0, "no guns reloading -> count 0")
	wr._guns[0]._start_reload()
	var st: Dictionary = wr.reload_state()
	t.ok(st["count"] == 1, "one reloading gun -> count 1")
	t.ok(st["frac"] > 0.9, "a fresh reload reads near full (%.2f)" % st["frac"])

	var hud: CanvasLayer = HudScript.new()
	var pstats: Node = PlayerStatsScript.new()
	hud.stats = pstats
	hud.weapon_ring = wr
	t.root().add_child(hud)
	await t.frame()
	hud._update_reload_debuff()
	t.ok(hud._reload_icon.visible, "HUD shows the reload debuff while a gun reloads")
	t.ok(hud._reload_icon._stacks == 1, "debuff stack matches one reloading gun")

	wr._guns[1]._start_reload()
	hud._update_reload_debuff()
	t.ok(hud._reload_icon._stacks == 2, "debuff stacks with the number of reloading guns")

	wr._guns[0]._finish_reload()
	wr._guns[1]._finish_reload()
	hud._update_reload_debuff()
	t.ok(not hud._reload_icon.visible, "debuff hides once no gun is reloading")

	hud.free()
	pstats.free()
	holder.free()


func _test_shop_offers(t: TestContext) -> void:
	t.suite = "WaveMenu.shop"
	var inv: Node = InventoryScript.build()
	var st: Node = PlayerStatsScript.new()
	st.souls = 1000                               # plenty to buy
	st.level = 10                                 # allow higher-level rolls
	var menu: CanvasLayer = WaveMenuScript.new()
	menu.inventory = inv
	menu.stats = st
	menu._rng.seed = 42                           # deterministic offers
	t.root().add_child(menu)
	await t.frame()
	menu.open(2)
	t.ok(menu._offers.size() == 5, "open() rolls 5 shop offers (got %d)" % menu._offers.size())

	var before_souls: int = st.souls
	var price: int = int(menu._offers[0]["price"])
	var stash_before: int = inv.stash.items_in_reading_order().size()
	menu._buy(0)
	t.ok(st.souls == before_souls - price, "buying spends the offer's soul price (%d -> %d, price %d)"
		% [before_souls, st.souls, price])
	t.ok(inv.stash.items_in_reading_order().size() == stash_before + 1, "bought item lands in the stash")
	t.ok(menu._offers[0]["sold"], "the bought slot is marked sold")
	menu._buy(0)
	t.ok(inv.stash.items_in_reading_order().size() == stash_before + 1, "a sold slot can't be bought again")

	st.souls = 0                                  # drain -> next buy is a no-op
	var stash_now: int = inv.stash.items_in_reading_order().size()
	menu._buy(1)
	t.ok(inv.stash.items_in_reading_order().size() == stash_now, "an unaffordable offer can't be bought")

	t.tree.paused = false
	menu.free()
	inv.free()
	st.free()


func _test_tooltip_expansion(t: TestContext) -> void:
	t.suite = "ItemTooltip.expansion"
	var tip: Control = ItemTooltipScript.new()
	t.root().add_child(tip)
	await t.frame()                       # _ready sets the font
	var e := InventoryItemScript.for_kind(InventoryItemScript.Kind.EXPAND_2X2)
	tip._build_model(e, 21)
	t.ok(not tip._show_power, "an expansion tooltip hides the power chip")
	t.ok(tip._sub_text == "Inventory Expansion", "an expansion subtitle reads 'Inventory Expansion' (%s)" % tip._sub_text)
	t.ok(not tip._sub_text.contains("Lvl"), "an expansion subtitle drops the level")
	var p := InventoryItemScript.pistol()
	tip._build_model(p, 21)
	t.ok(tip._show_power, "a weapon still shows the power chip")
	t.ok(tip._sub_text.contains("Lvl"), "a weapon subtitle keeps the level")
	tip.free()


func _test_shop_expansion_offers(t: TestContext) -> void:
	t.suite = "WaveMenu.expansions"
	var inv: Node = InventoryScript.build()
	var st: Node = PlayerStatsScript.new()
	st.souls = 1000
	st.level = 10
	var menu: CanvasLayer = WaveMenuScript.new()
	menu.inventory = inv
	menu.stats = st
	menu._rng.seed = 7
	t.root().add_child(menu)
	await t.frame()

	# Rolling many offer items yields both weapons and expansions.
	var saw_exp := false
	var saw_gun := false
	for i in 200:
		var it: Object = menu._roll_offer_item()
		if it.item_type == WeaponDefScript.ItemType.EXPANSION:
			saw_exp = true
		else:
			saw_gun = true
	t.ok(saw_exp and saw_gun, "rolled offers include both expansions and weapons")

	# An expansion offer is priced via the escalating inventory price.
	var e := InventoryItemScript.for_kind(InventoryItemScript.Kind.EXPAND_2X2)
	t.ok(menu._offer_price(e) == inv.expansion_price(WeaponCatalogScript.EXPAND_2X2),
		"expansion offers use the escalating inventory price")

	# Buying an expansion lands it in the stash and counts toward escalation.
	menu.open(1)
	var before: int = inv.expansion_count()
	menu._offers[0] = {"item": e, "price": menu._offer_price(e), "sold": false, "locked": false}
	menu._refresh_offer(0)
	menu._buy(0)
	t.ok(inv.expansion_count() == before + 1, "buying an expansion increases the owned count")

	t.tree.paused = false
	menu.free()
	inv.free()
	st.free()


## The shop rolls artifacts once their tier has unlocked, and gates higher tiers behind
## later waves. Rolls many offers (deterministic seed) rather than relying on 4 lucky slots.
func _test_shop_artifacts(t: TestContext) -> void:
	t.suite = "WaveMenu.shop_artifacts"
	var inv: Node = InventoryScript.build()
	var st: Node = PlayerStatsScript.new()
	st.souls = 1000
	st.level = 20
	var menu: CanvasLayer = WaveMenuScript.new()
	menu.inventory = inv
	menu.stats = st
	menu._rng.seed = 7
	t.root().add_child(menu)
	await t.frame()

	menu.current_wave = 20                         # all tiers unlocked
	var saw_artifact := false
	for i in 200:
		if menu._roll_offer_item().is_artifact():
			saw_artifact = true
			break
	t.ok(saw_artifact, "the shop can offer artifacts once unlocked")

	menu.current_wave = 1                          # only Tier-1 eligible
	var any_high_tier := false
	for i in 400:
		var it: Object = menu._roll_offer_item()
		if it.is_artifact() and WeaponCatalogScript.get_def(it.kind).tier >= 4:
			any_high_tier = true
			break
	t.ok(not any_high_tier, "wave 1 never offers Tier 4+ artifacts")

	t.tree.paused = false
	menu.free()
	st.free()
	inv.free()


func _test_shop_composition(t: TestContext) -> void:
	t.suite = "WaveMenu.composition"
	var inv: Node = InventoryScript.build()
	var st: Node = PlayerStatsScript.new()
	st.level = 10
	var menu: CanvasLayer = WaveMenuScript.new()
	menu.inventory = inv
	menu.stats = st
	menu._rng.seed = 3
	t.root().add_child(menu)
	await t.frame()
	menu.open(20)                                  # high wave -> several artifact tiers eligible
	t.ok(menu._offers.size() == 5, "shop has 5 slots")

	var guns := 0
	var exps := 0
	var arts: Dictionary = {}
	for o in menu._offers:
		var it: Object = o["item"]
		if it.is_artifact():
			t.ok(not arts.has(it.kind), "no duplicate artifact kind in the shop")
			arts[it.kind] = true
		elif it.item_type == WeaponDefScript.ItemType.EXPANSION:
			exps += 1
		else:
			guns += 1
	t.ok(guns >= 1, "at least one gun is guaranteed (got %d)" % guns)
	t.ok(exps >= 1, "an expander is guaranteed while the backpack has room (got %d)" % exps)
	menu.close()

	# Fully unlock the backpack: place a 1x1 extender on every locked cell.
	for cell in inv.backpack.locked_cells().duplicate():
		inv.backpack.place(InventoryItemScript.for_kind(InventoryItemScript.Kind.EXPAND_1X1), cell)
	t.ok(inv.backpack.locked_cells().is_empty(), "backpack is now fully unlocked")
	menu.open(20)
	var exps2 := 0
	for o in menu._offers:
		if o["item"].item_type == WeaponDefScript.ItemType.EXPANSION:
			exps2 += 1
	t.ok(exps2 == 0, "no expanders roll once the backpack is full (got %d)" % exps2)
	t.tree.paused = false
	menu.free()
	inv.free()
	st.free()


func _test_sell_item(t: TestContext) -> void:
	t.suite = "WaveMenu.sell"
	var inv: Node = InventoryScript.build()
	var st: Node = PlayerStatsScript.new()
	st.souls = 0
	var menu: CanvasLayer = WaveMenuScript.new()
	menu.inventory = inv
	menu.stats = st
	t.root().add_child(menu)
	await t.frame()
	menu.open(2)
	var p: Object = inv.equipped_pistols()[0]
	var sp: int = p.sell_price()
	menu._begin_hold(inv.backpack, p)             # pick it up (a UI click does this)
	t.ok(inv.equipped_pistols().size() == 1, "held pistol is unequipped")
	menu._sell_held()                             # drop on the sell zone
	t.ok(st.souls == sp, "selling credits the 65%% price (souls %d == %d)" % [st.souls, sp])
	t.ok(menu._held == null, "the sold item is no longer held")
	menu.close()
	t.ok(inv.equipped_pistols().size() == 1, "close() does not resurrect the sold pistol")
	t.tree.paused = false
	menu.free()
	inv.free()
	st.free()


## Regression: picking an extender back up must remove it (re-lock its old cell) and
## make a ghost. The old bug read grid.origin_of[item] (extenders aren't there), so
## _begin_hold aborted before pick_up -> old slot stayed unlocked + no ghost.
func _test_expansion_pickup_move(t: TestContext) -> void:
	t.suite = "WaveMenu.expansion_move"
	var inv: Node = InventoryScript.build()
	var st: Node = PlayerStatsScript.new()
	var menu: CanvasLayer = WaveMenuScript.new()
	menu.inventory = inv
	menu.stats = st
	t.root().add_child(menu)
	await t.frame()
	menu.open(1)

	var ext := InventoryItemScript.for_kind(InventoryItemScript.Kind.EXPAND_1X1)
	var locked: Array = inv.backpack.locked_cells()
	var old_cell: Vector2i = locked[0]
	var new_cell: Vector2i = locked[1]            # a different locked cell to move it to later
	t.ok(old_cell != new_cell, "two distinct locked cells exist")
	t.ok(inv.drop(inv.backpack, ext, old_cell), "extender drops onto a locked cell")
	t.ok(inv.backpack.valid.has(old_cell), "its cell is now unlocked")

	menu._begin_hold(inv.backpack, ext)
	t.ok(menu._held == ext and menu._ghost != null, "pick-up holds the extender and shows a ghost")
	t.ok(menu._held_origin == old_cell, "the held origin is the extender's own cell, not a default")
	t.ok(not inv.backpack.valid.has(old_cell), "picking it up re-locks its old cell (no orphan unlock)")

	t.ok(inv.drop(inv.backpack, menu._held, new_cell), "the held extender drops on the new cell")
	menu._end_hold()
	t.ok(inv.backpack.valid.has(new_cell) and not inv.backpack.valid.has(old_cell),
		"only the new cell is unlocked — the old slot did not stay unlocked")
	t.tree.paused = false
	menu.free()
	inv.free()
	st.free()


## A gun buffed by an artifact shows the resolved stat (5×1.4 = 7), flagged buffed, and
## carries the affecting artifact's icon in the tooltip's icon row.
func _test_tooltip_artifact_buff(t: TestContext) -> void:
	t.suite = "ItemTooltip.artifact_buff"
	var tip: Control = ItemTooltipScript.new()
	t.root().add_child(tip)
	await t.frame()                       # _ready sets the font
	var gun := InventoryItemScript.pistol()        # base damage 5
	var mods: Object = GunModsScript.new()
	mods.damage_mul = 1.4
	var icon: Texture2D = GridViewScript.icon_for(InventoryItemScript.for_kind(InventoryItemScript.Kind.RUNE_OF_WRATH))
	tip.show_for(gun, Vector2(10, 10), 21, 5, false, mods, [icon])
	var dmg := ""
	var buffed := false
	for i in tip._rows.size():
		if tip._rows[i][0] == "Damage":
			dmg = str(tip._rows[i][1])
			buffed = tip._row_buffed[i]
	t.ok(dmg == "7" and buffed, "buffed gun tooltip shows resolved damage 5x1.4=7, flagged buffed (got '%s')" % dmg)
	t.ok(tip._source_icons.size() == 1, "tooltip carries the affecting artifact's icon")
	# An unbuffed gun (no mods) shows the plain value, not flagged.
	tip.show_for(InventoryItemScript.pistol(), Vector2(10, 10), 21, -1, false, null, [])
	var plain_buffed := false
	for b in tip._row_buffed:
		if b:
			plain_buffed = true
	t.ok(not plain_buffed and tip._source_icons.is_empty(), "an unbuffed gun shows plain stats, no icons")
	tip.free()


## set_stars stores the marked cells and drawing a ★ over a grid cell must not crash.
func _test_grid_view_stars(t: TestContext) -> void:
	t.suite = "GridView.stars"
	var inv: Node = InventoryScript.build()
	var gv: Control = GridViewScript.new()
	gv.setup(inv.backpack)
	gv.set_stars([Vector2i(3, 2)])
	t.ok(gv.star_cells == [Vector2i(3, 2)], "set_stars stores the marked cells")
	t.root().add_child(gv)
	await t.frame()                       # exercise _draw_star; a draw error surfaces in the run log
	gv.set_stars([])
	t.ok(gv.star_cells.is_empty(), "set_stars([]) clears the marks")
	gv.free()
	inv.free()


## A placed extender renders faint (substrate alpha) under the slots, and drawing it
## must not crash.
func _test_grid_view_substrate(t: TestContext) -> void:
	t.suite = "GridView.substrate"
	t.ok(GridViewScript.SUBSTRATE_ALPHA > 0.0 and GridViewScript.SUBSTRATE_ALPHA < 1.0,
		"placed expansions render translucently (%.2f)" % GridViewScript.SUBSTRATE_ALPHA)
	var inv: Node = InventoryScript.build()
	var ext := InventoryItemScript.for_kind(InventoryItemScript.Kind.EXPAND_1X1)
	inv.drop(inv.backpack, ext, inv.backpack.locked_cells()[0])
	var gv: Control = GridViewScript.new()
	gv.setup(inv.backpack)
	t.root().add_child(gv)
	await t.frame()                       # draws the faint substrate + base; must not crash
	gv.free()
	inv.free()


func _test_shop_lock(t: TestContext) -> void:
	t.suite = "WaveMenu.lock"
	var inv: Node = InventoryScript.build()
	var st: Node = PlayerStatsScript.new()
	st.souls = 1000
	st.level = 10
	var menu: CanvasLayer = WaveMenuScript.new()
	menu.inventory = inv
	menu.stats = st
	menu._rng.seed = 5
	t.root().add_child(menu)
	await t.frame()
	menu.open(2)
	var kept: Object = menu._offers[0]["item"]
	menu._on_lock_toggled(true, 0)
	t.ok(menu._offers[0]["locked"], "toggling locks the slot")

	menu.close()
	menu.open(3)                                   # next wave's shop
	t.ok(menu._offers[0]["item"] == kept and menu._offers[0]["locked"],
		"a locked offer persists across opens")

	menu._buy(0)
	t.ok(menu._offers[0]["sold"] and not menu._offers[0]["locked"],
		"buying a locked slot clears its lock")
	menu.close()
	menu.open(4)
	t.ok(menu._offers[0]["item"] != kept, "after buying, the slot re-rolls next wave")
	t.tree.paused = false
	menu.free()
	inv.free()
	st.free()


func _test_shop_reroll(t: TestContext) -> void:
	t.suite = "WaveMenu.reroll"
	var inv: Node = InventoryScript.build()
	var st: Node = PlayerStatsScript.new()
	st.add_souls(1000)                             # total_souls = 1000 -> base = max(1, round(20.0)) = 20
	var menu: CanvasLayer = WaveMenuScript.new()
	menu.inventory = inv
	menu.stats = st
	menu._rng.seed = 9
	t.root().add_child(menu)
	await t.frame()
	menu.open(2)
	t.ok(menu.reroll_cost() == 20, "first reroll = max(1, 2%% of total collected) (got %d)" % menu.reroll_cost())

	var kept: Object = menu._offers[0]["item"]
	menu._on_lock_toggled(true, 0)                 # lock slot 0
	var before: int = st.souls
	menu._reroll()
	t.ok(st.souls == before - 20, "reroll spends the cost (%d -> %d)" % [before, st.souls])
	t.ok(menu._offers[0]["item"] == kept, "reroll keeps locked slots")
	t.ok(menu.reroll_cost() == 60, "second reroll triples to base*3 (got %d)" % menu.reroll_cost())

	menu.close()
	menu.open(3)
	t.ok(menu.reroll_cost() == 20, "reroll cost resets to base next wave (got %d)" % menu.reroll_cost())

	for i in menu._offers.size():
		menu._on_lock_toggled(true, i)
	t.ok(menu._reroll_btn.disabled, "reroll is disabled when every slot is locked")
	t.tree.paused = false
	menu.free()
	inv.free()
	st.free()


## RecapView draws a populated and an empty WaveStats without crashing (a draw error
## surfaces in the run log) and stores what it was given.
func _test_recap_view(t: TestContext) -> void:
	t.suite = "RecapView"
	var inv: Node = InventoryScript.build()
	var rv: Control = RecapViewScript.new()
	rv.set_scale_k(1.0)
	t.root().add_child(rv)
	await t.frame()                                  # _ready grabs the font
	var ws: Object = WaveStatsScript.new()
	ws.wave = 5
	ws.duration = 12.0
	ws.damage_dealt = 800.0
	ws.damage_taken = 40.0
	ws.souls_earned = 120
	ws.kills_by_type = {"Imp": 18}
	ws.guns = [{"item": InventoryItemScript.pistol(), "name": "Pistol", "damage": 500.0, "shots": 30, "hits": 26, "kills": 12}]
	rv.show_stats(ws, inv.backpack)
	await t.frame()                                  # exercise _draw with content
	t.ok(rv._stats == ws, "show_stats stores the wave stats")
	rv.show_stats(WaveStatsScript.new(), null)       # empty/edge: no guns, no kills, 0 duration, null backpack
	await t.frame()
	t.ok(rv._stats != null, "an empty recap renders without crashing")
	rv.free()
	inv.free()


## open() defaults to the RECAP tab (recap shown, shop hidden); switching shows the shop.
func _test_wave_menu_recap(t: TestContext) -> void:
	t.suite = "WaveMenu.recap"
	var inv: Node = InventoryScript.build()
	var st: Node = PlayerStatsScript.new()
	var tr: Object = CombatTrackerScript.new()
	tr.begin_wave(2)
	tr.record_damage_taken(5.0)
	tr.end_wave()
	var menu: CanvasLayer = WaveMenuScript.new()
	menu.inventory = inv
	menu.stats = st
	menu.tracker = tr
	t.root().add_child(menu)
	await t.frame()
	menu.open(2)
	t.ok(menu._tab == "shop" and menu._columns.visible and not menu._recap_view.visible,
		"open() defaults to the SHOP tab")
	menu._set_tab("recap")
	t.ok(menu._recap_view.visible and not menu._columns.visible, "switching to RECAP shows the recap")
	t.ok(menu._recap_view._stats == tr.last_wave, "the recap view is fed the last wave's stats")
	# Grid hit-testing is suppressed on the RECAP tab so tab clicks aren't swallowed.
	t.ok(menu._view_and_cell(Vector2(9999, 9999)).is_empty(), "no grid interaction while recap is shown")
	menu._set_tab("shop")
	t.ok(menu._columns.visible and not menu._recap_view.visible, "switching back to SHOP shows the shop")
	menu.close()
	t.tree.paused = false
	menu.free()
	tr.free()       # tracker is a Node referenced via menu.tracker, not a child — free it
	inv.free()
	st.free()
