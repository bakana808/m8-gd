@tool
extends SettingBase


@export var value := Vector2i.ZERO:
	set(p_value):
		value = p_value.clamp(min_value, max_value)
		await _update()
		_emit_value_changed()

@export var min_value := Vector2i.ZERO:
	set(p_value):
		min_value = p_value
		value = value

@export var max_value := Vector2i(100, 100):
	set(p_value):
		max_value = p_value
		value = value


func _ready() -> void:

	%SpinBoxX.theme_type_variation = "SettingControlVec2SpinBox"
	%SpinBoxY.theme_type_variation = "SettingControlVec2SpinBox"

	%SpinBoxX.get_line_edit().theme_type_variation = "SettingControlVec2LineEdit"
	%SpinBoxY.get_line_edit().theme_type_variation = "SettingControlVec2LineEdit"

	%SpinBoxX.value_changed.connect(func(p_value: float) -> void:
		value = Vector2i(int(p_value), value.y)
	)
	%SpinBoxY.value_changed.connect(func(p_value: float) -> void:
		value = Vector2i(value.x, int(p_value))
	)

	_update()


func _update() -> void:

	if not is_inside_tree(): await ready

	modulate = Color.WHITE if enabled else Color.from_hsv(0, 0, 0.25)
	%SpinBoxX.editable = enabled
	%SpinBoxY.editable = enabled

	if setting_name == "":
		%LabelName.visible = false
	else:
		%LabelName.visible = true
		%LabelName.text = setting_name

	%LabelName.custom_minimum_size.x = setting_name_min_width

	%SpinBoxX.min_value = min_value.x
	%SpinBoxX.max_value = max_value.x

	%SpinBoxY.min_value = min_value.y
	%SpinBoxY.max_value = max_value.y

	%SpinBoxX.value = value.x
	%SpinBoxY.value = value.y


func init(p_value: Variant, changed_fn: Callable) -> void:
	assert(p_value is Vector2i)
	super(p_value, changed_fn)
