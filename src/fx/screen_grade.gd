class_name ScreenGrade
extends CanvasLayer
## Full-screen hell post stack: the ported "video filter" grade (sharpen + clarity +
## saturation) plus a stylised hell look — cel posterize + Sobel ink outlines (#1),
## a shadow halftone dot screen (#2), and ember heat-haze (#5). All in ONE pass (see
## screen_grade.gdshader for why), on layer 0 — below the gameplay UI (HUD/indicators
## on layer 1, pause on 10) — so it processes the rendered 3D scene only; the UI draws
## on top, untouched. Drop it in the composition root with add_child(ScreenGrade.new()).
## Tune the look here; set any *_STRENGTH/AMOUNT to 0.0 to disable that effect and A/B.

const GRADE_SHADER: Shader = preload("res://src/fx/screen_grade.gdshader")

# Video grade (delivery-game DEFAULT_GRADE_PARAMS).
const SHARPNESS := 1.0
const CLARITY := 2.0
const SATURATION := 1.35   # was 1.35; lowered — 1.35 over-pushed the scene's reds

# #1 cel / comic.
const POSTERIZE_BANDS := 16.0      # luma bands (fewer = chunkier)
const POSTERIZE_AMOUNT := 0.95     # 0 = off
const OUTLINE_STRENGTH := 0.7     # ink-edge darkening; 0 = off
const OUTLINE_THRESHOLD := 0.1   # edge sensitivity (lower = more edges)

# #1b contrast / #2b cel specular / #3 rim highlight (the "shine" pass).
const CONTRAST := 0.35         # S-curve punch (darks deeper, brights hotter); 0 = off
const SPEC_THRESHOLD := 0.8    # luma where the gloss plateau starts
const SPEC_SOFTNESS := 0.12    # plateau edge softness
const SPEC_STRENGTH := 0.6     # push the brightest luma toward a hot highlight; 0 = off
const RIM_STRENGTH := 0.6      # bright ember rim on the lit side of edges; 0 = off
const RIM_THRESHOLD := 0.08    # how much brighter the lit side must be to rim

# #2 halftone dots in shadows.
const HALFTONE_STRENGTH := 0.15   # 0 = off
const HALFTONE_SCALE := 7.0       # dot cell size, px

# #5 ember heat-haze.
const HAZE_STRENGTH := 0     # max UV warp near hot pixels; 0 = off
const HAZE_SPEED := 0


func _ready() -> void:
	layer = 0                              # under the UI: process the 3D scene, not the HUD

	var mat := ShaderMaterial.new()
	mat.shader = GRADE_SHADER
	mat.set_shader_parameter("sharpness", SHARPNESS)
	mat.set_shader_parameter("clarity", CLARITY)
	mat.set_shader_parameter("saturation", SATURATION)
	mat.set_shader_parameter("posterize_bands", POSTERIZE_BANDS)
	mat.set_shader_parameter("posterize_amount", POSTERIZE_AMOUNT)
	mat.set_shader_parameter("outline_strength", OUTLINE_STRENGTH)
	mat.set_shader_parameter("outline_threshold", OUTLINE_THRESHOLD)
	mat.set_shader_parameter("contrast", CONTRAST)
	mat.set_shader_parameter("spec_threshold", SPEC_THRESHOLD)
	mat.set_shader_parameter("spec_softness", SPEC_SOFTNESS)
	mat.set_shader_parameter("spec_strength", SPEC_STRENGTH)
	mat.set_shader_parameter("rim_strength", RIM_STRENGTH)
	mat.set_shader_parameter("rim_threshold", RIM_THRESHOLD)
	mat.set_shader_parameter("halftone_strength", HALFTONE_STRENGTH)
	mat.set_shader_parameter("halftone_scale", HALFTONE_SCALE)
	mat.set_shader_parameter("haze_strength", HAZE_STRENGTH)
	mat.set_shader_parameter("haze_speed", HAZE_SPEED)

	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # fill the viewport
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE                 # never eat input
	rect.material = mat
	add_child(rect)
