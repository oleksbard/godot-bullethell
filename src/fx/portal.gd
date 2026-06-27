class_name Portal
extends Node3D
## A spawn portal: the rune summoning-circle art laid flat on the ground, glowing
## dark-red and flame-flickering, slowly turning. It flares open with a little
## overshoot, holds while a monster materializes in it, then collapses and frees
## itself. If the monster is killed before it emerges, the summon FAILS: the circle
## strobes and collapses early. Purely cosmetic (the imp's `emerge()` handles freeze).
##
## The visual IS the rune texture (res://decals/portal_runes.png) — no extra
## engine-drawn outline ring; the art supplies its own circle. If the texture is
## missing, a procedural ring of rune-marks stands in. Reference via
## `const Portal := preload(...)`; set position, add to world.

const MeshFactory := preload("res://src/lib/mesh_factory.gd")

const DURATION := 1.0          # total life — matches the imp's emerge time
const OPEN_TIME := 0.18        # flare open
const CLOSE_TIME := 0.22       # collapse shut
const RADIUS := 0.95
const FLAME := Color(0.6, 0.04, 0.02)   # dark ember-red (light + fallback ring)
const DECAL_FLAME := Color(1.4, 0.22, 0.07)   # flame-red the projected runes are painted with (mobile tints decal ALBEDO, not emission)
const DECAL_EMISSION := 0.45   # fraction of GLOW used for the rune decal's (untinted/white) emissive core — kept low so it reads hot-red, not white
const GLOW := 1.3              # base brightness; flickers around this like fire
const RING_TUBE := 0.02        # super-thin outline torus framing the rune circle
const RUNE_SPIN := 0.5         # rad/sec the circle slowly turns
const RUNE_TEXTURE := "res://decals/portal_runes.png"   # the art; marks otherwise

const FAIL_TIME := 0.45        # failed-summon flicker-out duration
const FAIL_STROBE := 55.0      # rad/sec harsh strobe while the summon collapses

# The monster this portal is summoning. If the spawner sets it (before add_child)
# and it dies before emerging, the portal "fails": strobes and collapses early.
var imp: Node3D

var _rune_mat: StandardMaterial3D       # marks-fallback material (emissive); null on the decal path
var _rune_decal_node: Decal             # the projected rune circle (texture path); null on the marks fallback
var _ring_mat: StandardMaterial3D       # outline torus material (marks fallback only)
var _light: OmniLight3D
var _runes: Node3D
var _tw: Tween
var _t := 0.0
var _flicker_seed := 0.0
var _watching := false         # we were given a live imp to watch
var _failed := false
var _fail_t := 0.0


func _ready() -> void:
	_watching = is_instance_valid(imp)   # imp is freshly assigned here, still valid
	_flicker_seed = randf() * TAU
	_build_runes()

	# A dim flame-red light so the ground inside/around the circle lifts a touch.
	_light = OmniLight3D.new()
	_light.light_color = FLAME
	_light.light_energy = 1.2
	_light.omni_range = 3.0
	_light.position.y = 0.4
	add_child(_light)

	_animate()


func _build_runes() -> void:
	_runes = Node3D.new()
	add_child(_runes)
	if ResourceLoader.exists(RUNE_TEXTURE):
		_rune_decal()            # projected art supplies its own circle — no torus ring
	else:
		_rune_marks()
		_build_ring()            # fallback marks get the engine-drawn outline ring


## A super-thin flame-red outline torus framing the rune circle. Same colour as
## the runes; flickers with them (see _set_glow). Not parented under _runes since
## it's rotationally symmetric — spinning it would be invisible anyway.
func _build_ring() -> void:
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.0, 0.0, 0.0)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = FLAME
	_ring_mat.emission_energy_multiplier = GLOW
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - RING_TUBE      # centreline at RADIUS, a hair-thin tube
	torus.outer_radius = RADIUS + RING_TUBE
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = _ring_mat
	ring.position.y = 0.05
	add_child(ring)


