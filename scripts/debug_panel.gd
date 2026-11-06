extends CanvasLayer

## Development-only overlay for the second technical session.
const LOT_A_PATH := "res://data/lots/lot_a.tres"

var balance_label: Label
var stage_label: Label
var lot_label: Label
var event_log_label: Label
var lot_a: LotDefinition
var game_state: Variant


func _ready() -> void:
	layer = 10
	game_state = get_node("/root/GameState")
	lot_a = load(LOT_A_PATH) as LotDefinition
	_build_panel()
	game_state.state_changed.connect(refresh)
	refresh()


func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-415.0, 20.0)
	panel.size = Vector2(395.0, 300.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.055, 0.07, 0.9)
	style.border_color = Color("7da7bf")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	panel.add_child(content)

	var title := Label.new()
	title.text = "ОТЛАДКА — ВЕРТИКАЛЬНЫЙ СРЕЗ"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("9ec9df"))
	content.add_child(title)

	balance_label = _add_label(content, 20, Color("ffe09a"))
	stage_label = _add_label(content, 14, Color("d6dde5"))
	lot_label = _add_label(content, 14, Color("b7d9be"))

	var events_title := _add_label(content, 14, Color("9ec9df"))
	events_title.text = "Журнал (последние 5):"
	event_log_label = _add_label(content, 13, Color("d6dde5"))
	event_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _add_label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func refresh() -> void:
	balance_label.text = "Баланс: %d жетонов" % game_state.tokens
	stage_label.text = "Этап: %s" % game_state.current_stage
	if lot_a != null:
		lot_label.text = "Lot A: %s | старт: %d | улик: %d" % [lot_a.display_name, lot_a.start_price, lot_a.visible_evidence.size()]
	else:
		lot_label.text = "Lot A: ошибка загрузки данных"
	event_log_label.text = "\n".join(PackedStringArray(game_state.get_recent_events(5)))
