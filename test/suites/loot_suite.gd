extends RefCounted
## Loot + progression tests: XP orbs/field, XP curve, souls, item level/power/rarity,
## loadout power. Split from run_tests.gd. `t` is the shared TestContext.

const TestContext := preload("res://test/test_context.gd")
const XpOrbScript := preload("res://src/loot/xp_orb.gd")
const XpOrbFieldScript := preload("res://src/loot/xp_orb_field.gd")
const HealthVialScript := preload("res://src/loot/health_vial.gd")
const HealthVialFieldScript := preload("res://src/loot/health_vial_field.gd")
const ImpScript := preload("res://src/enemies/imp.gd")
const MarineScript := preload("res://src/marine/marine.gd")
const PlayerStatsScript := preload("res://src/marine/player_stats.gd")
const HudScript := preload("res://src/ui/hud.gd")
const InventoryItemScript := preload("res://src/inventory/inventory_item.gd")
const InventoryScript := preload("res://src/inventory/inventory.gd")
const DamageNumberScript := preload("res://src/fx/damage_number.gd")


func run(t: TestContext) -> void:
	await _test_xp_orb(t)
	await _test_xp_orb_field(t)
	await _test_wave_drain(t)
	_test_xp_curve(t)
	await _test_souls(t)
	_test_spend_souls(t)
	_test_item_level_and_power(t)
	_test_rarity_roll(t)
	_test_loadout_power(t)
	_test_loadout_power_artifacts(t)
	_test_player_heal(t)
	await _test_health_vial(t)
	await _test_health_vial_field(t)
	await _test_damage_number_accumulates(t)


func _test_xp_orb(t: TestContext) -> void:
	t.suite = "XpOrb"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var player := Node3D.new()
	holder.add_child(player)                          # at origin

	# In magnet range -> flies toward the marine.
	var orb: Node3D = XpOrbScript.new()
	orb.player = player
	holder.add_child(orb)
	orb.set_process(false)
	orb.global_position = Vector3(2.0, 0.5, 0.0)      # dist 2 < MAGNET, > COLLECT
	await t.frame()
	var d0 := orb.global_position.distance_to(player.global_position)
	for i in 5:
		orb._process(0.05)
	var d1 := orb.global_position.distance_to(player.global_position)
	t.ok(d1 < d0 - 0.1, "an orb within magnet range flies toward the marine (%.2f -> %.2f)" % [d0, d1])
	orb.free()

	# Out of magnet range -> stays put; bank_drift() makes it rise and shrink out (never flies in).
	var orb2: Node3D = XpOrbScript.new()
	orb2.player = player
	holder.add_child(orb2)
	orb2.set_process(false)
	orb2.global_position = Vector3(10.0, 0.5, 0.0)    # dist 10 > MAGNET
	await t.frame()
	var e0 := orb2.global_position.distance_to(player.global_position)
	for i in 5:
		orb2._process(0.05)
	var e1 := orb2.global_position.distance_to(player.global_position)
	t.ok(absf(e1 - e0) < 0.1, "an orb beyond magnet range stays put (%.2f -> %.2f)" % [e0, e1])
	orb2.bank_drift()
	var y0 := orb2.position.y
	for i in 60:
		if orb2.is_queued_for_deletion():
			break
		orb2._process(0.05)
	t.ok(orb2.position.y > y0 and orb2.is_queued_for_deletion(),
		"bank_drift() rises the mote off to the vault and frees it (never flies to the marine)")
	if not orb2.is_queued_for_deletion():
		orb2.free()

	# Within collect range -> credits XP once and frees itself.
	var m: Node3D = MarineScript.new()
	holder.add_child(m)
	var st: Node = PlayerStatsScript.new()
	st.xp = 0.0
	st.xp_to_next = 100.0
	m.add_child(st)
	m.stats = st
	await t.frame()
	var orb3: Node3D = XpOrbScript.new()
	orb3.player = m
	orb3.xp_value = 5.0
	holder.add_child(orb3)
	orb3.set_process(false)
	orb3.global_position = m.global_position + Vector3(0.3, 0.0, 0.0)   # within COLLECT
	await t.frame()
	orb3._process(0.05)
	t.ok(orb3.is_queued_for_deletion(), "an orb within collect range is collected (freed)")
	t.ok(is_equal_approx(st.xp, 5.0), "collecting an orb credits the player's XP (%.1f)" % st.xp)
	t.ok(st.souls == 1, "collecting an orb banks one soul (souls %d)" % st.souls)
	holder.free()


