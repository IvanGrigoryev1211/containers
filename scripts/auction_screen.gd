extends CanvasLayer

## S03 view only: GameState owns validation, settlement and one-purchase guard.
const LOT_A = preload("res://data/lots/lot_a.tres")
var game_state: Node
var balance_label: Label
var bid: SpinBox
var bid_summary: Label
var hypothesis: TextEdit
var confirm_button: Button
var result_label: Label


func _ready() -> void:
	layer = 20
	game_state = get_node("/root/GameState")
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.025, 0.035, 0.05, 0.98)
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
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)
	_label(content, "АУКЦИОН — " + LOT_A.display_name, 26)
	_label(content, "Старт: %d жетонов · Максимальный предел: %d · Ценовой пол базовых находок: %d" % [LOT_A.start_price, LOT_A.bid_limit, LOT_A.guaranteed_price_floor])
	_label(content, "Фиксированные соперники: предел от %d гарантирует победу за %d жетонов. Ниже — проигрыш без списания; можно повторить." % [LOT_A.typical_winning_price, LOT_A.typical_winning_price])
	for evidence in LOT_A.visible_evidence:
		_label(content, evidence.title + "\n" + evidence.description + "\nРиск: " + evidence.risk_note)
	_label(content, "Ваша гипотеза (свободный текст, можно оставить пустой):")
	hypothesis = TextEdit.new()
	hypothesis.custom_minimum_size.y = 64
	hypothesis.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	content.add_child(hypothesis)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	content.add_child(row)
	balance_label = _label(row, "")
	_label(row, "Предел ставки:")
	bid = SpinBox.new()
	bid.min_value = LOT_A.start_price
	bid.max_value = LOT_A.bid_limit
	bid.step = 1
	bid.value = LOT_A.start_price
	bid.custom_minimum_size.x = 150
	row.add_child(bid)
	bid_summary = _label(row, "")
	bid_summary.hide()
	bid.value_changed.connect(func(_value): refresh())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	content.add_child(buttons)
	confirm_button = Button.new()
	confirm_button.text = "Подтвердить ставку"
	confirm_button.pressed.connect(_confirm)
	buttons.add_child(confirm_button)
	var cancel := Button.new()
	cancel.text = "Закрыть (Esc)"
	cancel.pressed.connect(close)
	buttons.add_child(cancel)
	result_label = _label(content, "")
	game_state.state_changed.connect(refresh)
	hide()
	refresh()


func _label(parent: Node, text: String, size := 17) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label


func open() -> void:
	show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	result_label.text = ""
	refresh()
	if not game_state.lot_a_won:
		hypothesis.grab_focus()


func close() -> void:
	hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func refresh() -> void:
	if balance_label == null:
		return
	balance_label.text = "Баланс: %d жетонов" % game_state.tokens
	# Below the start there is no valid range: keep the start visible, disable bidding.
	if game_state.lot_a_won:
		hypothesis.text = game_state.lot_a_hypothesis
	else:
		bid.max_value = maxi(LOT_A.start_price, mini(LOT_A.bid_limit, game_state.tokens))
	bid.visible = not game_state.lot_a_won
	bid_summary.visible = game_state.lot_a_won
	bid_summary.text = str(game_state.lot_a_bid_limit)
	bid.editable = not game_state.lot_a_won and game_state.tokens >= LOT_A.start_price
	hypothesis.editable = not game_state.lot_a_won
	confirm_button.disabled = game_state.lot_a_won or game_state.tokens < LOT_A.start_price
	if game_state.lot_a_won:
		result_label.text = "Лот A выигран за %d жетонов. Закройте аукцион и идите к столу вскрытия: наведитесь на него и нажмите E. Повторная ставка недоступна." % game_state.lot_a_paid
	elif game_state.tokens < LOT_A.start_price:
		result_label.text = "Недостаточно жетонов даже для стартовой ставки."


func _confirm() -> void:
	# Read pending typed text too, so an uncommitted SpinBox edit cannot bypass validation.
	var text := bid.get_line_edit().text.strip_edges()
	if not text.is_valid_int():
		result_label.text = "Введите целый предел ставки в допустимом диапазоне."
		return
	var outcome: String = game_state.submit_lot_a_bid(text.to_int(), hypothesis.text)
	refresh()
	if outcome == "lost":
		result_label.text = "Соперники перебили предел. Деньги не списаны. Можно изменить предел и повторить."
	elif outcome == "invalid":
		result_label.text = "Ставка отклонена: предел должен быть от %d до %d и не выше баланса." % [LOT_A.start_price, LOT_A.bid_limit]
