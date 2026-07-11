class_name Zombie
extends "res://src/enemies/enemy.gd"
## A slow, tanky bullet-sponge. Reuses the Enemy base AI + imp_anim.gdshader; only its
## model, gait, size, toughness, and the heavy red+green death gore differ. Costs 2 of a
## wave's spawn budget (imp = 1) — see WaveSpawner.

const MODEL: PackedScene = preload("res://models/zombie_opt.glb")
const ENEMY_NAME := "Zombie"     # recap kills-by-type label
const BASE_HP := 30.0            # ~6 pistol bolts (dmg 5) at wave 1; spawner scales per wave
const BASE_ATTACK_DAMAGE := 2.0  # hits harder than an imp; spawner scales per wave
const BASE_XP := 2.0             # ~2x an imp; spawner scales per wave

# Death gore palette (mixed red + green chunks; see _spawn_gore).
const GORE_VOLUME_MULT := 3      # throws this many times the projectile's chunk count (a heavier body)
const GIB_RED := Color(0.42, 0.06, 0.06)
const GIB_GREEN := Color(0.20, 0.5, 0.08)


func _configure() -> void:
	# Slow, stiff, hunched shamble + a heavy slow swipe. NEVER touch the spawner-set
	# combat numbers (max_hp/hp/attack_damage/xp_value/soul_value) here.
	speed = 1.4
	body_radius = 0.6
	stop_dist = 1.0
	model_height = 1.8
	model_yaw = PI                # zombie.glb facing — VERIFY by motion in-game (Godot forward = -Z)
	attack_range = 1.7
	attack_cooldown = 1.2
	body_color = Color(0.22, 0.34, 0.12)    # rotten flesh — tints non-lethal hit gibs
	body_tint = Color(0.30, 0.80, 0.18)     # saturated toxic-green — tune hue by eye
	tint_mix = 0.65                          # blend most of the way to flat green so it reads past the dark texture
	dmg_number_color = Color(0.7, 1.0, 0.6)
	eye_color = Color(0.5, 1.0, 0.3)         # sickly green
	eye_energy = 2.2
	# Gait: slow cadence, short drag, stiffer twist, deep hunch, heavy lumber, slow swipe.
	walk_freq = 3.0
	stride = 0.10
	twist = 0.10
	lean_run = 0.24
	bob = 0.11
	squash = 0.06
	lunge_rate = 1.0
	lunge_reach = 0.55
	can_special_leap = false      # only imps leap; the zombie just lumbers
	can_special_buff = true       # ...but the zombie channels the AoE haste (imps don't)


func _model_scene() -> PackedScene:
	return MODEL


func enemy_type() -> String:
	return ENEMY_NAME


## Heavy red+green death burst: ~3x the chunks of a normal kill, mixing crimson and
## toxic-green gib colours.
func _spawn_gore(gore_amount: int, hit_dir: Vector3) -> void:
	Gore.spawn_death(get_parent(), global_position, body_color,
		gore_amount * GORE_VOLUME_MULT, hit_dir, [GIB_RED, GIB_GREEN])
