extends Control

@export var draw_bounds := false

@export_range(1, 4) var integer_scale: int = 1:
	set(value):
		integer_scale = value
		_update_panel()

@export var position_offset: Vector2i = Vector2i(0, 0):
	set(value):
		position_offset = value
		_update_panel()

@export var padding: Vector2i = Vector2i(16, 16):
	set(value):
		padding = value
		_update_panel()

@export_range(0, 16) var corner_radius: int = 8:
	set(value):
		corner_radius = value
		_update_panel()

@export_range(0.0, 1.0, 0.01) var opacity: float = 1.0:
	set(value):
		opacity = value
		_update_panel()

@export_range(0.0, 8.0, 0.1) var blur_amount: float = 2.0:
	set(value):
		opacity = value
		_update_panel()


var main: Main


func init(p_main: Main) -> void:
	main = p_main

	%DisplayTextureRect.texture = main.m8_client.get_display_texture()

	main.m8_theme_changed.connect(func(_colors: PackedColorArray, _complete: bool) -> void:
		_update_panel()
	)

func overlay_get_properties() -> Array[String]:
	return ["integer_scale", "opacity", "padding", "corner_radius"]

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if draw_bounds:
		draw_rect(Rect2(position_offset, size), Color.WHITE, false)
		
func _update_panel() -> void:
	if is_inside_tree():
		# update position
		%DisplayPanel.position = position_offset

		# update padding
		var stylebox: StyleBox = %DisplayPanel.get_theme_stylebox("panel")
		stylebox.content_margin_left = padding.x
		stylebox.content_margin_right = padding.x
		stylebox.content_margin_top = padding.y
		stylebox.content_margin_bottom = padding.y
		stylebox.corner_radius_top_left = corner_radius
		stylebox.corner_radius_top_right = corner_radius
		stylebox.corner_radius_bottom_left = corner_radius
		stylebox.corner_radius_bottom_right = corner_radius

		# update shader
		%DisplayPanel.material.set_shader_parameter("panel_opacity", opacity)
		%DisplayPanel.material.set_shader_parameter("blur_amount", blur_amount)
		%DisplayPanel.material.set_shader_parameter("panel_color", main.m8_get_theme_colors()[0])

		# update size
		var display_size := main.m8_client.get_display_texture().get_size() * integer_scale
		%DisplayTextureRect.custom_minimum_size = display_size
		%DisplayPanel.custom_minimum_size = Vector2.ZERO
		%DisplayPanel.size = Vector2.ZERO
		size = %DisplayPanel.size

		anchors_preset = anchors_preset # needed for correct anchor to be used