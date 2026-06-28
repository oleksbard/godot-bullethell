extends RefCounted
## Enemy + wave tests: spawner, imp lifecycle, portal, wave progression/signals,
## power scaling. Split from run_tests.gd. `t` is the shared TestContext.

const TestContext := preload("res://test/test_context.gd")
const WaveSpawnerScript := preload("res://src/enemies/wave_spawner.gd")
const ImpScript := preload("res://src/enemies/imp.gd")
const PortalScript := preload("res://src/fx/portal.gd")
const IslandShape := preload("res://src/lib/island_shape.gd")
const GunScript := preload("res://src/weapons/gun.gd")
const MarineScript := preload("res://src/marine/marine.gd")
const PlayerStatsScript := preload("res://src/marine/player_stats.gd")
const InventoryScript := preload("res://src/inventory/inventory.gd")


func run(t: TestContext) -> void:
	await _test_wave_spawner(t)
	await _test_imp_die(t)
	await _test_imp_take_damage(t)
	await _test_imp_take_damage_returns_killed(t)
	await _test_imp_xp_drop(t)
	await _test_imp_hit_react(t)
	await _test_imp_emerge(t)
	await _test_imp_attack(t)
	await _test_imp_separation(t)
	await _test_portal_fail(t)
	await _test_wave_progression(t)
	await _test_wave_curve(t)
	await _test_wave_signals(t)
	await _test_wave_power_scaling(t)


func _test_wave_spawner(t: TestContext) -> void:
	t.suite = "WaveSpawner"
	var sp: Node3D = WaveSpawnerScript.new()
	sp.player = Node3D.new()
	t.root().add_child(sp.player)
	t.root().add_child(sp)                  # _ready() starts dripping in wave 1
	t.pump_spawn(sp, 15)

	var imps := t.nodes_in_group("imps")
	t.ok(imps.size() == 15, "the wave drips imps in one at a time (sampled 15, got %d)" % imps.size())

	var all_inside := true
	for imp in imps:
		var p: Vector3 = (imp as Node3D).position
		var ang := atan2(p.z, p.x)
		if Vector2(p.x, p.z).length() > IslandShape.radius(ang):
			all_inside = false
	t.ok(all_inside, "every imp spawns inside the coastline")

	var sp_player: Node = sp.player
	sp.free()                                 # frees the imps too
	sp_player.free()


func _test_imp_die(t: TestContext) -> void:
	t.suite = "Imp.die"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var imp: Node3D = ImpScript.new()
	holder.add_child(imp)
	await t.frame()
	t.ok(t.nodes_in_group("imps").has(imp), "imp registers in the 'imps' group")

	var blood_before := t.nodes_in_group("blood").size()
	imp.die(4)                                # killer passes the blood amount (projectile type)
	t.ok(t.nodes_in_group("imps").size() == 0, "die() removes it from the target group")
	# n directional spray decals + 1 round impact pool laid on top.
	t.ok(t.nodes_in_group("blood").size() - blood_before == 5,
		"die(n) spawns n spray decals + 1 impact pool (%d new)" % (t.nodes_in_group("blood").size() - blood_before))
	await t.frame()                       # let the queued free run
	holder.free()                             # frees gibs + blood too


func _test_imp_take_damage(t: TestContext) -> void:
	t.suite = "Imp.take_damage"
	var holder := Node3D.new()
	t.root().add_child(holder)

	# A tougher (later-wave) imp survives a hit it can't yet afford, then dies.
	var imp: Node3D = ImpScript.new()
	imp.max_hp = 6.0
	imp.hp = 6.0
	holder.add_child(imp)
	await t.frame()
	var blood_before := t.nodes_in_group("blood").size()
	imp.take_damage(GunScript.DAMAGE)             # one 5-dmg bolt — not enough vs 6 HP
	t.ok(t.nodes_in_group("imps").has(imp), "6-HP imp survives a single 5-dmg bolt")
	t.ok(t.nodes_in_group("blood").size() - blood_before == 1,
		"a non-lethal hit leaves exactly 1 blood decal (%d new)" % (t.nodes_in_group("blood").size() - blood_before))
	imp.take_damage(GunScript.DAMAGE)             # second bolt finishes it (10 >= 6)
	t.ok(t.nodes_in_group("imps").size() == 0, "second bolt drops it (HP <= 0 -> die)")

	# A base-HP imp dies to one pistol bolt (dmg 5 >= BASE_HP 3).
	var base: Node3D = ImpScript.new()
	holder.add_child(base)
	await t.frame()
	base.take_damage(GunScript.DAMAGE)
	t.ok(base.is_queued_for_deletion(),
		"base imp (%d HP) dies to one pistol bolt (dmg %d)" % [int(ImpScript.BASE_HP), int(GunScript.DAMAGE)])

	await t.frame()
	holder.free()


