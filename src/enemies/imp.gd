class_name Imp
extends "res://src/enemies/enemy.gd"
## A weak imp: the optimized imp.glb, walked/jabbed in imp_anim.gdshader (no skeleton —
## see Enemy + the shader). Uses the Enemy base's default tuning (those defaults ARE the
## imp's values); only its model, type label, and per-wave base stats are imp-specific.

const MODEL: PackedScene = preload("res://models/imp_opt.glb")
const ENEMY_NAME := "Imp"        # display label for the recap's kills-by-type tally
const BASE_HP := 3.0             # wave-1 HP; one pistol bolt (dmg 5) one-shots it. Spawner scales per wave.
const BASE_ATTACK_DAMAGE := 1.0  # wave-1 melee damage; spawner scales per wave
const BASE_XP := 1.0             # wave-1 XP value; spawner scales per wave


func _model_scene() -> PackedScene:
	return MODEL


func enemy_type() -> String:
	return ENEMY_NAME
