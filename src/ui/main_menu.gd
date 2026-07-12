class_name MainMenu
extends Node3D
## Title screen — the game's entry scene (project.godot run/main_scene). A small
## cinematic 3D diorama: heavy hell-fog, a featured model looming in the haze, and
## a custom molten-monolith "HELL MARINE" title (procedural geometry via TitleMesh,
## not a font) that floats gently. The camera parallaxes subtly toward the mouse.
## PLAY / OPTIONS / QUIT live in a 2D CanvasLayer overlay, reusing the ember style
## of pause_menu.gd / game_over_menu.gd.

const TitleMesh := preload("res://src/lib/title_mesh.gd")

const GAME_SCENE := "res://main.tscn"

# Featured model — fills the left of the frame. It's ~2 units tall, centred on its
# own origin; MODEL_POS is where that centre lands, MODEL_SCALE enlarges it.
const MODEL_PATH := "res://models/main-menu.glb"
const MODEL_YAW := 0.0                                  # front is +Z at yaw 0 → faces the camera (verified render)
const MODEL_POS := Vector3(-2.3, 1.3, 0.0)
const MODEL_SCALE := 1.9

# Rocky ground under the model so it isn't floating; recedes into the fog.
const GROUND_Y := -0.62                                 # top level, just under the model's feet
const GROUND_AMP := 0.38                                # bump height
const GROUND_CENTER := Vector3(-2.3, 0.0, -3.0)

# Frozen "mid-fire" flash + bolt at the gun muzzle (calibrated from front+side renders).
const MUZZLE_POS := Vector3(-3.3, 1.45, 1.2)
const MUZZLE_DIR := Vector3(-0.25, -0.75, 0.6)          # barrel points down-forward-left
const BOLT_LEN := 2.0

const TITLE_POS := Vector3(1.15, 2.5, 1.8)             # top-right, clear of the model on the left
const CAM_BASE := Vector3(0.0, 1.5, 6.5)
const CAM_LOOK := Vector3(0.0, 1.3, 0.0)
const PARALLAX_X := 0.8                                 # world units of camera sway at screen edge
const PARALLAX_Y := 0.5
const PARALLAX_DAMP := 4.0

const PIX_SIZE := Vector2i(768, 432)                    # low-res 3D buffer → nearest-upscaled = pixel-art (lower = chunkier)

const EMBER := Color(1.0, 0.45, 0.2)
const EMBER_DIM := Color(0.62, 0.22, 0.1)
const BTN_BG := Color(0.06, 0.02, 0.02, 0.92)

var _view: SubViewport
var _camera: Camera3D
var _title: MeshInstance3D
var _t := 0.0
var _parallax := Vector2.ZERO

var _main_box: VBoxContainer
var _options_box: VBoxContainer
var _play_btn: Button
var _back_btn: Button


func _ready() -> void:
	_build_viewport()
	_build_environment()
	_build_lights()
	_build_ground()
	_build_model()
	_build_muzzle_fx()
	_build_title()
	_build_camera()
	_build_ui()
	_play_btn.grab_focus()


func _process(delta: float) -> void:
	_t += delta

	# Camera parallax: damp toward the mouse's offset from screen centre.
	var vp := get_viewport()
	var msize := vp.get_visible_rect().size
	var ndc := Vector2.ZERO
	if msize.x > 0.0 and msize.y > 0.0:
		ndc = (vp.get_mouse_position() / msize) * 2.0 - Vector2.ONE
	_parallax = _parallax.lerp(ndc, clampf(delta * PARALLAX_DAMP, 0.0, 1.0))
	_camera.position = CAM_BASE + Vector3(_parallax.x * PARALLAX_X, -_parallax.y * PARALLAX_Y, 0.0)
	_camera.look_at(CAM_LOOK, Vector3.UP)

	# Title floats gently — steady glow, no flicker.
	_title.position.y = TITLE_POS.y + sin(_t * 1.2) * 0.05


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):        # ESC: back out of options, else quit
		if _options_box.visible:
			_show_options(false)
		else:
			get_tree().quit()
		get_viewport().set_input_as_handled()


# --- 3D scene ---------------------------------------------------------------

