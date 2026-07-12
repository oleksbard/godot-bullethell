class_name Revenant
extends "res://src/enemies/enemy.gd"
## A skeletal rocketeer: the game's first RANGED demon. Reuses the Enemy base AI +
## imp_anim.gdshader, but instead of running into melee it holds at firing range and lobs
## slow, dodgeable EnemyBolts at the marine (see _attack_player). It occasionally darts back
## when the player crowds it (_steer_intent) rather than kiting, and its special — granted by
## the RevenantCoordinator — is a rooted missile barrage: a fan of bolts (_release_barrage).
## Costs 3 of a wave's spawn budget (imp = 1, zombie = 2); appears from wave 1. See WaveSpawner.

const EnemyBoltScript := preload("res://src/fx/enemy_bolt.gd")

const MODEL: PackedScene = preload("res://models/revenant_opt.glb")
const ENEMY_NAME := "Revenant"    # recap kills-by-type label
const BASE_HP := 8.0              # ~2 pistol bolts (dmg 5) at wave 1; spawner scales per wave
const BASE_ATTACK_DAMAGE := 2.5   # damage PER BOLT (not melee); spawner scales per wave
const BASE_XP := 3.0              # elite — worth ~3x an imp; spawner scales per wave

# Backpedal: not a kite. It holds its ground and shoots; only when the player gets close does
# it SOMETIMES scuttle back a little, then resume. So you rarely see it retreat, and it never
# feels like it's keeping its distance.
const BACKPEDAL_NEAR := 6.0       # only consider retreating when the player is closer than this
const BACKPEDAL_TIME := 0.7       # seconds of a retreat burst once triggered
const BACKPEDAL_CHANCE := 0.5     # chance a retreat opportunity actually triggers
const BACKPEDAL_COOLDOWN := 3.0   # min seconds between retreats -> occasional, not constant
const BACKPEDAL_ROLL_EVERY := 0.5 # roll the chance at most this often (not every frame)

# Reposition: every few shots it strafes sideways to a fresh spot so it's a moving target,
# not a turret. Lateral (orbits the player) -> stays in the firing band.
const SHOTS_PER_MOVE_MIN := 2
const SHOTS_PER_MOVE_MAX := 3
const REPOSITION_TIME := 0.8      # seconds of strafing per reposition

# Barrage volley: a wide fan of bolts the player dodges by strafing perpendicular.
const BARRAGE_COUNT := 5
const BARRAGE_SPREAD := 0.87      # total fan width in radians (~50 degrees)

# Muzzle: fire from chest height, nudged forward along facing.
const MUZZLE_HEIGHT_FRAC := 0.62
const MUZZLE_FORWARD := 0.35

# Death gore palette: shattered bone + crimson.
const GORE_VOLUME_MULT := 2
const GIB_BONE := Color(0.86, 0.82, 0.70)
const GIB_BLOOD := Color(0.45, 0.07, 0.07)

var _backpedal_t := 0.0
var _backpedal_cd := 0.0
var _roll_t := 0.0
var _shots_since_move := 0
var _shots_before_move := 2
var _reposition_t := 0.0
var _reposition_side := 1.0


func _configure() -> void:
	# Ranged holder: slower, stops well short of the player, "attacks" (fires) from far.
	# NEVER touch the spawner-set combat numbers (max_hp/hp/attack_damage/xp_value) here.
	speed = 1.8
	body_radius = 0.5
	stop_dist = 9.0               # holds ~9u out; _steer_intent keeps it in the firing band
	attack_range = 13.0           # fires when the player is within this (base "in range")
	attack_cooldown = 2.5         # one bolt every 2.5s — deliberately not fast
	model_height = 1.95           # tall skeletal frame
	model_yaw = PI                # revenant.glb facing — VERIFY by motion in-game (Godot forward = -Z)
	body_color = Color(0.5, 0.1, 0.1)     # bloody tint for non-lethal hit gibs + albedo fallback
	# Cold bone read: the imps are the warm/red ones, so the skeletal revenant goes the opposite way —
	# a pale bone albedo + cold-cyan sockets/self-light. Separates it from the imp at a glance and keeps
	# the atmosphere cold rather than adding another warm glow to the orange-washed scene.
	body_tint = Color(0.62, 0.70, 0.82)   # pale desaturated bone-blue
	tint_mix = 0.3                         # lerp the dark texture toward bone so it doesn't wash to yellow
	body_emission = Color(0.06, 0.22, 0.40)  # dim cold-cyan self-light (wash-proof signature)
	body_glow = 0.28
	dmg_number_color = Color(0.7, 0.85, 1.0)
	eye_color = Color(0.45, 0.85, 1.0)    # cold cyan sockets — undeath, not the imp's ember
	eye_energy = 3.5
	# Gait: a heavy, lumbering undead sway. High twist swings the whole upper body (incl. the
	# model's outstretched arms) fore/aft as the shoulders counter-rotate, so it reads as alive
	# and lurching rather than a rigid T-pose — without faking arm joints (no skeleton). NO melee
	# lunge (lunge_reach 0 — it shoots, not jabs).
	walk_freq = 3.2               # slow, heavy cadence
	stride = 0.16
	twist = 0.26                  # strong shoulder counter-rotation -> the arms swing with the body
	lean_run = 0.18
	bob = 0.15                    # heavy vertical lurch
	squash = 0.08
	lunge_rate = 1.0
	lunge_reach = 0.0
	uses_melee_pose = false       # ranged: never strike the melee jab pose, so the walk gait keeps
	                              # animating instead of freezing in the rest pose (the "T-pose") in range
	can_special_leap = false      # skeletal — no pounce
	can_special_buff = false      # no AoE haste
	can_special_barrage = true    # ...but it looses the rooted missile barrage
	_shots_before_move = randi_range(SHOTS_PER_MOVE_MIN, SHOTS_PER_MOVE_MAX)


