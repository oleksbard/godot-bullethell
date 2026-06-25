class_name Gore
extends RefCounted
## Death effects for an imp: a burst of gib chunks (temporary, physics-y) plus a
## splatter of flat blood decals on the ground (persistent — lots of blood).
## Reference via `const Gore := preload(...)` and call Gore.spawn_death(...).

const GibScript := preload("res://src/fx/gib.gd")

const GIB_COUNT := 8
const BLOOD_COUNT := 14         # decals per death — "a lot of blood"
const BLOOD_GROUP := "blood"
const BLOOD_MAX := 600          # ponytail: hard cap; oldest blood trimmed past this


## Spawn gibs + blood for a death at `pos`, parented under `parent` (world space).
static func spawn_death(parent: Node, pos: Vector3, color: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_spawn_gibs(parent, pos, color, rng)
	_spawn_blood(parent, pos, rng)


static func _spawn_gibs(parent: Node, pos: Vector3, color: Color, rng: RandomNumberGenerator) -> void:
	for i in GIB_COUNT:
		var g := GibScript.new()
		g.color = color
		g.size = rng.randf_range(0.12, 0.26)
		parent.add_child(g)
		g.global_position = pos + Vector3(0.0, 0.5, 0.0)
		var a := rng.randf_range(0.0, TAU)
		var out := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(2.0, 5.0)
		out.y = rng.randf_range(3.0, 6.0)
		var spin := Vector3(rng.randf_range(-12, 12), rng.randf_range(-12, 12), rng.randf_range(-12, 12))
		g.launch(out, spin)


static func _spawn_blood(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> void:
	for i in BLOOD_COUNT:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.22 + rng.randf_range(0.0, 0.3), 0.0, 0.0)
		mat.roughness = 0.25            # wet sheen so it reads as fresh blood
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var plane := PlaneMesh.new()    # lies flat in XZ, faces +Y — a ground decal
		var s := rng.randf_range(0.4, 1.3)
		plane.size = Vector2(s, s)
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.material_override = mat
		mi.add_to_group(BLOOD_GROUP)
		parent.add_child(mi)
		var off := Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.2, 1.2))
		mi.global_position = pos + off + Vector3(0.0, 0.03 + float(i) * 0.003, 0.0)  # stagger y: no z-fight
		mi.rotation.y = rng.randf_range(0.0, TAU)
	_trim_blood(parent)


## Keep the blood decal count bounded — free the oldest beyond BLOOD_MAX.
static func _trim_blood(node: Node) -> void:
	var tree := node.get_tree()
	if tree == null:
		return
	var blood := tree.get_nodes_in_group(BLOOD_GROUP)
	var excess := blood.size() - BLOOD_MAX
	var i := 0
	while i < excess:
		if is_instance_valid(blood[i]):
			blood[i].queue_free()
		i += 1