func _build_viewport() -> void:
	# Render the 3D scene into a small buffer, then nearest-upscale it to fill the
	# screen → chunky pixel-art look. The 2D button overlay stays crisp on top.
	_view = SubViewport.new()
	_view.size = PIX_SIZE
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.msaa_3d = Viewport.MSAA_DISABLED               # crisp pixels, no edge smoothing
	add_child(_view)

	var layer := CanvasLayer.new()
	layer.layer = -1                                     # behind the PLAY/OPTIONS/QUIT overlay
	var screen := TextureRect.new()
	screen.texture = _view.get_texture()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # the actual pixelation
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	add_child(layer)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.010, 0.010)    # dark red void
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.15, 0.11)    # red hell ambiance
	env.ambient_light_energy = 0.8                       # lighter overall
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.4

	# Red haze behind the model; thinned so the model itself isn't hazed out.
	env.fog_enabled = true
	env.fog_light_color = Color(0.34, 0.07, 0.05)
	env.fog_density = 0.045

	# Restrained glow so the title reads without turning the scene glossy/pretty.
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.3                          # only the hottest molten bits bloom (no white blowout)
	env.set_glow_level(4, 1.0)
	env.set_glow_level(5, 1.0)

	var we := WorldEnvironment.new()
	we.environment = env
	_view.add_child(we)


func _build_lights() -> void:
	# Warm key raking across the model from the front-right so it reads clearly.
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.55, 0.3)
	key.light_energy = 2.6
	key.rotation = Vector3(deg_to_rad(-30.0), deg_to_rad(35.0), 0.0)
	key.shadow_enabled = true
	_view.add_child(key)

	# Front fill on the model so its face isn't lost to shadow.
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.62, 0.38)
	fill.light_energy = 6.0
	fill.omni_range = 11.0
	fill.position = MODEL_POS + Vector3(0.6, 1.1, 4.0)
	_view.add_child(fill)

	# Thin blood-red rim behind the model — silhouettes it against the black.
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.9, 0.1, 0.04)
	rim.light_energy = 5.0
	rim.omni_range = 8.0
	rim.position = MODEL_POS + Vector3(0.0, 0.2, -2.2)
	_view.add_child(rim)


func _build_model() -> void:
	if not ResourceLoader.exists(MODEL_PATH):
		return                                          # not added yet — fogged title scene stands alone
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		return
	var inst := packed.instantiate() as Node3D
	inst.position = MODEL_POS
	inst.rotation.y = deg_to_rad(MODEL_YAW)
	inst.scale = Vector3.ONE * MODEL_SCALE
	_view.add_child(inst)


## A lumpy charred-rock ground so the model isn't floating; edges fade into the fog.
func _build_ground() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.14
	var nx := 60
	var nz := 36
	var cs := 0.6
	var ox := GROUND_CENTER.x - nx * cs * 0.5
	var oz := GROUND_CENTER.z - nz * cs * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for gz in nz:
		for gx in nx:
			var a := _ground_pt(gx, gz, ox, oz, cs, noise)
			var b := _ground_pt(gx + 1, gz, ox, oz, cs, noise)
			var c := _ground_pt(gx + 1, gz + 1, ox, oz, cs, noise)
			var d := _ground_pt(gx, gz + 1, ox, oz, cs, noise)
			_ground_tri(st, a, b, c)
			_ground_tri(st, a, c, d)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.035, 0.035)         # charred basalt; the red ambiance tints it
	mat.roughness = 0.95
	mat.metallic = 0.0

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	_view.add_child(mi)


func _ground_pt(gx: int, gz: int, ox: float, oz: float, cs: float, noise: FastNoiseLite) -> Vector3:
	var wx := ox + gx * cs
	var wz := oz + gz * cs
	var wy := noise.get_noise_2d(wx, wz) * GROUND_AMP + GROUND_Y
	return Vector3(wx, wy, wz)


func _ground_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length() < 0.000001:
		return
	n = n.normalized()
	if n.y < 0.0:
		n = -n
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


