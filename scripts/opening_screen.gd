extends CanvasLayer

## S04 view: data and progress come only from GameState, no money operations.
const State = preload("res://scripts/game_state.gd").OpeningState
var game_state: Node
var status_label: Label
var balance_label: Label
var cut_button: Button
var lid_button: Button
var items_box: VBoxContainer
var summary_label: Label
var rows: Dictionary = {}


func _ready() -> void:
	layer = 20
	game_state = get_node("/root/GameState")
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.025, 0.035, 0.05, 1)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	backdrop.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	_label(content, "ВСКРЫТИЕ — " + game_state.LOT_A.display_name, 26)
	status_label = _label(content, "")
	balance_label = _label(content, "")
	cut_button = _button(content, "Срезать пломбу", func(): game_state.cut_seal())
	lid_button = _button(content, "Открыть крышку", func(): game_state.open_lid())
	items_box = VBoxContainer.new()
	items_box.add_theme_constant_override("separation", 12)
	content.add_child(items_box)
	summary_label = _label(content, "")
	_button(content, "Закрыть (Esc)", close)
	game_state.state_changed.connect(refresh)
	hide()
	refresh()


func _label(parent: Node, text: String, size := 18) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func open() -> void:
	show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	refresh()
	if cut_button.visible:
		cut_button.grab_focus()
	elif lid_button.visible:
		lid_button.grab_focus()


func close() -> void:
	hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func refresh() -> void:
	var state: int = game_state.opening_state
	balance_label.text = "Баланс: %d жетонов. Назначение зон не меняет деньги." % game_state.tokens
	cut_button.visible = state == State.SEALED
	lid_button.visible = state == State.UNSEALED
	items_box.visible = state in [State.SORTING, State.COMPLETE]
	summary_label.text = ""
	match state:
		State.LOCKED:
			status_label.text = "LOCKED — сначала выиграйте лот A на аукционе. Вскрытие недоступно; содержимое скрыто."
		State.SEALED:
			status_label.text = "SEALED — лот выигран. Сначала срежьте пломбу. Содержимое скрыто."
		State.UNSEALED:
			status_label.text = "UNSEALED — пломба срезана. Теперь откройте крышку. Содержимое скрыто."
		State.SORTING:
			status_label.text = "SORTING — назначьте каждому предмету одну зону по порядку. Все зоны допустимы. «Быстрая продажа» здесь только зона: деньги не начисляются."
		State.COMPLETE:
			status_label.text = "COMPLETE — все четыре предмета распределены. Итог сохранён до F4 или перезапуска. Продажа и обработка пока не реализованы."
	if not items_box.visible:
		for child in items_box.get_children():
			items_box.remove_child(child)
			child.queue_free()
		rows.clear()
		return
	var items: Array[ItemDefinition] = game_state.get_opening_items()
	if rows.is_empty():
		for item in items:
			var group := VBoxContainer.new()
			items_box.add_child(group)
			var label := _label(group, _item_description(item))
			var zones := HBoxContainer.new()
			zones.add_theme_constant_override("separation", 16)
			group.add_child(zones)
			var buttons: Array[Button] = []
			for zone in game_state.OPENING_ZONES:
				var button := _button(zones, zone, _assign.bind(item.id, zone))
				button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				button.modulate = Color("a7d9ff")
				buttons.append(button)
			rows[item.id] = {"label": label, "buttons": buttons}
	var next_found := false
	var summary := PackedStringArray()
	for item in items:
		var assigned: bool = game_state.item_zones.has(item.id)
		var active: bool = not assigned and not next_found
		if not assigned:
			next_found = true
		rows[item.id].label.text = _item_description(item) + (" → " + str(game_state.item_zones[item.id]) if assigned else " — выберите зону" if active else " — ожидает очереди")
		for button in rows[item.id].buttons:
			button.disabled = not active
		if assigned:
			summary.append(_item_description(item) + " → " + str(game_state.item_zones[item.id]))
	if state == State.COMPLETE:
		summary_label.text = "Итоговое распределение:\n" + "\n".join(summary)


func _assign(id: String, zone: String) -> void:
	game_state.assign_item(id, zone)


func _item_description(item: ItemDefinition) -> String:
	return "%s · Состояние: %s" % [item.display_name, item.initial_condition]
