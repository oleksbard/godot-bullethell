class_name PauseMenu
extends CanvasLayer
## ESC toggles an in-game pause overlay with Resume / Exit. Hell-styled: a dim
## red-black scrim, an ember "PAUSED" title, and dark buttons with an ember
## border that brightens on hover. Runs while the tree is paused (PROCESS_MODE_ALWAYS).

const DIM := Color(0.02, 0.0, 0.0, 0.74)        # near-black scrim, faint red
const EMBER := Color(1.0, 0.45, 0.2)
const EMBER_DIM := Color(0.62, 0.22, 0.1)
const BTN_BG := Color(0.06, 0.02, 0.02, 0.92)

var _resume_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep handling input while paused
	layer = 10                                   # above the gameplay UI
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):     # ESC by default
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


func _set_paused(p: bool) -> void:
	get_tree().paused = p
	visible = p
	if p:
		_resume_btn.grab_focus()                 # keyboard/controller ready


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 26)
	center.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 68)
	title.add_theme_color_override("font_color", EMBER)
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	box.add_child(title)

	_resume_btn = _make_button("RESUME", _on_resume)
	box.add_child(_resume_btn)
	box.add_child(_make_button("EXIT", _on_exit))


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


func _on_resume() -> void:
	_set_paused(false)


func _on_exit() -> void:
	get_tree().quit()