func _test_xp_orb_field(t: TestContext) -> void:
	t.suite = "XpOrbField"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var player := Node3D.new()
	holder.add_child(player)
	var field: Node3D = XpOrbFieldScript.new()
	field.player = player
	holder.add_child(field)

	var imp: Node3D = ImpScript.new()
	imp.xp_value = 4.0
	holder.add_child(imp)
	await t.frame()
	field.on_imp_spawned(imp)                         # what Main wires to spawner.imp_spawned

	var before := field.get_child_count()
	imp.global_position = Vector3(2.0, 0.0, 0.0)
	imp.die()                                         # emits died -> field.drop_orb
	t.ok(field.get_child_count() == before + 1, "a tracked imp's death drops one orb into the field")

	var n0 := field.get_child_count()
	field.drop_orb(Vector3(5.0, 0.0, 5.0), 0.0, 4)    # a 4-soul kill bursts into 4 motes (1 main + 3 bonus)
	t.ok(field.get_child_count() == n0 + 4, "a 4-soul drop bursts into 4 motes (got %d)" % (field.get_child_count() - n0))

	# With souls in the vault, each kill drops one EXTRA mote and drains the vault by one.
	var st: Node = PlayerStatsScript.new()
	st.bank_souls(2)
	field.stats = st
	var n1 := field.get_child_count()
	field.drop_orb(Vector3.ZERO, 0.0, 1)              # 1 main mote + 1 bonus pulled from the vault
	t.ok(field.get_child_count() == n1 + 2, "a kill drops one bonus mote from the vault (got %d)" % (field.get_child_count() - n1))
	t.ok(st.banked_souls == 1, "the bonus drop drains the vault by one (banked %d)" % st.banked_souls)
	field.drop_orb(Vector3.ZERO, 0.0, 1)              # drains the last banked soul
	field.drop_orb(Vector3.ZERO, 0.0, 1)              # vault empty -> no more bonus motes
	t.ok(st.banked_souls == 0, "the vault empties and stops giving bonuses (banked %d)" % st.banked_souls)

	await t.frame()
	st.free()
	holder.free()


## On a wave clear the field banks every uncollected mote (soul -> vault, XP still credited to
## the player) and only emits `drained` (which Main uses to open the wave menu) once the
## leftover motes have drifted off and freed themselves.
func _test_wave_drain(t: TestContext) -> void:
	t.suite = "XpOrbField.drain"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var marine: Node3D = MarineScript.new()
	holder.add_child(marine)
	var st: Node = PlayerStatsScript.new()
	st.xp_to_next = 100.0                             # keep add_xp from levelling during the test
	marine.add_child(st)
	marine.stats = st
	var field: Node3D = XpOrbFieldScript.new()
	field.player = marine
	field.stats = st
	holder.add_child(field)
	await t.frame()
	marine.set_process(false)
	var fired := [0]
	field.drained.connect(func() -> void: fired[0] += 1)

	field.drop_orb(Vector3(9.0, 0.0, 0.0), 3.0, 1)    # one leftover mote carrying 3 XP, far from the marine
	var orb := field.get_child(field.get_child_count() - 1)
	orb.set_process(false)                            # freeze it so the drain wait is driven by hand
	field.bank_leftovers()
	t.ok(orb._banking, "bank_leftovers() sets every leftover mote drifting off to the vault")
	t.ok(st.banked_souls == 1, "the leftover soul is sent to the vault (banked %d)" % st.banked_souls)
	t.ok(is_equal_approx(st.xp, 3.0), "leftover XP is still credited to the player (%.1f)" % st.xp)
	field._process(0.1)
	t.ok(fired[0] == 0, "drained holds while a mote is still drifting in the field")

	orb.free()                                        # the mote finished drifting off (freed)
	field._process(0.1)
	t.ok(fired[0] == 1, "drained fires once the field has emptied")

	field.bank_leftovers()                            # no leftover motes -> menu can open at once
	field._process(0.1)
	t.ok(fired[0] == 2, "an empty field drains immediately")
	holder.free()