func _model_scene() -> PackedScene:
	return MODEL


func enemy_type() -> String:
	return ENEMY_NAME


## Fire ONE bolt at the player (the ranged replacement for melee). Slow + dodgeable. Every
## few shots, kick off a sideways reposition so it doesn't sit still like a turret.
func _attack_player() -> void:
	_fire_bolt(Vector3.ZERO)
	_shots_since_move += 1
	if _shots_since_move >= _shots_before_move:
		_shots_since_move = 0
		_shots_before_move = randi_range(SHOTS_PER_MOVE_MIN, SHOTS_PER_MOVE_MAX)
		_reposition_t = REPOSITION_TIME
		_reposition_side = 1.0 if randf() < 0.5 else -1.0


## Hold at firing range; occasionally dart straight back when the player crowds in. Not a
## kite — most frames it either closes to range or stands still and shoots.
func _steer_intent(to_player: Vector3, delta: float) -> Vector3:
	_backpedal_cd = maxf(_backpedal_cd - delta, 0.0)
	var away := Vector3(-to_player.x, 0.0, -to_player.z)
	if _backpedal_t > 0.0:                                # crowded retreat wins
		_backpedal_t -= delta
		return away.normalized() if away.length() > 0.001 else Vector3.ZERO
	if _reposition_t > 0.0:                               # strafe sideways to a new spot after a few shots
		_reposition_t -= delta
		var perp := Vector3(-to_player.z, 0.0, to_player.x)   # 90° from the player dir -> lateral orbit
		return (perp.normalized() * _reposition_side) if perp.length() > 0.001 else Vector3.ZERO
	var dist := to_player.length()
	if dist < BACKPEDAL_NEAR and _backpedal_cd <= 0.0:
		_roll_t -= delta
		if _roll_t <= 0.0:
			_roll_t = BACKPEDAL_ROLL_EVERY
			if randf() < BACKPEDAL_CHANCE:
				_backpedal_t = BACKPEDAL_TIME
				_backpedal_cd = BACKPEDAL_COOLDOWN
				return away.normalized() if away.length() > 0.001 else Vector3.ZERO
	if dist > attack_range:           # drifted out of range -> close back in
		return to_player.normalized()
	return Vector3.ZERO               # in the firing band -> stand and shoot


## The barrage volley: a wide fan of bolts centred on the player. Fired by the base at the
## climax of the rooted wind-up (begin_barrage/_process_barrage in enemy.gd).
func _release_barrage() -> void:
	if player == null:
		return
	var to := player.global_position - global_position
	to.y = 0.0
	if to.length() < 0.001:
		return
	var base_dir := to.normalized()
	for i in BARRAGE_COUNT:
		var f := 0.0 if BARRAGE_COUNT <= 1 else (float(i) / float(BARRAGE_COUNT - 1) - 0.5)
		_fire_bolt(base_dir.rotated(Vector3.UP, f * BARRAGE_SPREAD))


## Spawn one EnemyBolt from the chest muzzle. aim_dir == ZERO -> the bolt aims at the player
## itself; otherwise it flies the given heading (barrage fan).
func _fire_bolt(aim_dir: Vector3) -> void:
	var parent := get_parent()
	if parent == null or player == null:
		return
	var bolt := EnemyBoltScript.new()
	bolt.player = player
	bolt.damage = attack_damage
	bolt.aim_dir = aim_dir
	parent.add_child(bolt)
	var fwd := -global_transform.basis.z
	bolt.global_position = global_position + Vector3.UP * (model_height * MUZZLE_HEIGHT_FRAC) + fwd * MUZZLE_FORWARD


## Shattered-skeleton death: bone-white + crimson chunks, a heavier burst than an imp's.
func _spawn_gore(damage: float, hit_dir: Vector3) -> void:
	Gore.spawn_death(get_parent(), global_position, body_color,
		damage, hit_dir, [GIB_BONE, GIB_BLOOD], GORE_VOLUME_MULT)