func _test_imp_xp_drop(t: TestContext) -> void:
	t.suite = "Imp.xp"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var imp: Node3D = ImpScript.new()
	imp.xp_value = 9.0
	imp.soul_value = 3
	holder.add_child(imp)
	await t.frame()
	var got := [Vector3.ZERO, -1.0, -1]              # [pos, xp, souls]
	imp.died.connect(func(pos: Vector3, xp: float, souls: int) -> void: got[0] = pos; got[1] = xp; got[2] = souls)
	imp.global_position = Vector3(3.0, 0.0, 1.0)
	imp.die()
	t.ok(is_equal_approx(got[1], 9.0), "imp emits its xp_value on death (%.1f)" % got[1])
	t.ok(got[0].is_equal_approx(Vector3(3.0, 0.0, 1.0)), "imp emits its death position")
	t.ok(got[2] == 3, "imp emits its soul_value on death (%d)" % got[2])
	await t.frame()                              # let the queued free run
	holder.free()


func _test_imp_hit_react(t: TestContext) -> void:
	t.suite = "Imp.hit"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var imp: Node3D = ImpScript.new()
	imp.max_hp = 10.0
	imp.hp = 10.0                                  # tough enough to survive the test hit
	holder.add_child(imp)
	await t.frame()                            # _ready builds the model + _anim_mats
	imp.global_position = Vector3(5.0, 0.0, 0.0)

	imp.take_damage(2.0, 1, Vector3(1.0, 0.0, 0.0))   # non-lethal, bolt travelling +X
	t.ok(not imp._dead, "a non-lethal hit doesn't kill")
	t.ok(imp._knock.x > 0.1, "hit shoves the imp along the bolt's travel (knockback)")
	t.ok(imp._slow > 0.0 and imp._hit_flash > 0.0, "hit triggers a brief slow + flash")

	for i in 20:
		imp._update_hit_flash(0.05)                # ~1s later
	t.ok(imp._hit_flash == 0.0, "the hurt-flash decays back to zero")
	holder.free()


func _test_imp_emerge(t: TestContext) -> void:
	t.suite = "Imp.emerge"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var player := Node3D.new()
	holder.add_child(player)                  # at origin
	var imp: Node3D = ImpScript.new()
	imp.player = player
	holder.add_child(imp)
	imp.global_position = Vector3(8.0, 0.0, 0.0)
	imp.emerge(1.0)
	await t.frame()

	var start := imp.global_position
	for i in 10:
		imp._process(0.05)                    # 0.5s elapsed (< emerge time) -> frozen
	t.ok(imp.global_position.distance_to(start) < 0.01, "imp stays put while in the portal")
	t.ok(imp.scale.x < 1.0, "imp is still scaling up mid-emerge (%.2f)" % imp.scale.x)

	for i in 30:
		imp._process(0.05)                    # past 1s -> emerged, free to hunt
	t.ok(imp.global_position.distance_to(start) > 0.5, "imp moves once it has emerged")
	holder.free()


func _test_imp_attack(t: TestContext) -> void:
	t.suite = "Imp.attack"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var m: Node3D = MarineScript.new()
	holder.add_child(m)
	var stats: Node = PlayerStatsScript.new()
	stats.max_health = 50.0
	stats.health = 50.0
	m.add_child(stats)
	m.stats = stats
	var imp: Node3D = ImpScript.new()
	imp.player = m
	imp.attack_damage = 3.0
	holder.add_child(imp)
	await t.frame()
	imp.global_position = m.global_position + Vector3(0.5, 0.0, 0.0)   # inside ATTACK_RANGE

	var before: float = stats.health
	for i in 12:
		imp._process(0.1)                     # > ATTACK_COOLDOWN -> lands at least one hit
	t.ok(stats.health < before, "an imp in melee range damages the player (%.0f -> %.0f)" % [before, stats.health])
	holder.free()


