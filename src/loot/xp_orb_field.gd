class_name XpOrbField
extends Node3D
## Owns every live XP orb. Wired by Main: connect WaveSpawner.imp_spawned -> on_imp_spawned
## (so each imp's death drops an orb), and WaveSpawner.wave_cleared -> vacuum_all (so leftover
## orbs all fly to the marine when a wave ends — no earned XP is lost). Sits at world origin;
## orbs are its children.
## ponytail: per-orb nodes + queue_free; pool / MultiMesh only if orb counts ever spike.

const XpOrbScript := preload("res://src/loot/xp_orb.gd")

var player: Node3D                # the marine; handed to each spawned orb


## Bind one imp's death to an orb drop. Connected to WaveSpawner.imp_spawned by Main.
func on_imp_spawned(imp: Node) -> void:
	imp.died.connect(drop_orb)


## Drop one orb at `world_pos` worth `xp_value` (matches Imp.died's arguments).
func drop_orb(world_pos: Vector3, xp_value: float) -> void:
	var orb := XpOrbScript.new()
	orb.player = player
	orb.xp_value = xp_value
	add_child(orb)
	orb.global_position = world_pos


## Pull every live orb to the marine regardless of distance (called on a cleared wave).
func vacuum_all() -> void:
	for orb in get_children():
		if orb.has_method("vacuum"):
			orb.vacuum()
