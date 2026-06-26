class_name BlobShadow
extends MeshInstance3D
## A cheap fake shadow: a soft dark radial disc laid flat on the ground beneath a
## unit, parented to it so it follows for free. No shadow-map cost — one unshaded
## transparent quad. The mesh + material are shared across every blob (size comes
## from node scale), so a swarm of these is just N near-free nodes.
## ponytail: one draw per blob; fold into a MultiMesh if the swarm ever does.

const Self := preload("res://src/fx/blob_shadow.gd")   # cold-load safe self-ref (no global class cache)

const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.8)
const GROUND_Y := 0.04          # sit just above the surface to avoid z-fighting

static var _mat: StandardMaterial3D
static var _mesh: QuadMesh


## A blob shadow disc of the given world radius. Parent it to a unit at its feet.
static func make(radius: float) -> MeshInstance3D:
	var s := Self.new()
	s.mesh = _shared_mesh()
	s.material_override = _shared_mat()
	s.rotation.x = -PI * 0.5                       # lay the quad flat, facing up
	s.scale = Vector3(radius * 2.0, radius * 2.0, 1.0)
	s.position.y = GROUND_Y
	s.cast_shadow = SHADOW_CASTING_SETTING_OFF
	return s


## Shared 1×1 quad (sized per-blob via node scale).
static func _shared_mesh() -> QuadMesh:
	if _mesh == null:
		_mesh = QuadMesh.new()
		_mesh.size = Vector2.ONE
	return _mesh


## Shared unshaded material: a soft radial alpha (opaque centre → transparent rim).
static func _shared_mat() -> StandardMaterial3D:
	if _mat != null:
		return _mat
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))      # opaque centre
	grad.set_color(1, Color(1, 1, 1, 0))      # transparent rim
	grad.add_point(0.7, Color(1, 1, 1, 1))    # stay solid out to 0.7, soft only at the very edge
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)        # reaches transparent at the disc edge
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = SHADOW_COLOR
	_mat.albedo_texture = tex
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat
