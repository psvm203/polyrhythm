extends RefCounted

const ACCENT := Color("64e2cd")


static func panel(color: Color, border: Color, padding: float = 12.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style


static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16
	var normal := panel(Color("192333"), Color("29384b"))
	var hover := panel(Color("23364a"), Color("4b8b91"))
	var pressed := panel(Color("204440"), Color("64e2cd"))
	var disabled := panel(Color("111a27"), Color("202c3c"))
	var focus := panel(Color.TRANSPARENT, ACCENT)
	for type in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			var style: StyleBoxFlat = {"normal": normal, "hover": hover, "pressed": pressed, "hover_pressed": pressed, "disabled": disabled, "focus": focus}[state]
			theme.set_stylebox(state, type, style)
		theme.set_color("font_color", type, Color("d8e4ef"))
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_pressed_color", type, ACCENT)
		theme.set_color("font_disabled_color", type, Color("56657a"))
		theme.set_color("font_focus_color", type, Color.WHITE)
	theme.set_color("font_color", "Label", Color("d8e4ef"))
	theme.set_stylebox("normal", "LineEdit", panel(Color("0a121e"), Color("29384b")))
	theme.set_stylebox("focus", "LineEdit", panel(Color("0d1a27"), ACCENT))
	theme.set_color("font_color", "LineEdit", Color("e0ebf4"))
	theme.set_color("font_placeholder_color", "LineEdit", Color("687b93"))
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", Color("28675f"))
	for type in ["HScrollBar", "VScrollBar", "HSlider"]:
		var track := panel(Color("0a121e"), Color("0a121e"), 0)
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		theme.set_stylebox("scroll", type, track)
		theme.set_stylebox("slider", type, track)
		for state in ["grabber", "grabber_highlight", "grabber_pressed", "grabber_area", "grabber_area_highlight"]:
			var handle := panel(Color("426677"), Color("426677"), 0)
			handle.content_margin_top = 3
			handle.content_margin_bottom = 3
			theme.set_stylebox(state, type, handle)
	return theme


static func primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", panel(ACCENT, ACCENT, 20))
	button.add_theme_stylebox_override("hover", panel(Color("93f2df"), Color("93f2df"), 20))
	button.add_theme_stylebox_override("pressed", panel(Color("42baa7"), Color("42baa7"), 20))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color("082922"))