## Brotato-style quadratic XP curve: xp_for(lvl) == (lvl+3)^2, and add_xp wraps
## levels by that curve (not a flat 10).
func _test_xp_curve(t: TestContext) -> void:
	t.suite = "PlayerStats.curve"
	var st: Node = PlayerStatsScript.new()
	t.ok(st.xp_for(1) == 16.0 and st.xp_for(2) == 25.0 and st.xp_for(3) == 36.0,
		"xp_for is (lvl+3)^2: 16 / 25 / 36 (got %.0f / %.0f / %.0f)"
			% [st.xp_for(1), st.xp_for(2), st.xp_for(3)])
	t.ok(st.xp_to_next == st.xp_for(1), "initial xp_to_next == xp_for(1)")
	st.add_xp(15.0)
	t.ok(st.level == 1, "15 XP < 16 -> still level 1")
	st.add_xp(2.0)                                # total 17: clears 16, 1 carried into level 2
	t.ok(st.level == 2 and absf(st.xp - 1.0) < 0.001, "17 XP -> level 2, 1 XP into the next")
	t.ok(st.xp_to_next == 25.0, "level 2 now needs 25 XP")
	st.free()


func _test_souls(t: TestContext) -> void:
	t.suite = "Souls"
	var stats: Node = PlayerStatsScript.new()
	var got := [-1]
	stats.souls_changed.connect(func(s: int) -> void: got[0] = s)
	stats.add_souls()
	t.ok(stats.souls == 1 and got[0] == 1, "add_souls() banks one and emits (souls %d)" % stats.souls)
	stats.add_souls(3)
	t.ok(stats.souls == 4, "add_souls(n) accumulates (souls %d)" % stats.souls)

	var hud: CanvasLayer = HudScript.new()
	hud.stats = stats
	t.root().add_child(hud)
	await t.frame()                           # _ready builds the counter + binds
	t.ok(hud._souls_count.text == "4", "HUD counter shows the current souls (%s)" % hud._souls_count.text)
	stats.add_souls(2)
	t.ok(hud._souls_count.text == "6", "HUD counter updates on souls_changed (%s)" % hud._souls_count.text)

	# The vault counter shows when souls are banked and hides once it empties.
	t.ok(not hud._bank_orb.visible, "the vault counter is hidden while the vault is empty")
	stats.bank_souls(3)
	t.ok(hud._bank_count.text == "3" and hud._bank_orb.visible, "HUD shows the vault counter when souls are banked (%s)" % hud._bank_count.text)
	stats.draw_banked_soul()
	stats.draw_banked_soul()
	stats.draw_banked_soul()
	t.ok(not hud._bank_orb.visible, "the vault counter hides once the vault empties")
	hud.free()
	stats.free()


func _test_spend_souls(t: TestContext) -> void:
	t.suite = "PlayerStats.spend"
	var st: Node = PlayerStatsScript.new()
	st.add_souls(30)
	var emitted := [-1]
	st.souls_changed.connect(func(s: int) -> void: emitted[0] = s)
	t.ok(st.spend_souls(10) and st.souls == 20, "spend deducts when affordable (souls %d)" % st.souls)
	t.ok(emitted[0] == 20, "spend emits souls_changed")
	t.ok(not st.spend_souls(999) and st.souls == 20, "spend refuses when unaffordable (no change)")
	t.ok(st.total_souls == 30, "total_souls is the monotonic lifetime sum (30), not the spent-down balance (got %d)" % st.total_souls)
	st.add_souls(5)
	t.ok(st.souls == 25 and st.total_souls == 35, "add_souls raises both souls and total_souls")
	st.free()


