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
const HIT_GIB_COUNT := 3        # smaller flesh burst when a hit doesn't kill
const GIB_CONE := 0.8           # gibs fly in a ±0.8 rad cone around the bolt's travel
const BLOOD_SPREAD := 1.9       # how far the splatter scatters from the death point
const BLOOD_JITTER := 0.4       # ±rad each decal's spray varies off the travel axis
const BLOOD_GROUP := "blood"
const BLOOD_MAX := 600          # ponytail: hard cap; oldest blood trimmed past this
const BLOOD_HOLD := 7.0         # base seconds fully visible before fading (×0.8–1.2 per decal)
const BLOOD_FADE := 3.0         # base fade-out duration, then the decal frees itself

# Directional splat textures: each sprays from its lower-left toward its top-right
# corner. On a flat PlaneMesh (UVs u→+X, v→+Z) that diagonal is a fixed local
# heading; this offset rotates the decal so the spray lines up with the world
# travel direction. Calibrated by render — see the spray-points-forward test.
const DECAL_DIR_OFFSET := PI * 0.25

# Blood reads as a glowing sticker if it's bright + glossy on the near-black
# ground (it even trips the scene's bloom). This dark, matte crimson tint sinks it
# into the charred basalt — a deep stain, not neon. Multiplies the texture; varied
# slightly per decal so copies don't read identical.
const BLOOD_TINT := Color(0.5, 0.1, 0.08)
const BLOOD_ROUGHNESS := 0.9    # matte: no wet specular glint to catch the eye

# The directional splat textures (alpha cut-outs) — the forward spray. Random/decal.
const BLOOD_TEXTURES := [
	"res://decals/blood_direct_01.png",
	"res://decals/blood_direct_02.png",
	"res://decals/blood_direct_03.png",
	"res://decals/blood_direct_04.png",
	"res://decals/blood_direct_05.png",
	"res://decals/blood_direct_06.png",
]

# Round, non-directional splats — one is laid on top at the impact point as the
# central wound pool, over the directional spray.
const BLOOD_POOL_TEXTURES := [
	"res://decals/blood_spot_01.png",
	"res://decals/blood_spot_02.png",
	"res://decals/blood_spot_03.png",
	"res://decals/blood_spot_04.png",
	"res://decals/blood_spot_05.png",
]


## Spawn gibs + `blood_count` blood decals for a death at `pos`, parented under
## `parent` (world space). The killer decides blood_count (its projectile type) and
## `hit_dir` (its travel direction) so the gore sprays forward — relentless force.
static func spawn_death(parent: Node, pos: Vector3, color: Color, blood_count: int, hit_dir: Vector3 = Vector3.ZERO) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Horizontal travel direction; random if none supplied (e.g. a wave wipe) so
	# the death still reads as a directional spray rather than a symmetric pool.
	var fwd := Vector3(hit_dir.x, 0.0, hit_dir.z)
	if fwd.length() < 0.01:
		var a := rng.randf_range(0.0, TAU)
		fwd = Vector3(cos(a), 0.0, sin(a))
	fwd = fwd.normalized()
	_spawn_gibs(parent, pos, color, rng, fwd)
	_spawn_blood(parent, pos, rng, blood_count, fwd)


## Lighter feedback for a hit that does NOT kill: a small flesh burst + one blood
## decal, sprayed forward along `hit_dir`. No central wound pool — that's a death cue.
static func spawn_hit(parent: Node, pos: Vector3, color: Color, hit_dir: Vector3 = Vector3.ZERO) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fwd := Vector3(hit_dir.x, 0.0, hit_dir.z)
	if fwd.length() < 0.01:
		var a := rng.randf_range(0.0, TAU)
		fwd = Vector3(cos(a), 0.0, sin(a))
	fwd = fwd.normalized()
	_spawn_gibs(parent, pos, color, rng, fwd, HIT_GIB_COUNT)

	# A single directional spray decal ahead of the impact (no pool on top).
	var tex: Texture2D = load(BLOOD_TEXTURES[rng.randi_range(0, BLOOD_TEXTURES.size() - 1)])
	var yaw := atan2(-fwd.x, -fwd.z) + DECAL_DIR_OFFSET + rng.randf_range(-BLOOD_JITTER, BLOOD_JITTER)
	var off := fwd * rng.randf_range(0.0, 0.8)
	_decal(parent, tex, pos + off, rng.randf_range(0.6, 1.2), yaw, 0.03, rng)
	_trim_blood(parent)


