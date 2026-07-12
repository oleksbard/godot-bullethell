extends RefCounted
## Enemy + wave tests: spawner, imp lifecycle, portal, wave progression/signals,
## power scaling. Split from run_tests.gd. `t` is the shared TestContext.

const TestContext := preload("res://test/test_context.gd")
const WaveSpawnerScript := preload("res://src/enemies/wave_spawner.gd")
const ImpScript := preload("res://src/enemies/imp.gd")
const GoreScript := preload("res://src/fx/gore.gd")
const ZombieScript := preload("res://src/enemies/zombie.gd")
const RevenantScript := preload("res://src/enemies/revenant.gd")
const EnemyBoltScript := preload("res://src/fx/enemy_bolt.gd")
const LeapCoordinatorScript := preload("res://src/enemies/leap_coordinator.gd")
const BuffCoordinatorScript := preload("res://src/enemies/buff_coordinator.gd")
const RevenantCoordinatorScript := preload("res://src/enemies/revenant_coordinator.gd")
const PortalScript := preload("res://src/fx/portal.gd")
const IslandShape := preload("res://src/lib/island_shape.gd")
const GunScript := preload("res://src/weapons/gun.gd")
const MarineScript := preload("res://src/marine/marine.gd")
const PlayerStatsScript := preload("res://src/marine/player_stats.gd")
const InventoryScript := preload("res://src/inventory/inventory.gd")


func run(t: TestContext) -> void:
	await _test_wave_spawner(t)
	await _test_imp_die(t)
	await _test_gore_mixed(t)
	await _test_gore_direction(t)
	await _test_zombie(t)
	await _test_imp_take_damage(t)
	await _test_imp_take_damage_returns_killed(t)
	await _test_imp_xp_drop(t)
	await _test_imp_hit_react(t)
	await _test_knockback_falloff(t)
	await _test_imp_emerge(t)
	await _test_imp_attack(t)
	await _test_imp_separation(t)
	await _test_portal_fail(t)
	await _test_wave_progression(t)
	await _test_wave_curve(t)
	await _test_zombie_budget(t)
	await _test_wave_signals(t)
	await _test_wave_power_scaling(t)
	_test_leap_coordinator(t)
	_test_buff_coordinator(t)
	await _test_speed_buff(t)
	await _test_revenant(t)
	_test_revenant_share(t)
	await _test_enemy_bolt_only_hits_player(t)
	await _test_revenant_fires(t)
	await _test_revenant_repositions(t)
	await _test_revenant_barrage_fan(t)
	_test_revenant_coordinator(t)


## Point cost of a spawned enemy, matching the spawner's budget (imp 1 / zombie 2 / revenant 3).
func _cost_of(e: Node) -> int:
	match e.enemy_type():
		"Zombie": return WaveSpawnerScript.ZOMBIE_COST
		"Revenant": return WaveSpawnerScript.REVENANT_COST
		_: return 1


## Pump the spawner until the current wave has spent its whole point budget.
func _drain(sp: Node) -> void:
	for _i in 600:
		if sp._to_spawn <= 0:
			return
		sp._process(0.2)


## Total point cost of every live enemy (should equal the wave's budget once drained).
func _live_points(t: TestContext) -> int:
	var points := 0
	for e in t.nodes_in_group("imps"):
		points += _cost_of(e)
	return points


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

	var gibs_before := t.nodes_in_group("gibs").size()
	imp.die(4.0)                              # killer passes the blow's damage
	t.ok(t.nodes_in_group("imps").size() == 0, "die() removes it from the target group")
	# Gib count scales with the killing damage (x KILL_GIBS_PER_DAMAGE); all flying body parts (no decals).
	var expect_die := int(round(4.0 * GoreScript.KILL_GIBS_PER_DAMAGE))
	t.ok(t.nodes_in_group("gibs").size() - gibs_before == expect_die,
		"die(dmg) throws round(dmg x rate) chunks (%d new)" % (t.nodes_in_group("gibs").size() - gibs_before))
	await t.frame()                       # let the queued free run
	holder.free()                             # frees the gibs too