func _test_item_level_and_power(t: TestContext) -> void:
	t.suite = "Item.level"
	var p1 := InventoryItemScript.pistol()
	t.ok(p1.level() == 1 and p1.rarity() == "Normal" and p1.power() == 10,
		"level-1 pistol: Normal, power 10 (got L%d %s pow %d)" % [p1.level(), p1.rarity(), p1.power()])
	var p5 := InventoryItemScript.pistol()
	p5.item_level = 5
	t.ok(p5.rarity() == "Unique", "level-5 pistol is Unique (got %s)" % p5.rarity())
	t.ok(roundi(p5.damage_value()) == 13, "level-5 damage is 13 (got %d)" % roundi(p5.damage_value()))
	t.ok(p5.power() > p1.power(), "higher level -> more power (%d > %d)" % [p5.power(), p1.power()])

	# Buy/sell prices: buy = round(10 * level^1.5); sell = round(65% of buy).
	t.ok(p1.buy_price() == 10 and p1.sell_price() == roundi(10.0 * 0.65),
		"L1 pistol buys for 10, sells for %d (got %d / %d)" % [roundi(10.0 * 0.65), p1.buy_price(), p1.sell_price()])
	t.ok(p5.buy_price() == 112 and p5.sell_price() == roundi(112.0 * 0.65),
		"L5 pistol price scales (buy %d, sell %d)" % [p5.buy_price(), p5.sell_price()])

	# Sawed-off carries a higher per-weapon base price (14); derived prices scale from it.
	var sg1 := InventoryItemScript.for_kind(InventoryItemScript.Kind.SAWED_OFF)
	t.ok(sg1.buy_price() == 14, "L1 sawed-off buys for 14 (dearer than the pistol's 10, got %d)" % sg1.buy_price())
	var sg5 := InventoryItemScript.for_kind(InventoryItemScript.Kind.SAWED_OFF)
	sg5.item_level = 5
	t.ok(sg5.buy_price() == roundi(14.0 * pow(5.0, 1.5)), "L5 sawed-off price scales from its 14 base (got %d)" % sg5.buy_price())

	# Magazine + reload: 7 rounds; L1 reloads in 1.5s; higher level reloads faster.
	t.ok(p1.magazine_size() == 7, "pistol magazine is 7")
	t.ok(is_equal_approx(p1.reload_time_value(), 1.5), "L1 reload time is 1.5s (got %.2f)" % p1.reload_time_value())
	t.ok(p5.reload_time_value() < p1.reload_time_value(),
		"a higher-level pistol reloads faster (%.2f < %.2f)" % [p5.reload_time_value(), p1.reload_time_value()])

	# Power is strictly monotonic in level, and rarity bands map as designed.
	var mono := true
	var prev := 0
	var bands := {1: "Normal", 2: "Rare", 3: "Rare", 4: "Unique", 5: "Unique", 6: "Legendary", 8: "Legendary"}
	var bands_ok := true
	for lvl in range(1, 9):
		var pi := InventoryItemScript.pistol()
		pi.item_level = lvl
		if pi.power() <= prev:
			mono = false
		prev = pi.power()
		if bands.has(lvl) and pi.rarity() != bands[lvl]:
			bands_ok = false
	t.ok(mono, "power strictly increases with level 1..8")
	t.ok(bands_ok, "rarity bands map Normal/Rare/Unique/Legendary correctly")