## A single frozen frame of the gun firing — a hot muzzle flash + a bolt caught mid-flight.
func _build_muzzle_fx() -> void:
	var holder := Node3D.new()
	holder.position = MUZZLE_POS
	_view.add_child(holder)
	holder.look_at(MUZZLE_POS + MUZZLE_DIR, Vector3.UP)   # local -Z aims along the shot

	# Bolt: a bright stretched streak frozen along the firing line.
	var bolt := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, BOLT_LEN)
	bolt.mesh = bm
	bolt.position = Vector3(0.0, 0.0, -BOLT_LEN * 0.5 - 0.25)
	bolt.material_override = _emissive(Color(1.0, 0.5, 0.16), 6.0)
	holder.add_child(bolt)

	# Muzzle flash core.
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	core.mesh = sm
	core.material_override = _emissive(Color(1.0, 0.82, 0.45), 9.0)
	holder.add_child(core)

	# Flash spikes — a small starburst facing along the shot.
	for ang in [0.0, 55.0, 110.0, 145.0]:
		var spike := MeshInstance3D.new()
		var sbm := BoxMesh.new()
		sbm.size = Vector3(0.028, 0.55, 0.028)
		spike.mesh = sbm
		spike.rotation.z = deg_to_rad(ang)
		spike.material_override = _emissive(Color(1.0, 0.55, 0.2), 6.0)
		holder.add_child(spike)


func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # pure glow, not lit
	return m


func _build_title() -> void:
	# Custom molten-monolith letters (procedural faces, no font) + untextured lava
	# material that emits the per-vertex heat baked by TitleMesh.
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/ui/molten_title.gdshader")

	_title = MeshInstance3D.new()
	_title.mesh = TitleMesh.build("HELL\nMARINE")
	_title.material_override = mat
	_title.position = TITLE_POS
	_view.add_child(_title)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_camera.position = CAM_BASE
	_camera.current = true
	_view.add_child(_camera)
	_camera.look_at(CAM_LOOK, Vector3.UP)        # after add_child: look_at needs a global transform


# --- 2D overlay (buttons + options) -----------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Lower-centre band so the stack clears the 3D title above it.
	var center := CenterContainer.new()
	center.anchor_left = 0.5                       # right column — model owns the left
	center.anchor_right = 1.0
	center.anchor_top = 0.58                       # below the top-right title
	center.anchor_bottom = 0.96
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)

	_main_box = VBoxContainer.new()
	_main_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_box.add_theme_constant_override("separation", 16)
	center.add_child(_main_box)

	_play_btn = _make_button("PLAY", _on_play)
	_main_box.add_child(_play_btn)
	_main_box.add_child(_make_button("OPTIONS", func() -> void: _show_options(true)))
	_main_box.add_child(_make_button("QUIT", func() -> void: get_tree().quit()))

	_options_box = _build_options()
	_options_box.visible = false
	center.add_child(_options_box)


func _build_options() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)

	box.add_child(_option_label("VOLUME"))
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.01
	vol.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	vol.custom_minimum_size = Vector2(400.0, 24.0)
	vol.value_changed.connect(_on_volume)
	box.add_child(vol)

	var fs := CheckButton.new()
	fs.text = "Fullscreen"
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs.add_theme_color_override("font_color", EMBER)
	fs.add_theme_color_override("font_hover_color", Color.WHITE)
	fs.toggled.connect(_on_fullscreen)
	box.add_child(fs)

	_back_btn = _make_button("BACK", func() -> void: _show_options(false))
	box.add_child(_back_btn)
	return box


func _option_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", EMBER)
	return l


func _show_options(on: bool) -> void:
	_options_box.visible = on
	_main_box.visible = not on
	if on:
		_back_btn.grab_focus()
	else:
		_play_btn.grab_focus()


# --- handlers ---------------------------------------------------------------

func _on_play() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_volume(v: float) -> void:
	# maxf keeps db finite at 0 (linear_to_db(0) is -inf); -80 dB reads as silent.
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))


func _on_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


# ponytail: ember button styling is duplicated across the three menus
# (pause_menu, game_over_menu, here); extract a shared menu_style.gd if a fourth appears.
func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(400, 80)
	b.add_theme_font_size_override("font_size", 36)
	b.add_theme_color_override("font_color", EMBER)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _btn_box(EMBER_DIM))
	b.add_theme_stylebox_override("hover", _btn_box(EMBER))
	b.add_theme_stylebox_override("pressed", _btn_box(EMBER))
	b.add_theme_stylebox_override("focus", _btn_box(EMBER))
	b.pressed.connect(handler)
	return b


func _btn_box(border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BTN_BG
	s.border_color = border
	s.set_border_width_all(3)
	s.set_corner_radius_all(5)
	s.content_margin_left = 30
	s.content_margin_right = 30
	s.content_margin_top = 18
	s.content_margin_bottom = 18
	return s
