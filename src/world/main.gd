class_name Main
extends Node3D
## Composition root for the hell-marine prototype (iteration 1).
##
## Builds the hellish environment + a low warm key light, the procedural hell
## island, the marine, and a top-down orthographic follow camera. Stateless
## geometry/colour helpers live in src/lib/*; the island mesh in
## src/world/hell_island.gd; the marine in src/marine/. This script only composes.

const HellIsland := preload("res://src/world/hell_island.gd")
const MarineScript := preload("res://src/marine/marine.gd")
const WaveSpawnerScript := preload("res://src/enemies/wave_spawner.gd")
const WeaponRingScript := preload("res://src/weapons/weapon_ring.gd")
const IndicatorsScript := preload("res://src/ui/offscreen_indicators.gd")
const BattleMusicScript := preload("res://src/audio/battle_music.gd")
const PauseMenuScript := preload("res://src/ui/pause_menu.gd")
const PlayerStatsScript := preload("res://src/marine/player_stats.gd")
const HudScript := preload("res://src/ui/hud.gd")
const GameOverMenuScript := preload("res://src/ui/game_over_menu.gd")
const XpOrbFieldScript := preload("res://src/loot/xp_orb_field.gd")
const ScreenGradeScript := preload("res://src/fx/screen_grade.gd")
const InventoryScript := preload("res://src/inventory/inventory.gd")
const LevelUpMenuScript := preload("res://src/ui/level_up_menu.gd")

const CAM_OFFSET := Vector3(0.0, 13.0, 7.0)
const CAM_SIZE := 18.0             # orthographic vertical extent (smaller = closer)
const DEATH_MENU_DELAY := 0.9      # let the death topple play before the menu pops

var marine: Node3D
var camera: Camera3D
var game_over: CanvasLayer


func _ready() -> void:
	_build_environment()
	_build_key_light()
	add_child(HellIsland.build())

	# preload by path (not bare class_name) so loading doesn't depend on the editor
	# having built the global class cache — works on a cold clone / CI.
	marine = MarineScript.new()
	add_child(marine)

	# Player stats the HUD binds to; the marine drains health and gains XP through it.
	var stats := PlayerStatsScript.new()
	marine.add_child(stats)
	marine.stats = stats

	# Grid inventory: the backpack's equipped pistols drive the marine's held guns.
	var inventory := InventoryScript.build()
	marine.add_child(inventory)
	marine.inventory = inventory

	# XP orbs dropped by dead imps, magnetised to the marine.
	var loot := XpOrbFieldScript.new()
	loot.player = marine
	add_child(loot)

	# Gameplay HUD: animated portrait + HP, full-width XP strip, level medallion.
	# Built before the spawner so its wave-started handler is connected in time.
	var hud := HudScript.new()
	hud.stats = stats
	add_child(hud)

	# Level-up menu — pauses on level-up; lets the player manage the inventory.
	var levelup := LevelUpMenuScript.new()
	levelup.inventory = inventory
	levelup.hud = hud
	levelup.stats = stats
	add_child(levelup)
	hud.level_reached.connect(levelup.open)   # open on a FULL bar, not the instant XP crosses the threshold

	# Wave spawner — announces imp spawns + wave boundaries; we wire them to loot + HUD here.
	var spawner := WaveSpawnerScript.new()
	spawner.player = marine
	spawner.inventory = inventory   # read equipped loadout power to scale each wave
	spawner.imp_spawned.connect(loot.on_imp_spawned)
	spawner.wave_cleared.connect(loot.vacuum_all)
	spawner.wave_started.connect(hud.on_wave_started)
	add_child(spawner)

	# Guns floating around the marine, auto-aiming at the closest imps.
	var weapons := WeaponRingScript.new()
	weapons.player = marine
	add_child(weapons)

	# Battle music — random track, quiet, fades out when no imps are alive.
	add_child(BattleMusicScript.new())

	# Screen-space "video filter" grade, on layer 0 so it grades the 3D scene only.
	add_child(ScreenGradeScript.new())

	# Screen-border markers for off-screen imps.
	var ui := CanvasLayer.new()
	ui.add_child(IndicatorsScript.new())
	add_child(ui)

	# ESC pause menu (Resume / Exit).
	add_child(PauseMenuScript.new())

	# Game-over menu — raised after the marine dies (New Game / Exit).
	game_over = GameOverMenuScript.new()
	add_child(game_over)
	marine.died.connect(_on_player_died)

	_build_camera()


## The marine died — let its death topple play, then raise the game-over menu.
func _on_player_died() -> void:
	await get_tree().create_timer(DEATH_MENU_DELAY).timeout
	if is_instance_valid(game_over):
		game_over.show_menu()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.01, 0.015)        # near-black void, faint red
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.50, 0.27, 0.20)      # ember fill — less pure-red so it doesn't wash everything red
	env.ambient_light_energy = 0.85                        # was 0.85; cut so the key light's cast shadows actually read (was washing the marine's shadow out flat)

	# Tone mapping + exposure — the biggest "feel" lever.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.45

	# Red-black haze swallows the void at the island's edge.
	env.fog_enabled = true
	env.fog_light_color = Color(0.30, 0.05, 0.03)
	env.fog_density = 0.012

	# Glow so emissive ember rocks bloom like coals.
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.05
	env.glow_bloom = 0.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.15   # was 0.9; only the emissive ember rocks bloom now, not the lit ground
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 1.0)
	env.set_glow_level(5, 1.0)

	# SSAO grounds the marine + rocks onto the surface.
	env.ssao_enabled = true
	env.ssao_radius = 0.7
	env.ssao_intensity = 1.2

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_key_light() -> void:
	# Low, warm key raking across the island like firelight out of the void.
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.5, 0.25)
	key.light_energy = 2.8   # was 2.2; bumped to keep lit ground bright after the ambient cut
	key.rotation = Vector3(deg_to_rad(-42.0), deg_to_rad(35.0), 0.0)   # steeper than -22 so the marine's shadow sits under/behind it (grounds it) instead of raking far off-frame
	key.shadow_enabled = true
	add_child(key)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL   # clean diorama look
	camera.size = CAM_SIZE
	camera.position = marine.global_position + CAM_OFFSET
	camera.rotation = Vector3(-atan2(CAM_OFFSET.y, CAM_OFFSET.z), 0.0, 0.0)
	camera.current = true
	add_child(camera)


func _process(_delta: float) -> void:
	if marine == null or camera == null:
		return
	camera.global_position = marine.global_position + CAM_OFFSET