func _test_rarity_roll(t: TestContext) -> void:
	t.suite = "Item.roll"
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	# A level-1 player can only ever roll item level 1 (max_level clamps to 1).
	var only_one := true
	for i in 50:
		if InventoryItemScript.roll_level(1, 0.0, rng) != 1:
			only_one = false
	t.ok(only_one, "a level-1 player only ever rolls item level 1")

	# Same seed, higher rarity_bonus -> higher mean rolled level (the curve flattens up).
	rng.seed = 999
	var sum_lo := 0.0
	for i in 400:
		sum_lo += InventoryItemScript.roll_level(11, 0.0, rng)
	rng.seed = 999
	var sum_hi := 0.0
	for i in 400:
		sum_hi += InventoryItemScript.roll_level(11, 0.5, rng)
	t.ok(sum_hi > sum_lo, "rarity_bonus raises the mean rolled level (%.2f > %.2f)" % [sum_hi / 400.0, sum_lo / 400.0])

	# Rolls never exceed max_level for the player level (player 5 -> max 3).
	rng.seed = 7
	var within := true
	for i in 200:
		var l := InventoryItemScript.roll_level(5, 0.9, rng)
		if l < 1 or l > 3:
			within = false
	t.ok(within, "rolls stay within 1..max_level for the player level")


func _test_loadout_power(t: TestContext) -> void:
	t.suite = "Inventory.power"
	var inv: Node = InventoryScript.build()
	t.ok(inv.loadout_power() == 20, "two level-1 pistols -> loadout power 20 (got %d)" % inv.loadout_power())
	inv.equipped_pistols()[0].item_level = 5      # level up an equipped pistol in place
	t.ok(inv.loadout_power() > 20, "a higher-level equipped pistol raises loadout power (%d)" % inv.loadout_power())
	var p_before: int = inv.loadout_power()
	var hi := InventoryItemScript.pistol()
	hi.item_level = 6
	inv.add_to_stash(hi)
	t.ok(inv.loadout_power() == p_before, "a stashed pistol doesn't count toward loadout power")
	inv.free()


## A global damage artifact in the backpack raises the loadout power readout. (3,1) is a
## valid empty backpack cell — Furnace is GLOBAL, so position only needs to be placed.
func _test_loadout_power_artifacts(t: TestContext) -> void:
	t.suite = "Inventory.loadout_power"
	var inv: Node = InventoryScript.build()
	var base: int = inv.loadout_power()
	inv.backpack.place(InventoryItemScript.for_kind(InventoryItemScript.Kind.THE_FURNACE), Vector2i(3, 1))
	t.ok(inv.loadout_power() > base, "a global damage artifact raises loadout power (%d > %d)" % [inv.loadout_power(), base])
	inv.free()


## PlayerStats.heal: restores HP, clamps to max, and returns only what was actually restored.
func _test_player_heal(t: TestContext) -> void:
	t.suite = "PlayerStats.heal"
	var s: Node = PlayerStatsScript.new()
	s.max_health = 60.0
	s.health = 40.0
	var healed: float = s.heal(15.0)
	t.ok(healed == 15.0 and s.health == 55.0, "heal restores HP and returns the amount (%.0f)" % healed)
	healed = s.heal(100.0)
	t.ok(healed == 5.0 and s.health == 60.0, "heal clamps to max, returns only what it restored (%.0f)" % healed)
	healed = s.heal(10.0)
	t.ok(healed == 0.0, "healing at full HP restores nothing (%.0f)" % healed)
	s.free()