## The art, PROJECTED onto the ground with a Decal so it follows the terrain instead of
## clipping through the hills as a flat quad did. Emission-only (albedo_mix 0): it glows
## the flame-red runes onto the rock without painting over it, and the texture's alpha
## masks the projection to just the rune marks. modulate tints to flame; emission_energy
## (driven by _set_glow) does the fire flicker. The art supplies its own circle, so no
## separate outline ring is needed. Tall box (size.y) spans the hill under the footprint.
func _rune_decal() -> void:
	var tex: Texture2D = load(RUNE_TEXTURE)
	var decal := Decal.new()
	decal.texture_albedo = tex                 # alpha masks the projection to the runes; rgb painted in DECAL_FLAME
	decal.texture_emission = tex               # a hot emissive core inside the runes (untinted = bright; kept low)
	decal.albedo_mix = 1.0                      # paint the runes onto the ground (modulate tints albedo in mobile)
	decal.modulate = DECAL_FLAME               # flame-red; _set_glow pulses this for the fire flicker
	decal.emission_energy = GLOW * DECAL_EMISSION
	decal.size = Vector3(RADIUS * 2.0, 2.0, RADIUS * 2.0)
	_rune_decal_node = decal
	_runes.add_child(decal)


## Fallback when there's no rune art: a ring of short radial rune-marks (every 3rd
## one longer) — reads as ritual markings until real rune art is dropped in.
func _rune_marks() -> void:
	_rune_mat = StandardMaterial3D.new()
	_rune_mat.albedo_color = Color(0.0, 0.0, 0.0)
	_rune_mat.emission_enabled = true
	_rune_mat.emission = FLAME
	_rune_mat.emission_energy_multiplier = GLOW
	_rune_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var marks := 12
	for i in marks:
		var a := TAU * float(i) / float(marks)
		var long := i % 3 == 0
		var mark := MeshInstance3D.new()
		mark.mesh = MeshFactory.beveled_box(Vector3(0.045, 0.02, 0.26 if long else 0.14), 0.01)
		mark.material_override = _rune_mat
		mark.position = Vector3(cos(a) * RADIUS, 0.05, sin(a) * RADIUS)
		mark.rotation.y = PI / 2.0 - a          # long axis points radially outward
		_runes.add_child(mark)


## Drive the circle's brightness (runes + outline ring + ground light) to `level`,
## where 1.0 is the base glow. The projected decal and the emissive fallback parts both
## scale their emission energy.
func _set_glow(level: float) -> void:
	var e := GLOW * level
	if _rune_decal_node != null:
		# Pulse the painted-rune colour (alpha stays 1 so coverage holds) + the hot core.
		_rune_decal_node.modulate = Color(DECAL_FLAME.r * level, DECAL_FLAME.g * level, DECAL_FLAME.b * level, 1.0)
		_rune_decal_node.emission_energy = e * DECAL_EMISSION
	elif _rune_mat != null:
		_rune_mat.emission_energy_multiplier = e
	if _ring_mat != null:
		_ring_mat.emission_energy_multiplier = e
	_light.light_energy = 1.2 * level


## Flicker the circle like fire and turn it slowly while open. If the monster we're
## summoning dies before it emerges, the summon fails: strobe + collapse (see _fail).
func _process(delta: float) -> void:
	_t += delta

	if not _failed and _watching and not is_instance_valid(imp):
		_fail()

	if _failed:
		_fail_t -= delta
		var k := clampf(_fail_t / FAIL_TIME, 0.0, 1.0)            # 1 -> 0
		var strobe := (0.5 + 0.5 * sin(_t * FAIL_STROBE)) * k     # erratic, dying out
		_set_glow(1.7 * strobe)
		scale = Vector3(k, 1.0, k)                                # footprint shrinks away
		_runes.rotation.y += delta * RUNE_SPIN * 3.0             # spins up as it destabilises
		if _fail_t <= 0.0:
			queue_free()
		return

	var flick := 0.78 + 0.22 * sin(_t * 9.0 + _flicker_seed) + 0.12 * sin(_t * 23.0)
	_set_glow(flick)
	_runes.rotation.y += delta * RUNE_SPIN


## The summon failed — abandon the normal open/hold/close and flicker out fast.
func _fail() -> void:
	_failed = true
	_fail_t = FAIL_TIME
	if _tw != null and _tw.is_valid():
		_tw.kill()


## Flat-on-the-ground: open with a little overshoot, hold, then snap shut. Scale
## stays 1 on Y so the circle doesn't squash vertically — only the footprint
## grows and shrinks.
func _animate() -> void:
	scale = Vector3(0.01, 1.0, 0.01)
	_tw = create_tween()
	_tw.tween_property(self, "scale", Vector3.ONE, OPEN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_interval(DURATION - OPEN_TIME - CLOSE_TIME)
	_tw.tween_property(self, "scale", Vector3(0.01, 1.0, 0.01), CLOSE_TIME).set_ease(Tween.EASE_IN)
	_tw.tween_callback(queue_free)