func _test_gore_mixed(t: TestContext) -> void:
	t.suite = "Gore.mixed"
	var holder := Node3D.new()
	t.root().add_child(holder)
	await t.frame()
	# Mixed gib colours: round(damage x rate) chunks, tinted from the list.
	var before := t.nodes_in_group("gibs").size()
	GoreScript.spawn_death(holder, Vector3.ZERO, Color(1, 0, 0), 6.0, Vector3(0, 0, -1),
		[Color(1, 0, 0), Color(0, 1, 0)])
	var expect6 := int(round(6.0 * GoreScript.KILL_GIBS_PER_DAMAGE))
	t.ok(t.nodes_in_group("gibs").size() - before == expect6,
		"mixed death = round(6 x rate) chunks (%d new)" % (t.nodes_in_group("gibs").size() - before))
	# Empty colour list reproduces the single-tint path, same count.
	before = t.nodes_in_group("gibs").size()
	GoreScript.spawn_death(holder, Vector3.ZERO, Color(1, 0, 0), 4.0, Vector3(0, 0, -1))
	var expect4 := int(round(4.0 * GoreScript.KILL_GIBS_PER_DAMAGE))
	t.ok(t.nodes_in_group("gibs").size() - before == expect4,
		"default (empty list) = round(4 x rate) chunks (%d new)" % (t.nodes_in_group("gibs").size() - before))
	# A runaway damage is clamped to the per-burst ceiling.
	before = t.nodes_in_group("gibs").size()
	GoreScript.spawn_death(holder, Vector3.ZERO, Color(1, 0, 0), 500.0)
	t.ok(t.nodes_in_group("gibs").size() - before == GoreScript.GIB_CAP,
		"a huge damage is capped at GIB_CAP (%d new)" % (t.nodes_in_group("gibs").size() - before))
	await t.frame()
	holder.free()


## Every chunk is launched away from the blow (forward along hit_dir) and gets at least
## SPEED_MIN of horizontal throw — so none spray back toward the player or pile on the corpse.
func _test_gore_direction(t: TestContext) -> void:
	t.suite = "Gore.direction"
	var holder := Node3D.new()
	t.root().add_child(holder)
	await t.frame()
	var fwd := Vector2(0.0, -1.0)                 # bolt travels -Z; chunks should fly -Z, away from the blow
	GoreScript.spawn_death(holder, Vector3.ZERO, Color(1, 0, 0), 8, Vector3(0.0, 0.0, -1.0))
	var all_forward := true
	var all_thrown := true
	for g in holder.get_children():               # only the chunks this burst spawned (not other tests')
		var horiz := Vector2(g._vel.x, g._vel.z)
		if horiz.dot(fwd) <= 0.0:
			all_forward = false                   # went sideways-back / toward the player
		if horiz.length() < GoreScript.SPEED_MIN - 0.01:
			all_thrown = false                    # barely moved -> would pile
	t.ok(all_forward, "every chunk is launched away from the blow (forward along hit_dir)")
	t.ok(all_thrown, "every chunk gets >= SPEED_MIN horizontal throw (no pilers)")
	holder.free()


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
	var gibs_before := t.nodes_in_group("gibs").size()
	imp.take_damage(GunScript.DAMAGE)             # one 5-dmg bolt — not enough vs 6 HP
	t.ok(t.nodes_in_group("imps").has(imp), "6-HP imp survives a single 5-dmg bolt")
	var expect_hit := int(round(GunScript.DAMAGE * GoreScript.HIT_GIBS_PER_DAMAGE))
	t.ok(t.nodes_in_group("gibs").size() - gibs_before == expect_hit,
		"a non-lethal hit sprays round(dmg x rate) chunks (%d new)" % (t.nodes_in_group("gibs").size() - gibs_before))
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