## A vial heals a hurt marine on contact and is consumed; a full-health marine leaves it.
func _test_health_vial(t: TestContext) -> void:
	t.suite = "HealthVial"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var marine: Node3D = MarineScript.new()
	holder.add_child(marine)
	var stats: Node = PlayerStatsScript.new()
	marine.add_child(stats)
	marine.stats = stats
	await t.frame()                       # marine _ready builds the rig
	marine.set_process(false)             # only the vial's _process is driven below

	# Hurt marine within reach -> healed and consumed.
	stats.health = 10.0
	var vial: Node3D = HealthVialScript.new()
	vial.player = marine
	vial.heal_amount = 20.0
	holder.add_child(vial)
	vial.set_process(false)                         # drive _process by hand (else it auto-collects mid-frame)
	vial.global_position = Vector3(0.5, 0.0, 0.0)   # within COLLECT_RADIUS of the marine at origin
	await t.frame()
	vial._process(0.05)
	t.ok(stats.health == 30.0, "a hurt marine in reach is healed by the vial (10 -> %.0f)" % stats.health)
	t.ok(vial.is_queued_for_deletion(), "the vial is consumed on a real heal")

	# Full marine -> vial stays (no waste).
	stats.health = stats.max_health
	var vial2: Node3D = HealthVialScript.new()
	vial2.player = marine
	holder.add_child(vial2)
	vial2.set_process(false)
	vial2.global_position = Vector3(0.5, 0.0, 0.0)
	await t.frame()
	vial2._process(0.05)
	t.ok(not vial2.is_queued_for_deletion(), "a full-health marine leaves the vial on the map")
	holder.free()


## The drop field never exceeds MAX_VIALS, and skips dropping entirely at full HP.
func _test_health_vial_field(t: TestContext) -> void:
	t.suite = "HealthVialField"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var stats: Node = PlayerStatsScript.new()
	holder.add_child(stats)
	stats.health = 10.0                   # hurt -> drops allowed
	var player := Node3D.new()
	holder.add_child(player)
	player.global_position = Vector3(100.0, 0.0, 0.0)   # far away -> dropped vials never auto-collect
	var field: Node3D = HealthVialFieldScript.new()
	field.player = player
	field.stats = stats
	holder.add_child(field)
	await t.frame()
	field.set_process(false)
	field.drop_chance = 1.0               # force the per-interval roll so drops are deterministic here

	# Badly hurt (down 50, vials heal 20) -> fills to the hard cap MAX_VIALS and stops.
	for i in 10:
		field._process(HealthVialFieldScript.DROP_INTERVAL + 1.0)
	var n: int = t.nodes_in_group(HealthVialScript.GROUP).size()
	t.ok(n == HealthVialFieldScript.MAX_VIALS, "the field fills to MAX_VIALS and stops (%d)" % n)

	# Clear the map, fill the marine -> no further drops.
	for v in t.nodes_in_group(HealthVialScript.GROUP):
		v.free()
	stats.health = stats.max_health
	for i in 5:
		field._process(HealthVialFieldScript.DROP_INTERVAL + 1.0)
	var m: int = t.nodes_in_group(HealthVialScript.GROUP).size()
	t.ok(m == 0, "a full-health marine gets no health drops (%d)" % m)

	# Down only 10 HP: one 20-HP vial already covers the gap -> never a second.
	stats.health = stats.max_health - 10.0
	for i in 10:
		field._process(HealthVialFieldScript.DROP_INTERVAL + 1.0)
	var k: int = t.nodes_in_group(HealthVialScript.GROUP).size()
	t.ok(k == 1, "drops no more vials than the missing HP needs (down 10 -> %d)" % k)
	holder.free()


## Repeated hits accumulate into one floating number (which grows, capped at BASE_FONT).
func _test_damage_number_accumulates(t: TestContext) -> void:
	t.suite = "DamageNumber"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var n: Node3D = DamageNumberScript.spawn(holder, Vector3.ZERO, 5.0, Color.WHITE)
	await t.frame()
	var f0: int = n.font_size
	n.add(7.0)
	n.add(7.0)
	t.ok(is_equal_approx(n._amount, 19.0), "repeated hits accumulate into one number (got %s)" % n._amount)
	t.ok(n.text == "19", "the displayed text reflects the running total")
	t.ok(n.font_size > f0, "the number grows as it accumulates")
	t.ok(n.font_size <= DamageNumberScript.BASE_FONT, "font growth is capped at BASE_FONT")
	holder.free()
