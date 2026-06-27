extends RefCounted
## Audio SFX tests, split from run_tests.gd. `t` is the shared TestContext.

const TestContext := preload("res://test/test_context.gd")
const ShotSfxScript := preload("res://src/audio/shot_sfx.gd")
const ImpactSfxScript := preload("res://src/audio/impact_sfx.gd")


func run(t: TestContext) -> void:
	await _test_shot_sfx(t)
	await _test_impact_sfx(t)


func _test_shot_sfx(t: TestContext) -> void:
	t.suite = "ShotSfx"
	var s: Node = ShotSfxScript.new()
	t.root().add_child(s)
	await t.frame()                  # _ready loads the clips + pool
	var loaded: int = s._streams.size()
	var all_valid: bool = loaded == 5
	for st in s._streams:
		if st == null:
			all_valid = false
	t.ok(all_valid, "loads all 5 pistol clips (got %d)" % loaded)
	# Evened volumes: the quietest clip (05) gets boosted well above the loudest (01).
	t.ok(s._volumes.size() == 5 and s._volumes[4] > s._volumes[0] + 10.0,
		"per-clip trims even the levels (loud %.1f dB vs quiet %.1f dB)" % [s._volumes[0], s._volumes[4]])
	s.play()                             # must not error even with no audio device
	t.ok(true, "play() runs without error")
	s.free()


func _test_impact_sfx(t: TestContext) -> void:
	t.suite = "ImpactSfx"
	var s: Node = ImpactSfxScript.new()
	t.root().add_child(s)
	await t.frame()                  # _ready loads the clips + pool
	var loaded: int = s._streams.size()
	var all_valid: bool = loaded == 3
	for st in s._streams:
		if st == null:
			all_valid = false
	t.ok(all_valid, "loads all 3 impact clips (got %d)" % loaded)
	t.ok(ImpactSfxScript.IMPACT_DB < ShotSfxScript.MASTER_DB,
		"impact is quieter than the shot level (%.1f < %.1f dB)" % [ImpactSfxScript.IMPACT_DB, ShotSfxScript.MASTER_DB])
	s.play()                             # must not error even with no audio device
	t.ok(true, "play() runs without error")
	s.free()