func _test_knockback_falloff(t: TestContext) -> void:
	t.suite = "Enemy.knockback"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var imp: Node3D = ImpScript.new()
	imp.max_hp = 100.0
	imp.hp = 100.0                                   # survives many non-lethal hits
	holder.add_child(imp)
	await t.frame()
	var dir := Vector3(1.0, 0.0, 0.0)

	# Three knockbacks with no _process between them -> the window stays open and the
	# falloff escalates: full, -50%, -100%.
	imp.take_damage(2.0, dir)
	var k1: float = imp._knock.length()
	imp.take_damage(2.0, dir)
	var k2: float = imp._knock.length()
	imp.take_damage(2.0, dir)
	var k3: float = imp._knock.length()
	t.ok(k1 > 0.1, "1st knockback in the window is full (%.2f)" % k1)
	t.ok(is_equal_approx(k2, k1 * 0.5), "2nd knockback is halved (%.2f vs %.2f)" % [k2, k1])
	t.ok(k3 < 0.001, "3rd+ knockback is fully suppressed (%.2f)" % k3)

	# A lull longer than KB_WINDOW resets the falloff to full. player == null so _process
	# just decays the window and returns (no movement).
	imp.player = null
	imp._process(ImpScript.KB_WINDOW + 0.1)
	imp.take_damage(2.0, dir)
	t.ok(is_equal_approx(imp._knock.length(), k1),
		"knockback resets to full after a >5s lull (%.2f)" % imp._knock.length())
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

	imp.take_damage(2.0, Vector3(1.0, 0.0, 0.0))   # non-lethal, bolt travelling +X
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

	_drain(sp)                                # spawn all of wave 1 (points, not headcount — revenants cost 3)
	t.ok(_live_points(t) == 32, "wave 1 spends its 32-point budget (got %d)" % _live_points(t))
	var w1_interval: float = sp._spawn_interval

	for imp in t.nodes_in_group("imps"):
		imp.die()                             # clear the field; die() leaves the group at once
	sp._process(0.1)                          # notices the clear -> emits wave_cleared, then idles
	t.ok(sp._awaiting_next, "a cleared wave idles for the menu flow (no free-running timer)")
	sp.resume_after_menu()                    # Main calls this when the wave menu closes
	sp._process(WaveSpawnerScript.WAVE_DELAY + 0.1) # breather elapses -> next wave begins
	var budget: int = sp._to_spawn            # wave 2 = 38 points
	t.ok(budget == 38, "wave 2 budget climbs by +6 to 38 (got %d)" % budget)
	_drain(sp)
	t.ok(_live_points(t) == budget, "wave 2 spends exactly its budget in points (%d == %d)" % [_live_points(t), budget])
	t.ok(sp._spawn_interval < w1_interval,
		"wave 2 drips faster than wave 1 (%.2f < %.2f s)" % [sp._spawn_interval, w1_interval])

	await t.frame()
	holder.free()