static func _spawn_gibs(parent: Node, pos: Vector3, color: Color, rng: RandomNumberGenerator, fwd: Vector3, count: int = GIB_COUNT) -> void:
	for i in count:
		var g := GibScript.new()
		g.color = color
		g.size = rng.randf_range(0.12, 0.26)
		parent.add_child(g)
		g.global_position = pos + Vector3(0.0, 0.5, 0.0)
		# Fly mostly along the bolt's travel: a random cone around fwd, varied
		# speed + upward arc so they don't launch in lockstep.
		var horiz := fwd.rotated(Vector3.UP, rng.randf_range(-GIB_CONE, GIB_CONE))
		var out := horiz * rng.randf_range(2.5, 6.0)
		out.y = rng.randf_range(2.5, 5.5)
		var spin := Vector3(rng.randf_range(-12, 12), rng.randf_range(-12, 12), rng.randf_range(-12, 12))
		g.launch(out, spin)


static func _spawn_blood(parent: Node, pos: Vector3, rng: RandomNumberGenerator, count: int, fwd: Vector3) -> void:
	var base_yaw := atan2(-fwd.x, -fwd.z) + DECAL_DIR_OFFSET   # texture spray aligned to travel
	var side := Vector3(-fwd.z, 0.0, fwd.x)                    # perpendicular, for lateral scatter
	for i in count:
		var tex: Texture2D = load(BLOOD_TEXTURES[rng.randi_range(0, BLOOD_TEXTURES.size() - 1)])
		var s := rng.randf_range(0.6, 2.2)         # widely varied splat sizes
		# Bias the splatter forward along travel (the force carries it), with some
		# lateral spread — a fan ahead of the impact, not a ring around it.
		var along := rng.randf_range(-0.2, 1.0) * BLOOD_SPREAD
		var lateral := rng.randf_range(-0.5, 0.5) * BLOOD_SPREAD
		var off := fwd * along + side * lateral
		var yaw := base_yaw + rng.randf_range(-BLOOD_JITTER, BLOOD_JITTER)
		_decal(parent, tex, pos + off, s, yaw, 0.03 + float(i) * 0.003, rng)

	# One round impact pool on top, at the hit point — the central wound, over the
	# directional spray (highest y so it draws last). Round → any rotation.
	var ptex: Texture2D = load(BLOOD_POOL_TEXTURES[rng.randi_range(0, BLOOD_POOL_TEXTURES.size() - 1)])
	_decal(parent, ptex, pos, rng.randf_range(1.0, 1.8), rng.randf_range(0.0, TAU),
		0.03 + float(count) * 0.003 + 0.01, rng)

	_trim_blood(parent)


## Build one flat ground blood decal (textured PlaneMesh) and start its fade.
static func _decal(parent: Node, tex: Texture2D, pos: Vector3, size: float, yaw: float, y_off: float, rng: RandomNumberGenerator) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA   # honour the splat's alpha cut-out
	var k := rng.randf_range(0.8, 1.0)                     # per-decal value variance
	mat.albedo_color = Color(BLOOD_TINT.r * k, BLOOD_TINT.g * k, BLOOD_TINT.b * k, 1.0)
	mat.roughness = BLOOD_ROUGHNESS
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var plane := PlaneMesh.new()    # lies flat in XZ, faces +Y — a ground decal
	plane.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.add_to_group(BLOOD_GROUP)
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0.0, y_off, 0.0)    # staggered y: no z-fight
	mi.rotation.y = yaw
	_fade_out(mi, mat, rng)


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
