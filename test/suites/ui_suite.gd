extends RefCounted
## UI tests: tooltip, grid view, level-up menu, HUD medals/XP/souls/debuff, status
## icon, shop, sell. Split from run_tests.gd. `t` is the shared TestContext.

const TestContext := preload("res://test/test_context.gd")
const ItemTooltipScript := preload("res://src/ui/item_tooltip.gd")
const GridViewScript := preload("res://src/ui/grid_view.gd")
const StatusIconScript := preload("res://src/ui/status_icon.gd")
const LevelUpMenuScript := preload("res://src/ui/level_up_menu.gd")
const HudScript := preload("res://src/ui/hud.gd")
const InventoryItemScript := preload("res://src/inventory/inventory_item.gd")
const InventoryScript := preload("res://src/inventory/inventory.gd")
const PlayerStatsScript := preload("res://src/marine/player_stats.gd")
const MarineScript := preload("res://src/marine/marine.gd")
const WeaponRingScript := preload("res://src/weapons/weapon_ring.gd")


func run(t: TestContext) -> void:
	_test_item_tooltip(t)
	_test_grid_view(t)
	await _test_level_up_menu(t)
	await _test_hud_clear_medals(t)
	await _test_hud_xp_animation(t)
	await _test_status_icon(t)
	await _test_reload_debuff(t)
	await _test_shop_offers(t)
	await _test_sell_item(t)


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


func _test_level_up_menu(t: TestContext) -> void:
	t.suite = "LevelUpMenu"
	var inv: Node = InventoryScript.build()
	var st: Node = PlayerStatsScript.new()
	st.souls = 5
	var menu: CanvasLayer = LevelUpMenuScript.new()
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
	t.suite = "LevelUpMenu.shop"
	var inv: Node = InventoryScript.build()
	var st: Node = PlayerStatsScript.new()
	st.souls = 1000                               # plenty to buy
	st.level = 10                                 # allow higher-level rolls
	var menu: CanvasLayer = LevelUpMenuScript.new()
	menu.inventory = inv
	menu.stats = st
	menu._rng.seed = 42                           # deterministic offers
	t.root().add_child(menu)
	await t.frame()
	menu.open(2)
	t.ok(menu._offers.size() == 4, "open() rolls 4 shop offers (got %d)" % menu._offers.size())

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


func _test_sell_item(t: TestContext) -> void:
	t.suite = "LevelUpMenu.sell"
	var inv: Node = InventoryScript.build()
	var st: Node = PlayerStatsScript.new()
	st.souls = 0
	var menu: CanvasLayer = LevelUpMenuScript.new()
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