func _test_zombie_budget(t: TestContext) -> void:
	t.suite = "WaveSpawner.budget"
	# Share is a pure, gated, capped function of the wave.
	var sp0: Node3D = WaveSpawnerScript.new()
	t.ok(is_equal_approx(sp0._zombie_share(1), 0.0), "wave 1 has zero zombie share")
	t.ok(sp0._zombie_share(2) > 0.0, "zombies are enabled from wave 2")
	t.ok(is_equal_approx(sp0._zombie_share(99), WaveSpawnerScript.ZOMBIE_SHARE_CAP),
		"the zombie share is capped (%.2f)" % sp0._zombie_share(99))
	sp0.free()

	# Wave 1 spawns no zombies; a deep wave mixes them and the points equal the budget.
	var holder := Node3D.new()
	t.root().add_child(holder)
	var sp: Node3D = WaveSpawnerScript.new()
	sp.player = Node3D.new()
	holder.add_child(sp.player)
	holder.add_child(sp)                          # _ready -> wave 1
	_drain(sp)                                    # spawn all of wave 1
	var w1_zombies := 0
	for e in t.nodes_in_group("imps"):
		if e.enemy_type() == "Zombie":
			w1_zombies += 1
	t.ok(w1_zombies == 0, "no zombies spawn in wave 1 (got %d)" % w1_zombies)
	for e in t.nodes_in_group("imps"):
		e.die()
	sp._process(0.1)                              # notices the clear
	sp.resume_after_menu()
	# Advance to a deep wave (7) where the share is high, then drain its budget.
	for _i in 6:
		sp._start_wave()                          # _ready already started wave 1, so these bump _wave 2..7
	var budget: int = sp._to_spawn
	_drain(sp)
	t.ok(sp._to_spawn <= 0, "the wave drains its point budget")
	var zoms := 0
	for e in t.nodes_in_group("imps"):
		if e.enemy_type() == "Zombie":
			zoms += 1
	t.ok(zoms > 0, "a deep wave mixes in zombies (got %d)" % zoms)
	t.ok(_live_points(t) == budget,
		"imp(1) + zombie(2) + revenant(3) points equal the budget (%d, want %d)" % [_live_points(t), budget])
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
	var first_enemy: Array[Node] = [null]
	sp.wave_started.connect(func(w: int) -> void: started[0] = w)
	sp.imp_spawned.connect(func(imp: Node) -> void:
		spawned[0] += 1
		if first_enemy[0] == null:
			first_enemy[0] = imp)
	sp.wave_cleared.connect(func() -> void: cleared[0] += 1)

	holder.add_child(sp)                              # _ready -> _start_wave() -> wave_started(1)
	t.ok(started[0] == 1, "wave_started fires with wave 1 on ready (got %d)" % started[0])

	_drain(sp)                                        # spawn all of wave 1
	t.ok(spawned[0] == t.nodes_in_group("imps").size(),
		"imp_spawned fires once per spawned enemy (%d signals, %d live)" % [spawned[0], t.nodes_in_group("imps").size()])
	var fe: Node = first_enemy[0]
	var base_xp := ImpScript.BASE_XP
	if fe != null and fe.enemy_type() == "Zombie": base_xp = ZombieScript.BASE_XP
	elif fe != null and fe.enemy_type() == "Revenant": base_xp = RevenantScript.BASE_XP
	t.ok(fe != null and is_equal_approx(fe.xp_value, base_xp),
		"a wave-1 enemy carries its un-scaled BASE_XP (%.1f, want %.1f)" % [fe.xp_value if fe != null else -1.0, base_xp])

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


func _test_zombie(t: TestContext) -> void:
	t.suite = "Zombie"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var z: Node3D = ZombieScript.new()
	holder.add_child(z)
	await t.frame()                                  # _ready -> _configure + model
	t.ok(t.nodes_in_group("imps").has(z), "zombie joins the 'imps' target group")
	t.ok(z.enemy_type() == "Zombie", "zombie reports its type for the recap")
	t.ok(is_equal_approx(ZombieScript.BASE_HP, 30.0), "zombie BASE_HP is 30 (~6 pistol bolts)")

	# Tuned slower + bulkier than the imp.
	var i: Node3D = ImpScript.new()
	holder.add_child(i)
	await t.frame()
	t.ok(z.speed < i.speed, "zombie shambles slower than the imp (%.2f < %.2f)" % [z.speed, i.speed])
	t.ok(z.model_height > i.model_height, "zombie is taller than the imp (%.1f > %.1f)" % [z.model_height, i.model_height])

	# Death contract: emits died once and leaves the group.
	var z2: Node3D = ZombieScript.new()
	z2.max_hp = 30.0
	z2.hp = 30.0
	z2.xp_value = 7.0
	z2.soul_value = 4
	holder.add_child(z2)
	await t.frame()
	var got := [false, -1.0, -1]
	z2.died.connect(func(_p: Vector3, xp: float, souls: int) -> void: got[0] = true; got[1] = xp; got[2] = souls)
	t.ok(z2.take_damage(5.0) == false, "5 dmg doesn't kill a 30-HP zombie")
	t.ok(z2.take_damage(99.0) == true, "the lethal hit returns true")
	t.ok(got[0] and is_equal_approx(got[1], 7.0) and got[2] == 4, "zombie die() emits died(pos, xp, souls)")
	t.ok(not t.nodes_in_group("imps").has(z2), "die() removes the zombie from the group")
	await t.frame()
	holder.free()


