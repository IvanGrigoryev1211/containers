extends CanvasLayer

## S05 view: a four-row projection of Lot A, with settlement owned by GameState.
var game_state: Node
var status_label: Label
var balance_label: Label
var items_box: VBoxContainer
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
	_label(content, "ТЕРМИНАЛ ПРОДАЖИ — " + game_state.LOT_A.display_name, 26)
	status_label = _label(content, "")
	balance_label = _label(content, "")
	items_box = VBoxContainer.new()
	items_box.add_theme_constant_override("separation", 12)
	content.add_child(items_box)
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


func close() -> void:
	hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func refresh() -> void:
	if status_label == null:
		return
	balance_label.text = "Баланс: %d жетонов" % game_state.tokens
	var inventory: Array[Dictionary] = game_state.get_lot_a_inventory()
	if inventory.is_empty():
		status_label.text = "LOCKED — сначала завершите вскрытие и распределите все четыре предмета. До COMPLETE список скрыт, продажа недоступна."
		_clear_rows()
		return
	status_label.text = "Список Lot A в порядке ресурса. Зона показана для справки и не влияет на доступность продажи. V-12 и этикетка ждут будущих сессий."
	if rows.is_empty():
		for entry in inventory:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 16)
			items_box.add_child(row)
			var label := _label(row, "")
			var button: Button
			if entry.id in game_state.QUICK_SALE_ITEM_IDS:
				button = _button(row, "", _sell.bind(entry.id))
				button.custom_minimum_size.x = 190
			rows[entry.id] = {"label": label, "button": button}
	for entry in inventory:
		var status := "Продано" if entry.sold else "Доступна быстрая продажа" if entry.id in game_state.QUICK_SALE_ITEM_IDS else "Не продаётся в S05"
		rows[entry.id].label.text = "%s · Состояние: %s · Зона: %s · Статус: %s" % [entry.display_name, entry.initial_condition, entry.zone, status]
		var button: Button = rows[entry.id].button
		if button != null:
			button.text = "Продано за %d" % entry.quick_sale_value if entry.sold else "Продать за %d" % entry.quick_sale_value
			button.disabled = entry.sold


func _clear_rows() -> void:
	for child in items_box.get_children():
		items_box.remove_child(child)
		child.queue_free()
	rows.clear()


func _sell(id: String) -> void:
	game_state.quick_sell_item(id)
