class_name ScreenGrade
extends CanvasLayer
## Full-screen post-process "video filter" grade (sharpen + clarity + saturation),
## ported from the delivery-game web build's postGrade pass (see screen_grade.gdshader).
## Sits on layer 0 — below the gameplay UI (HUD/indicators on layer 1, pause on 10) — so
## it grades the rendered 3D scene only; the UI draws on top, ungraded.
## Drop it in the composition root with add_child(ScreenGrade.new()).

const GRADE_SHADER: Shader = preload("res://src/fx/screen_grade.gdshader")

# delivery-game's tuned defaults (DEFAULT_GRADE_PARAMS); shader uniforms default to these
# too — set here so the values live next to the code that owns the look.
const SHARPNESS := 1.0
const CLARITY := 1.0
const SATURATION := 1.12   # was 1.35; lowered — 1.35 over-pushed the scene's reds


func _ready() -> void:
	layer = 0                              # under the UI: grade the 3D scene, not the HUD

	var mat := ShaderMaterial.new()
	mat.shader = GRADE_SHADER
	mat.set_shader_parameter("sharpness", SHARPNESS)
	mat.set_shader_parameter("clarity", CLARITY)
	mat.set_shader_parameter("saturation", SATURATION)

	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # fill the viewport
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE                 # never eat input
	rect.material = mat
	add_child(rect)