## A minimal stand-in enemy for the coordinator: lives in group "imps", reports leap state,
## and records that begin_leap() was called — no model/AI, so the gate logic tests fast.
class StubImp extends Node3D:
	var leaping := false
	var began := false
	var can_special_leap := true
	func can_leap() -> bool: return not leaping
	func is_leaping() -> bool: return leaping
	func begin_leap(_target: Vector3) -> void:
		began = true
		leaping = true


## The global leap gate: one at a time, on cooldown, nearest in-band enemy chosen. Drives
## the coordinator's _process directly with a fixed delta — deterministic, no real frames.
func _test_leap_coordinator(t: TestContext) -> void:
	t.suite = "LeapCoordinator"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var player := Node3D.new()
	holder.add_child(player)                    # at the origin

	var close := StubImp.new(); close.position = Vector3(2.0, 0.0, 0.0)    # inside melee range -> skip
	var zomb := StubImp.new(); zomb.position = Vector3(5.0, 0.0, 0.0); zomb.can_special_leap = false   # non-leaper, nearest -> skip
	var near := StubImp.new(); near.position = Vector3(6.0, 0.0, 0.0)      # in band, nearest imp
	var far := StubImp.new(); far.position = Vector3(9.0, 0.0, 0.0)        # in band, farther
	for s in [close, zomb, near, far]:
		s.add_to_group(ImpScript.GROUP)
		holder.add_child(s)

	var coord := LeapCoordinatorScript.new()
	coord.player = player
	holder.add_child(coord)
	coord._cooldown = 0.0                       # skip the start grace

	coord._process(0.016)
	t.ok(near.began and not close.began and not far.began, "nearest in-band imp leaps (not the melee-range one)")
	t.ok(not zomb.began, "a non-leaping enemy (can_special_leap=false) is skipped even when nearest")
	t.ok(coord._active == near, "the coordinator holds it as the single active leaper")

	coord._process(0.016)
	t.ok(not far.began, "no second leap starts while one is in flight")

	near.leaping = false                        # simulate the leap landing
	coord._process(0.016)
	t.ok(coord._active == null and coord._cooldown > 0.0, "a finished leap releases the token and re-arms the cooldown")
	t.ok(not far.began, "the next leap waits out the cooldown")

	holder.free()


## A minimal stand-in zombie for the buff coordinator: lives in group "imps", reports channel
## state, and records begin_channel() — no model/AI, so the gate logic tests fast.
class StubZombie extends Node3D:
	var channeling := false
	var began := false
	var can_special_buff := true
	func can_channel() -> bool: return not channeling
	func is_channeling() -> bool: return channeling
	func begin_channel() -> void:
		began = true
		channeling = true


