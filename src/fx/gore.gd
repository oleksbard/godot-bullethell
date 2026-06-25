class_name Gore
extends RefCounted
## Death effects for an imp: a burst of gib chunks (temporary, physics-y) plus a
## splatter of textured blood decals on the ground. How many decals is decided by
## the caller (the projectile picks an amount for its type — see Projectile), so a
## weak bolt barely bleeds and a heavy weapon paints the floor. Each decal sits
## for its own randomized lifetime, then fades out and frees itself — so the
## island stays gory mid-fight but doesn't accumulate forever. Reference via
## `const Gore := preload(...)` and call Gore.spawn_death(...).

const GibScript := preload("res://src/fx/gib.gd")

const GIB_COUNT := 8
const BLOOD_SPREAD := 1.9       # how far the splatter scatters from the death point
const BLOOD_GROUP := "blood"
const BLOOD_MAX := 600          # ponytail: hard cap; oldest blood trimmed past this
const BLOOD_HOLD := 7.0         # base seconds fully visible before fading (×0.8–1.2 per decal)
const BLOOD_FADE := 3.0         # base fade-out duration, then the decal frees itself

# The user-supplied splat textures (alpha cut-outs). Picked at random per decal.
const BLOOD_TEXTURES := [
	"res://decals/blood_spot_01.png",
	"res://decals/blood_spot_02.png",
	"res://decals/blood_spot_03.png",
	"res://decals/blood_spot_04.png",
	"res://decals/blood_spot_05.png",
]


## Spawn gibs + `blood_count` blood decals for a death at `pos`, parented under
## `parent` (world space). The killer decides blood_count (its projectile type).
static func spawn_death(parent: Node, pos: Vector3, color: Color, blood_count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_spawn_gibs(parent, pos, color, rng)
	_spawn_blood(parent, pos, rng, blood_count)


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


static func _spawn_blood(parent: Node, pos: Vector3, rng: RandomNumberGenerator, count: int) -> void:
	for i in count:
		var tex: Texture2D = load(BLOOD_TEXTURES[rng.randi_range(0, BLOOD_TEXTURES.size() - 1)])
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA   # honour the splat's alpha cut-out
		# Slight per-decal darken/desaturate so identical textures don't read as copies.
		var k := rng.randf_range(0.75, 1.0)
		mat.albedo_color = Color(1.0, k, k, 1.0)
		mat.roughness = 0.3             # wet sheen so it reads as fresh blood
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var plane := PlaneMesh.new()    # lies flat in XZ, faces +Y — a ground decal
		var s := rng.randf_range(0.5, 2.1)         # widely varied splat sizes
		plane.size = Vector2(s, s)
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.material_override = mat
		mi.add_to_group(BLOOD_GROUP)
		parent.add_child(mi)
		var off := Vector3(rng.randf_range(-BLOOD_SPREAD, BLOOD_SPREAD), 0.0, rng.randf_range(-BLOOD_SPREAD, BLOOD_SPREAD))
		mi.global_position = pos + off + Vector3(0.0, 0.03 + float(i) * 0.003, 0.0)  # stagger y: no z-fight
		mi.rotation.y = rng.randf_range(0.0, TAU)
		_fade_out(mi, mat, rng)
	_trim_blood(parent)


## Hold the decal, then fade its alpha to nothing and free it — so blood lingers
## but doesn't pile up forever. Each decal scales its hold + fade by a random
## 0.8–1.2, so a batch spawned together still disappears at staggered times. A
## node-bound tween dies with the node if it's trimmed first.
static func _fade_out(mi: MeshInstance3D, mat: StandardMaterial3D, rng: RandomNumberGenerator) -> void:
	var k := rng.randf_range(0.8, 1.2)
	var col := mat.albedo_color
	var tw := mi.create_tween()
	tw.tween_interval(BLOOD_HOLD * k)
	tw.tween_property(mat, "albedo_color", Color(col.r, col.g, col.b, 0.0), BLOOD_FADE * k)
	tw.tween_callback(mi.queue_free)


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
