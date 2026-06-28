extends RefCounted
## Wave recap: WaveStats math + CombatTracker accumulation + the player damage signal.

const TestContext := preload("res://test/test_context.gd")
const WaveStatsScript := preload("res://src/stats/wave_stats.gd")
const CombatTrackerScript := preload("res://src/stats/combat_tracker.gd")
const InventoryItemScript := preload("res://src/inventory/inventory_item.gd")
const PlayerStatsScript := preload("res://src/marine/player_stats.gd")


func run(t: TestContext) -> void:
	_test_wave_stats(t)
	_test_combat_tracker(t)
	_test_player_stats_damaged(t)


func _test_wave_stats(t: TestContext) -> void:
	t.suite = "WaveStats"
	var ws: Object = WaveStatsScript.new()
	ws.duration = 2.0
	var a := {"name": "A", "damage": 100.0, "shots": 10, "hits": 8, "kills": 5}
	var b := {"name": "B", "damage": 40.0, "shots": 5, "hits": 5, "kills": 2}
	ws.guns = [a, b]
	ws.kills_by_type = {"Imp": 7}
	t.ok(is_equal_approx(ws.dps(a), 50.0), "dps = damage / duration (100/2 = 50, got %.1f)" % ws.dps(a))
	t.ok(is_equal_approx(ws.accuracy(a), 0.8), "accuracy = hits / shots (8/10, got %.2f)" % ws.accuracy(a))
	t.ok(is_same(ws.mvp(), a), "mvp is the highest-damage gun")
	t.ok(ws.total_kills() == 7, "total_kills sums kills_by_type")
	var z: Object = WaveStatsScript.new()
	t.ok(z.dps(a) == 0.0, "dps is 0 when duration is 0")
	t.ok(z.accuracy({"shots": 0, "hits": 0}) == 0.0, "accuracy is 0 when no shots")
	t.ok(z.mvp().is_empty(), "mvp is {} with no guns")


func _test_combat_tracker(t: TestContext) -> void:
	t.suite = "CombatTracker"
	var tr: Object = CombatTrackerScript.new()
	tr.begin_wave(3)
	var gun := RefCounted.new()                      # stand-in gun instance (a dict key)
	var item := InventoryItemScript.pistol()
	tr.record_shot(gun, item)
	tr.record_shot(gun, item)
	tr.record_hit(gun, 5.0, false)
	tr.record_hit(gun, 5.0, true)
	tr.record_kill_by_type("Imp", 2)
	tr.record_kill_by_type("Imp", 1)
	tr.record_damage_taken(7.0)
	tr._process(1.0)                                 # grow the wave timer (no tree needed)
	tr._process(1.0)
	var snap: Object = tr.snapshot()                 # mid-wave snapshot reflects partial state
	t.ok(is_equal_approx(snap.duration, 2.0), "snapshot stamps elapsed duration (got %.1f)" % snap.duration)
	t.ok(is_equal_approx(snap.damage_dealt, 10.0), "snapshot sums damage dealt")
	tr.end_wave()
	var ws: Object = tr.last_wave
	t.ok(ws != null and ws.wave == 3, "end_wave finalises last_wave for the wave number")
	t.ok(is_equal_approx(ws.damage_dealt, 10.0) and is_equal_approx(ws.damage_taken, 7.0),
		"damage dealt + taken tallied")
	t.ok(ws.souls_earned == 3 and ws.total_kills() == 2, "souls + kills tallied from kills-by-type")
	t.ok(ws.guns.size() == 1, "one gun card recorded")
	var c: Dictionary = ws.guns[0]
	t.ok(c["shots"] == 2 and c["hits"] == 2 and c["kills"] == 1, "per-gun shots/hits/kills")
	t.ok(c["name"] == "Pistol" and is_equal_approx(c["damage"], 10.0), "per-gun name + damage")
	t.ok(is_equal_approx(ws.dps(c), 5.0), "per-gun DPS = 10 dmg / 2s")
	tr.free()                                        # tracker is a Node, never parented — free it


func _test_player_stats_damaged(t: TestContext) -> void:
	t.suite = "PlayerStats.damaged"
	var st: Object = PlayerStatsScript.new()
	var got := [0.0]
	st.damaged.connect(func(amount: float) -> void: got[0] += amount)
	st.take_damage(8.0)
	t.ok(is_equal_approx(got[0], 8.0), "take_damage emits damaged(amount)")
	st.heal(5.0)
	t.ok(is_equal_approx(got[0], 8.0), "heal does not emit damaged")
	st.free()                                        # PlayerStats is a Node, never parented — free it
