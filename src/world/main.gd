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

const CAM_OFFSET := Vector3(0.0, 13.0, 7.0)
const CAM_SIZE := 18.0             # orthographic vertical extent (smaller = closer)

var marine: Node3D
var camera: Camera3D


func _ready() -> void:
	_build_environment()
	_build_key_light()
	add_child(HellIsland.build())

	# preload by path (not bare class_name) so loading doesn't depend on the
	# editor having built the global class cache — works on a cold clone / CI.
	marine = MarineScript.new()
	add_child(marine)

	# Wave 1 of imps scattered across the island.
	var spawner := WaveSpawnerScript.new()
	spawner.player = marine
	add_child(spawner)

	# Guns floating around the marine, auto-aiming at the closest imps.
	var weapons := WeaponRingScript.new()
	weapons.player = marine
	add_child(weapons)

	# Battle music — random track, quiet, fades out when no imps are alive.
	add_child(BattleMusicScript.new())

	# Screen-border markers for off-screen imps.
	var ui := CanvasLayer.new()
	ui.add_child(IndicatorsScript.new())
	add_child(ui)

	# ESC pause menu (Resume / Exit).
	add_child(PauseMenuScript.new())

	_build_camera()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.01, 0.015)        # near-black void, faint red
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.22, 0.12)      # ember fill
	env.ambient_light_energy = 1.15

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
	env.glow_hdr_threshold = 0.9
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
	key.light_energy = 1.8
	key.rotation = Vector3(deg_to_rad(-22.0), deg_to_rad(35.0), 0.0)
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