func _test_imp_separation(t: TestContext) -> void:
	t.suite = "Imp.separation"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var player: Node3D = Node3D.new()    # at origin; both imps start inside STOP_DIST
	holder.add_child(player)
	var a: Node3D = ImpScript.new()
	holder.add_child(a)
	a.global_position = Vector3(0.2, 0.0, 0.0)
	var b: Node3D = ImpScript.new()
	holder.add_child(b)
	b.global_position = Vector3(-0.2, 0.0, 0.0)
	a.player = player
	b.player = player
	await t.frame()                  # _ready -> both in the group

	var before := a.global_position.distance_to(b.global_position)
	for i in 40:
		a._process(0.05)
		b._process(0.05)
	var after := a.global_position.distance_to(b.global_position)
	t.ok(after > before + 0.5, "overlapping imps push apart (%.2f -> %.2f)" % [before, after])
	holder.free()


func _test_portal_fail(t: TestContext) -> void:
	t.suite = "Portal.fail"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var imp: Node3D = ImpScript.new()
	holder.add_child(imp)
	var portal: Node3D = PortalScript.new()
	portal.imp = imp                          # set before add_child so _ready watches it
	holder.add_child(portal)
	await t.frame()

	t.ok(not portal._failed, "portal is steady while its imp lives")
	imp.free()                                # imp killed before it finished emerging
	portal._process(0.05)
	t.ok(portal._failed, "portal fails when its imp dies while the portal is active")
	holder.free()


func _test_wave_progression(t: TestContext) -> void:
	t.suite = "WaveSpawner.waves"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var sp: Node3D = WaveSpawnerScript.new()
	sp.player = Node3D.new()
	holder.add_child(sp.player)
	holder.add_child(sp)                      # _ready -> starts dripping in wave 1

	t.pump_spawn(sp, 32)
	t.ok(t.nodes_in_group("imps").size() == 32, "wave 1 drips in to 32 imps (got %d)" % t.nodes_in_group("imps").size())
	var w1_interval: float = sp._spawn_interval

	for imp in t.nodes_in_group("imps"):
		imp.die()                             # clear the field; die() leaves the group at once
	sp._process(0.1)                          # notices the clear -> emits wave_cleared, then idles
	t.ok(sp._awaiting_next, "a cleared wave idles for the menu flow (no free-running timer)")
	sp.resume_after_menu()                    # Main calls this when the wave menu closes
	sp._process(WaveSpawnerScript.WAVE_DELAY + 0.1) # breather elapses -> next wave begins
	t.pump_spawn(sp, 38)
	t.ok(t.nodes_in_group("imps").size() == 38, "next wave grows to 38 imps (+6 linear) (got %d)" % t.nodes_in_group("imps").size())
	t.ok(sp._spawn_interval < w1_interval,
		"wave 2 drips faster than wave 1 (%.2f < %.2f s)" % [sp._spawn_interval, w1_interval])

	await t.frame()
	holder.free()


## Drives _start_wave() directly (no real spawning) to check the count curve, the horde
## multiplier, and the elite-wave champion buff.
func _test_wave_curve(t: TestContext) -> void:
	t.suite = "WaveSpawner.curve"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var sp: Node3D = WaveSpawnerScript.new()
	sp.player = Node3D.new()
	holder.add_child(sp.player)
	holder.add_child(sp)                      # _ready -> wave 1

	t.ok(sp._to_spawn == 32, "wave 1 baseline is 32 (got %d)" % sp._to_spawn)
	sp._start_wave()                          # wave 2
	t.ok(sp._to_spawn == 38, "wave 2 climbs by +6 to 38 (got %d)" % sp._to_spawn)

	for _i in 3:
		sp._start_wave()                      # waves 3, 4, 5
	t.ok(sp._to_spawn == 84, "wave 5 horde = 56 x1.5 = 84 (got %d)" % sp._to_spawn)
	t.ok(sp._champions_left == 0, "a plain horde wave seeds no champions")

	for _i in 5:
		sp._start_wave()                      # waves 6..10
	t.ok(sp._to_spawn == 129, "wave 10 elite-horde count = 86 x1.5 = 129 (got %d)" % sp._to_spawn)
	t.ok(sp._champions_left == 1, "wave 10 seeds 1 champion (got %d)" % sp._champions_left)

	sp._process(0.2)                          # portal in the wave's first imp -> a champion
	var imps := t.nodes_in_group("imps")
	var first: Node = imps[0] if imps.size() > 0 else null
	var champ_hp := (ImpScript.BASE_HP + 9.0 * WaveSpawnerScript.HP_PER_WAVE) * WaveSpawnerScript.CHAMP_HP_MULT
	t.ok(first != null and is_equal_approx(first.body_scale, WaveSpawnerScript.CHAMP_SIZE_MULT),
		"the elite wave's first imp is an oversized champion")
	t.ok(first != null and is_equal_approx(first.max_hp, champ_hp),
		"the champion is x4 HP (%.0f, want %.0f)" % [first.max_hp if first != null else 0.0, champ_hp])
	t.ok(first != null and first.soul_value >= 1 + WaveSpawnerScript.CHAMP_BONUS_SOULS,
		"the champion drops a soul jackpot (souls %d)" % (first.soul_value if first != null else 0))

	await t.frame()
	holder.free()