## The global buff gate: one at a time, on cooldown, the zombie with the most in-range
## neighbours chosen, non-buffers skipped. Drives _process directly — deterministic.
func _test_buff_coordinator(t: TestContext) -> void:
	t.suite = "BuffCoordinator"
	var holder := Node3D.new()
	t.root().add_child(holder)

	# caster (origin) sees a + b (each 5 away, within BUFF_RANGE 6) plus the co-located
	# nonbuffer -> 3 neighbours; a and b see only caster+nonbuffer (a<->b is 10 apart) -> 2;
	# lone sees none. So the caster is the unambiguous max among eligible zombies.
	var lone := StubZombie.new(); lone.position = Vector3(30, 0, 0)
	var caster := StubZombie.new(); caster.position = Vector3(0, 0, 0)
	var a := StubZombie.new(); a.position = Vector3(5, 0, 0)
	var b := StubZombie.new(); b.position = Vector3(-5, 0, 0)
	var nonbuffer := StubZombie.new(); nonbuffer.position = Vector3(0, 0, 0.5); nonbuffer.can_special_buff = false
	for s in [lone, caster, a, b, nonbuffer]:
		s.add_to_group("imps")
		holder.add_child(s)

	var coord := BuffCoordinatorScript.new()
	holder.add_child(coord)
	coord._cooldown = 0.0                       # skip the start grace

	coord._process(0.016)
	t.ok(caster.began and not lone.began, "the zombie with the most in-range neighbours channels; the lone one doesn't")
	t.ok(not nonbuffer.began, "a non-buffer (can_special_buff=false) never channels, even when clustered")
	t.ok(coord._active == caster, "the coordinator holds the caster as the single active channeller")

	coord._process(0.016)
	t.ok(not a.began, "no second channel starts while one is active")

	caster.channeling = false                   # simulate the channel finishing
	coord._process(0.016)
	t.ok(coord._active == null and coord._cooldown > 0.0, "a finished channel releases the token and re-arms the cooldown")
	holder.free()                               # clear the group before the solo case

	# A zombie with NOBODY in range never channels — the buff is never wasted on empty air.
	var solo_holder := Node3D.new()
	t.root().add_child(solo_holder)
	var solo := StubZombie.new()
	solo.add_to_group("imps")
	solo_holder.add_child(solo)
	var coord2 := BuffCoordinatorScript.new()
	solo_holder.add_child(coord2)
	coord2._cooldown = 0.0
	coord2._process(0.016)
	t.ok(not solo.began and coord2._active == null, "a lone zombie (no one in range) never channels")
	solo_holder.free()


## A hasted enemy actually travels faster: buff one of two identical imps, step both, compare
## distance covered toward the player. Guards the "buff does nothing" bug the player reported.
func _test_speed_buff(t: TestContext) -> void:
	t.suite = "Enemy.buff"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var target := Node3D.new()
	holder.add_child(target)                    # player at the origin

	var plain: Node3D = ImpScript.new()
	plain.max_hp = 999.0; plain.hp = 999.0; plain.player = target
	plain.position = Vector3(10.0, 0.0, 0.0)
	var hasted: Node3D = ImpScript.new()
	hasted.max_hp = 999.0; hasted.hp = 999.0; hasted.player = target
	hasted.position = Vector3(10.0, 0.0, 20.0)  # far from `plain` so separation doesn't skew it
	holder.add_child(plain)
	holder.add_child(hasted)
	await t.frame()                             # _ready builds the model (emerge = 0 -> moves at once)

	hasted.apply_speed_buff(ImpScript.BUFF_MULT, ImpScript.BUFF_DURATION)
	var p0: Vector3 = plain.global_position
	var h0: Vector3 = hasted.global_position
	for _i in 10:
		plain._process(0.1)
		hasted._process(0.1)                    # 1.0s of stepping
	var d_plain := p0.distance_to(plain.global_position)
	var d_hasted := h0.distance_to(hasted.global_position)
	t.ok(d_plain > 0.5, "the plain imp moved (%.2f)" % d_plain)
	t.ok(d_hasted > d_plain * 1.4, "the hasted imp covered >1.4x the plain imp's distance (+60%% buff: %.2f vs %.2f)" % [d_hasted, d_plain])
	holder.free()


## Count EnemyBolt children under a holder (bolts add themselves to the firer's parent).
func _count_bolts(holder: Node) -> int:
	var n := 0
	for c in holder.get_children():
		if c.get_script() == EnemyBoltScript:
			n += 1
	return n


## A minimal stand-in player: records the damage it takes (the bolt/melee victim).
class StubPlayer extends Node3D:
	var hits := 0
	var total := 0.0
	func take_damage(amount: float) -> void:
		hits += 1
		total += amount


