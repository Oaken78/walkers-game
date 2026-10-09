class_name WorkshopTheme
extends RefCounted
## The workshop UI look, built in code from the GDD 10 palette: ink panels, off-white text, the player accent for
## what is live (armed part, changed stat, exit). No threat hue (rule 2). Scrap amounts use the salvage cyan (rule 3).
## Font sizes are in base pixels (the project is 1280x720 and stretches, so 1080p is 1.5 x): the smallest text is
## SMALL_FONT x 1.5 = 21 px tall at 1080p, above the 14 px floor (task T09, readability).

const INK: Color = Color("14161A")
const PANEL_BG: Color = Color(0.078, 0.086, 0.102, 0.9)
const PANEL_EDGE: Color = Color("3A3E45")
const BODY: Color = Color("E6E1D6")
const MUTED: Color = Color("B3AFA4")
const ACCENT: Color = Color("FF8A3D")
## A better change: the accent. A worse change: light neutral grey. They are at least 0.25 luma apart (GDD 12) and
## neither is the threat hue.
const BETTER: Color = ACCENT
const WORSE: Color = Color("E2E2E2")
const SALVAGE: Color = Color("3DE0E8")
const BUTTON_BG: Color = Color("2B2F36")
const BUTTON_HOVER: Color = Color("3B4048")
const BUTTON_DISABLED_BG: Color = Color("1C1F24")
const DISABLED_TEXT: Color = Color("8E8A80")

const FONT: int = 16
const SMALL_FONT: int = 14
const HEADING_FONT: int = 19
## 1080p / the 720p base height.
const SCALE_TO_1080P: float = 1.5

const PART_ROW: StringName = &"PartRow"
const ARMED_ROW: StringName = &"ArmedRow"
const STAT_ROW: StringName = &"StatRow"
const STAT_ROW_BETTER: StringName = &"StatRowBetter"
const STAT_ROW_WORSE: StringName = &"StatRowWorse"
const EXIT_BUTTON: StringName = &"ExitButton"
const MUTED_LABEL: StringName = &"MutedLabel"
const HEADING_LABEL: StringName = &"HeadingLabel"
const SCRAP_LABEL: StringName = &"ScrapLabel"
const SCRAP_SMALL_LABEL: StringName = &"ScrapSmallLabel"
const ACCENT_LABEL: StringName = &"AccentLabel"
const WORSE_LABEL: StringName = &"WorseLabel"


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = FONT
	_labels(theme)
	_panels(theme)
	_buttons(theme)
	return theme


## The smallest font size the theme uses, in pixels at 1080p.
static func smallest_text_px_1080p() -> float:
	return float(mini(mini(FONT, SMALL_FONT), HEADING_FONT)) * SCALE_TO_1080P


## Rec. 709 luma of the sRGB values (0 to 1), the same measure tools/pixels.ps1 prints.
static func luma(color: Color) -> float:
	return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b


## How far apart the better and worse marks are in luma (GDD 12: at least 0.25).
static func mark_luma_gap() -> float:
	return absf(luma(BETTER) - luma(WORSE))


static func _box(
	fill: Color, edge: Color, edge_width: int, margin_h: int = 8, margin_v: int = 4
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(edge_width)
	box.set_corner_radius_all(4)
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	return box


static func _labels(theme: Theme) -> void:
	theme.set_font_size("font_size", "Label", FONT)
	theme.set_color("font_color", "Label", BODY)
	_label_variation(theme, MUTED_LABEL, SMALL_FONT, MUTED)
	_label_variation(theme, HEADING_LABEL, HEADING_FONT, BODY)
	_label_variation(theme, SCRAP_LABEL, HEADING_FONT, SALVAGE)
	_label_variation(theme, SCRAP_SMALL_LABEL, SMALL_FONT, SALVAGE)
	_label_variation(theme, ACCENT_LABEL, FONT, ACCENT)
	_label_variation(theme, WORSE_LABEL, FONT, WORSE)


static func _label_variation(theme: Theme, variation: StringName, size: int, color: Color) -> void:
	theme.set_type_variation(variation, "Label")
	theme.set_font_size("font_size", variation, size)
	theme.set_color("font_color", variation, color)


static func _panels(theme: Theme) -> void:
	theme.set_stylebox("panel", "PanelContainer", _box(PANEL_BG, PANEL_EDGE, 1, 8, 8))
	theme.set_type_variation(PART_ROW, "PanelContainer")
	theme.set_stylebox("panel", PART_ROW, _box(Color(1.0, 1.0, 1.0, 0.04), PANEL_EDGE, 1, 8, 6))
	theme.set_type_variation(ARMED_ROW, "PanelContainer")
	theme.set_stylebox("panel", ARMED_ROW, _box(Color(1.0, 0.541, 0.239, 0.16), ACCENT, 2, 8, 6))
	# Stat rows: plain, or tinted with a bar on the left while the row shows a change: accent for better, grey for worse.
	theme.set_type_variation(STAT_ROW, "PanelContainer")
	var clear := Color(0.0, 0.0, 0.0, 0.0)
	theme.set_stylebox("panel", STAT_ROW, _box(clear, clear, 0, 3, 2))
	theme.set_type_variation(STAT_ROW_BETTER, "PanelContainer")
	var better := _box(Color(1.0, 0.541, 0.239, 0.18), BETTER, 0, 3, 2)
	better.border_width_left = 3
	theme.set_stylebox("panel", STAT_ROW_BETTER, better)
	theme.set_type_variation(STAT_ROW_WORSE, "PanelContainer")
	var worse := _box(Color(1.0, 1.0, 1.0, 0.09), WORSE, 0, 3, 2)
	worse.border_width_left = 3
	theme.set_stylebox("panel", STAT_ROW_WORSE, worse)


static func _buttons(theme: Theme) -> void:
	theme.set_font_size("font_size", "Button", FONT)
	theme.set_stylebox("normal", "Button", _box(BUTTON_BG, PANEL_EDGE, 1))
	theme.set_stylebox("hover", "Button", _box(BUTTON_HOVER, BODY, 1))
	theme.set_stylebox("pressed", "Button", _box(INK, ACCENT, 2))
	theme.set_stylebox("hover_pressed", "Button", _box(INK, ACCENT, 2))
	theme.set_stylebox("disabled", "Button", _box(BUTTON_DISABLED_BG, PANEL_EDGE, 1))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", BODY)
	theme.set_color("font_hover_color", "Button", BODY)
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_hover_pressed_color", "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", DISABLED_TEXT)
	# The exit button: accent fill with ink text when it can be used.
	theme.set_type_variation(EXIT_BUTTON, "Button")
	theme.set_font_size("font_size", EXIT_BUTTON, HEADING_FONT)
	theme.set_stylebox("normal", EXIT_BUTTON, _box(ACCENT, INK, 2, 8, 8))
	theme.set_stylebox("hover", EXIT_BUTTON, _box(Color("FFA466"), INK, 2, 8, 8))
	theme.set_stylebox("pressed", EXIT_BUTTON, _box(Color("D96F2B"), INK, 2, 8, 8))
	theme.set_stylebox("disabled", EXIT_BUTTON, _box(BUTTON_DISABLED_BG, PANEL_EDGE, 1, 8, 8))
	theme.set_color("font_color", EXIT_BUTTON, INK)
	theme.set_color("font_hover_color", EXIT_BUTTON, INK)
	theme.set_color("font_pressed_color", EXIT_BUTTON, INK)
	theme.set_color("font_disabled_color", EXIT_BUTTON, DISABLED_TEXT)