func _test_wave_signals(t: TestContext) -> void:
	t.suite = "WaveSpawner.signals"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var sp: Node3D = WaveSpawnerScript.new()
	sp.player = Node3D.new()
	holder.add_child(sp.player)

	var started := [0]
	var spawned := [0]
	var cleared := [0]
	var first_xp := [-1.0]
	sp.wave_started.connect(func(w: int) -> void: started[0] = w)
	sp.imp_spawned.connect(func(imp: Node) -> void:
		spawned[0] += 1
		if first_xp[0] < 0.0:
			first_xp[0] = imp.xp_value)
	sp.wave_cleared.connect(func() -> void: cleared[0] += 1)

	holder.add_child(sp)                              # _ready -> _start_wave() -> wave_started(1)
	t.ok(started[0] == 1, "wave_started fires with wave 1 on ready (got %d)" % started[0])

	t.pump_spawn(sp, 32)
	t.ok(spawned[0] == 32, "imp_spawned fires once per spawned imp (got %d)" % spawned[0])
	t.ok(is_equal_approx(first_xp[0], ImpScript.BASE_XP),
		"a wave-1 imp carries BASE_XP (%.1f)" % first_xp[0])

	for imp in t.nodes_in_group("imps"):
		imp.die()
	sp._process(0.1)                                  # notices the field is clear
	t.ok(cleared[0] == 1, "wave_cleared fires when the field clears (got %d)" % cleared[0])

	await t.frame()
	holder.free()


func _test_wave_power_scaling(t: TestContext) -> void:
	t.suite = "WaveSpawner.power"
	# Baseline spawner (no inventory -> power factor 1.0).
	var h1 := Node3D.new()
	t.root().add_child(h1)
	var base_sp: Node3D = WaveSpawnerScript.new()
	base_sp.player = Node3D.new()
	h1.add_child(base_sp.player)
	h1.add_child(base_sp)                         # _ready -> _start_wave computes _to_spawn
	var base_to_spawn: int = base_sp._to_spawn

	# Powerful loadout -> bigger wave + tougher imps.
	var h2 := Node3D.new()
	t.root().add_child(h2)
	var inv: Node = InventoryScript.build()
	for it in inv.equipped_pistols():
		it.item_level = 8                         # crank loadout power up
	var sp: Node3D = WaveSpawnerScript.new()
	sp.player = Node3D.new()
	h2.add_child(sp.player)
	sp.inventory = inv
	h2.add_child(sp)                              # _ready -> _start_wave reads the power factor
	t.ok(sp._power_factor > 1.0, "loadout power raises the wave's power factor (%.1f)" % sp._power_factor)
	t.ok(sp._to_spawn > base_to_spawn, "a stronger loadout spawns more imps (%d > %d)" % [sp._to_spawn, base_to_spawn])

	# A single imp from the powered spawner is tougher than a base wave-1 imp.
	t.pump_spawn(sp, 1)
	var imps := t.nodes_in_group("imps")
	var hp: float = imps[0].max_hp if imps.size() > 0 else 0.0
	t.ok(imps.size() > 0 and hp > ImpScript.BASE_HP,
		"a stronger loadout makes imps tougher (max_hp %.1f > base %.1f)" % [hp, ImpScript.BASE_HP])

	await t.frame()
	h1.free()
	h2.free()
	inv.free()


func _test_imp_take_damage_returns_killed(t: TestContext) -> void:
	t.suite = "Imp.take_damage"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var imp: Node3D = ImpScript.new()
	imp.max_hp = 10.0
	imp.hp = 10.0
	holder.add_child(imp)
	await t.frame()                                  # _ready builds the model
	t.ok(imp.enemy_type() == "Imp", "imp reports its enemy type")
	t.ok(imp.take_damage(4.0) == false, "a non-lethal hit returns false")
	t.ok(imp.take_damage(99.0) == true, "the lethal hit returns true")
	holder.free()