## The ranged elite: joins the group, reports its type, and is tuned to fight at range
## (fires from beyond where it stops) with only the barrage special.
func _test_revenant(t: TestContext) -> void:
	t.suite = "Revenant"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var r: Node3D = RevenantScript.new()
	holder.add_child(r)
	await t.frame()                                  # _ready -> _configure + model
	t.ok(t.nodes_in_group("imps").has(r), "revenant joins the 'imps' target group")
	t.ok(r.enemy_type() == "Revenant", "revenant reports its type for the recap")
	t.ok(r.can_special_barrage and not r.can_special_leap and not r.can_special_buff,
		"revenant has only the barrage special (no leap, no buff)")
	t.ok(r.attack_range > r.stop_dist, "revenant fires from beyond where it stops (ranged, not melee)")

	var i: Node3D = ImpScript.new()
	holder.add_child(i)
	await t.frame()
	t.ok(r.attack_range > i.attack_range, "revenant attacks from much farther than an imp (%.1f > %.1f)" % [r.attack_range, i.attack_range])
	holder.free()


## Revenant share: nonzero from wave 1 (present immediately), climbs, capped. Pure function.
func _test_revenant_share(t: TestContext) -> void:
	t.suite = "WaveSpawner.revenant"
	var sp0: Node3D = WaveSpawnerScript.new()
	t.ok(sp0._revenant_share(1) > 0.0, "revenants appear from wave 1 (share %.2f)" % sp0._revenant_share(1))
	t.ok(sp0._revenant_share(5) > sp0._revenant_share(1), "the revenant share climbs with the wave")
	t.ok(is_equal_approx(sp0._revenant_share(99), WaveSpawnerScript.REVENANT_SHARE_CAP),
		"the revenant share is capped (%.2f)" % sp0._revenant_share(99))
	sp0.free()


## The enemy bolt damages the PLAYER and passes through other enemies unharmed — the core
## "revenant bullets only hurt the player" contract.
func _test_enemy_bolt_only_hits_player(t: TestContext) -> void:
	t.suite = "EnemyBolt"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var player := StubPlayer.new()
	holder.add_child(player)                         # at the origin — the bolt's target

	var bystander: Node3D = ImpScript.new()
	bystander.max_hp = 100.0
	bystander.hp = 100.0
	holder.add_child(bystander)
	await t.frame()
	bystander.global_position = Vector3(0.0, 0.0, -1.5)   # sits directly on the bolt's path

	var bolt: Node3D = EnemyBoltScript.new()
	bolt.player = player
	bolt.damage = 5.0
	holder.add_child(bolt)
	bolt.global_position = Vector3(0.0, 0.0, -3.0)   # flies +Z toward the player, crossing the imp

	for _i in 60:
		if not is_instance_valid(bolt):
			break
		bolt._process(0.05)
	t.ok(player.hits >= 1 and is_equal_approx(player.total, 5.0), "the enemy bolt damages the player (%.1f)" % player.total)
	t.ok(is_instance_valid(bystander) and is_equal_approx(bystander.hp, 100.0),
		"the enemy bolt passes through enemies unharmed (imp HP %.0f, untouched)" % bystander.hp)
	holder.free()


## A revenant in firing range looses bolts at the player on its cooldown (the ranged attack).
func _test_revenant_fires(t: TestContext) -> void:
	t.suite = "Revenant.fire"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var player := StubPlayer.new()
	holder.add_child(player)                         # at the origin
	var r: Node3D = RevenantScript.new()
	r.player = player
	r.max_hp = 100.0
	r.hp = 100.0
	holder.add_child(r)
	await t.frame()
	r.global_position = Vector3(0.0, 0.0, 10.0)      # within attack_range (13), beyond stop_dist (9)

	var before := _count_bolts(holder)
	for _i in 40:
		r._process(0.1)                              # 4s > attack_cooldown 2.5 -> at least one shot
	t.ok(_count_bolts(holder) - before >= 1, "a revenant in range fires bolts at the player (%d)" % (_count_bolts(holder) - before))
	holder.free()


## After its shot quota the revenant strafes to a new spot (a moving target, not a turret).
func _test_revenant_repositions(t: TestContext) -> void:
	t.suite = "Revenant.reposition"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var player := StubPlayer.new()
	holder.add_child(player)
	var r: Node3D = RevenantScript.new()
	r.player = player
	r.max_hp = 100.0
	r.hp = 100.0
	holder.add_child(r)
	await t.frame()
	r.global_position = Vector3(0.0, 0.0, 10.0)

	r._shots_before_move = 2
	r._shots_since_move = 0
	r._attack_player()
	r._attack_player()                               # hit the quota -> trigger a reposition
	t.ok(r._reposition_t > 0.0, "after its shot quota the revenant kicks off a reposition")
	var p0: Vector3 = r.global_position
	for _i in 6:
		r._process(0.1)
	t.ok(r.global_position.distance_to(p0) > 0.2, "the reposition actually moves it (%.2f)" % r.global_position.distance_to(p0))
	holder.free()


## The barrage special looses a fan of exactly BARRAGE_COUNT bolts, then ends.
func _test_revenant_barrage_fan(t: TestContext) -> void:
	t.suite = "Revenant.barrage"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var player := StubPlayer.new()
	holder.add_child(player)
	var r: Node3D = RevenantScript.new()
	r.player = player
	holder.add_child(r)
	await t.frame()
	r.global_position = Vector3(0.0, 0.0, 10.0)

	t.ok(r.can_barrage(), "an idle revenant can be told to barrage")
	r.begin_barrage()
	t.ok(r.is_barraging(), "begin_barrage puts it into the rooted barrage state")
	var before := _count_bolts(holder)
	for _i in 20:
		r._process(0.1)                              # 2s: wind-up (0.6) + fire + recovery (0.4)
	t.ok(_count_bolts(holder) - before == RevenantScript.BARRAGE_COUNT,
		"the barrage looses a fan of BARRAGE_COUNT bolts (%d)" % (_count_bolts(holder) - before))
	t.ok(not r.is_barraging(), "the barrage ends after firing + recovery")
	holder.free()


## A minimal stand-in revenant for the coordinator: lives in group "imps", reports barrage
## state, and records begin_barrage() — no model/AI, so the gate logic tests fast.
class StubRevenant extends Node3D:
	var barraging := false
	var began := false
	var can_special_barrage := true
	func can_barrage() -> bool: return not barraging
	func is_barraging() -> bool: return barraging
	func begin_barrage() -> void:
		began = true
		barraging = true


## The global barrage gate: one at a time, on cooldown, the nearest eligible revenant chosen,
## non-barragers skipped. Drives _process directly — deterministic, no real frames.
func _test_revenant_coordinator(t: TestContext) -> void:
	t.suite = "RevenantCoordinator"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var player := Node3D.new()
	holder.add_child(player)                         # at the origin

	var far := StubRevenant.new(); far.position = Vector3(20, 0, 0)
	var near := StubRevenant.new(); near.position = Vector3(5, 0, 0)
	var nonbarr := StubRevenant.new(); nonbarr.position = Vector3(2, 0, 0); nonbarr.can_special_barrage = false  # nearest, but opts out
	for s in [far, near, nonbarr]:
		s.add_to_group("imps")
		holder.add_child(s)

	var coord := RevenantCoordinatorScript.new()
	coord.player = player
	holder.add_child(coord)
	coord._cooldown = 0.0                            # skip the start grace

	coord._process(0.016)
	t.ok(near.began and not far.began, "the nearest eligible revenant barrages")
	t.ok(not nonbarr.began, "a non-barrager (can_special_barrage=false) is skipped even when nearest")
	t.ok(coord._active == near, "the coordinator holds it as the single active barrager")

	coord._process(0.016)
	t.ok(not far.began, "no second barrage starts while one is active")

	near.barraging = false                           # simulate the barrage finishing
	coord._process(0.016)
	t.ok(coord._active == null and coord._cooldown > 0.0, "a finished barrage releases the token and re-arms the cooldown")
	holder.free()
