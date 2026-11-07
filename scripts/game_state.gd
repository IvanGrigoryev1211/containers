extends Node

## Runtime-only state for the vertical slice. No save system is involved yet.
signal state_changed

const STARTING_TOKENS := 750
const LOT_A = preload("res://data/lots/lot_a.tres")
enum OpeningState { LOCKED, SEALED, UNSEALED, SORTING, COMPLETE }
const OPENING_ZONES := ["быстрая продажа", "рабочий стол", "хранение"]

var tokens: int = STARTING_TOKENS
var current_stage := "Мастерская — аукцион лота A"
var event_log: Array[String] = []
var lot_a_won := false
var lot_a_hypothesis := ""
var lot_a_bid_limit := 0
var lot_a_paid := 0
var _auction_resolving := false
var opening_state := OpeningState.LOCKED
var item_zones: Dictionary = {}
var _opening_resolving := false


func _ready() -> void:
	reset_for_debug()


func can_afford(amount: int) -> bool:
	return amount >= 0 and tokens >= amount


func spend(amount: int, reason := "Операция") -> bool:
	if amount <= 0:
		_record_event("Списание отклонено (%s): сумма должна быть положительной." % reason)
		return false
	if not can_afford(amount):
		_record_event("Списание отклонено (%s): %d жетонов при балансе %d." % [reason, amount, tokens])
		return false

	tokens -= amount
	_record_event("Списано %d жетонов (%s). Баланс: %d." % [amount, reason, tokens])
	return true


func earn(amount: int, reason := "Операция") -> bool:
	if amount <= 0:
		_record_event("Начисление отклонено (%s): сумма должна быть положительной." % reason)
		return false

	tokens += amount
	_record_event("Начислено %d жетонов (%s). Баланс: %d." % [amount, reason, tokens])
	return true


func reset_for_debug() -> void:
	if _auction_resolving or _opening_resolving:
		return
	tokens = STARTING_TOKENS
	lot_a_won = false
	lot_a_hypothesis = ""
	lot_a_bid_limit = 0
	lot_a_paid = 0
	_auction_resolving = false
	opening_state = OpeningState.LOCKED
	item_zones.clear()
	current_stage = "Мастерская — аукцион лота A"
	event_log.clear()
	_record_event("DEBUG: состояние сброшено. Баланс: %d." % tokens)


func submit_lot_a_bid(limit: int, hypothesis: String) -> String:
	# Fixed S03 rival script: rivals stop immediately below typical_winning_price.
	# A sufficient limit wins at that price, never at the player's whole limit.
	# The guard is set before spend() emits state_changed (including reentrant calls).
	if lot_a_won or _auction_resolving:
		return "already_won"
	if limit < LOT_A.start_price or limit > LOT_A.bid_limit or not can_afford(limit):
		return "invalid"
	_auction_resolving = true
	var note := hypothesis.strip_edges()
	if note.is_empty():
		note = "не записана"
	_record_event("Аукцион %s: предел %d; гипотеза: %s" % [LOT_A.display_name, limit, note])
	if limit < LOT_A.typical_winning_price:
		_record_event("Фиксированные соперники: нужен предел %d. Предел %d ниже; проигрыш без списания, можно повторить." % [LOT_A.typical_winning_price, limit])
		_auction_resolving = false
		return "lost"
	if not spend(LOT_A.typical_winning_price, "Аукцион: " + LOT_A.display_name):
		_auction_resolving = false
		return "invalid"
	lot_a_won = true
	lot_a_hypothesis = hypothesis
	lot_a_bid_limit = limit
	lot_a_paid = LOT_A.typical_winning_price
	opening_state = OpeningState.SEALED
	current_stage = "лот A выигран; идите к столу вскрытия"
	_record_event("Фиксированные соперники: предел не ниже %d гарантирует победу за %d. Лот A выигран; идите к столу вскрытия." % [LOT_A.typical_winning_price, lot_a_paid])
	_auction_resolving = false
	return "won"


func cut_seal() -> bool:
	if _opening_resolving or _auction_resolving or not lot_a_won or opening_state != OpeningState.SEALED:
		return false
	_opening_resolving = true
	opening_state = OpeningState.UNSEALED
	current_stage = "лот A: пломба срезана; откройте крышку"
	_record_event("Вскрытие: пломба срезана (UNSEALED).")
	_opening_resolving = false
	return true


func open_lid() -> bool:
	if _opening_resolving or _auction_resolving or not lot_a_won or opening_state != OpeningState.UNSEALED or not _opening_items_valid():
		return false
	_opening_resolving = true
	opening_state = OpeningState.SORTING
	current_stage = "лот A: распределите четыре предмета"
	_record_event("Вскрытие: крышка открыта (SORTING); предметов: %d." % LOT_A.future_items.size())
	_opening_resolving = false
	return true


func _opening_items_valid() -> bool:
	var ids: Array[String] = []
	if LOT_A.future_items.size() != 4:
		return false
	for item in LOT_A.future_items:
		if item == null or item.id.is_empty() or item.id in ids:
			return false
		ids.append(item.id)
	return true


func get_opening_items() -> Array[ItemDefinition]:
	# Do not expose contents to the view until the lid is open.
	if opening_state not in [OpeningState.SORTING, OpeningState.COMPLETE]:
		return []
	return LOT_A.future_items


func assign_item(id: String, zone: String) -> bool:
	if _opening_resolving or _auction_resolving or not lot_a_won or opening_state != OpeningState.SORTING:
		return false
	if zone not in OPENING_ZONES or item_zones.has(id) or not _opening_items_valid():
		return false
	# Reveal/assign in resource order. A stale click is bound to its original ID.
	var next_item: ItemDefinition
	for item in LOT_A.future_items:
		if not item_zones.has(item.id):
			next_item = item
			break
	if next_item == null or next_item.id != id:
		return false
	_opening_resolving = true
	item_zones[id] = zone
	if item_zones.size() == LOT_A.future_items.size():
		opening_state = OpeningState.COMPLETE
		current_stage = "лот A: вскрытие и распределение завершены"
	_record_event("Распределение: %s → %s (%d/%d). Только назначение зоны, без продажи." % [next_item.display_name, zone, item_zones.size(), LOT_A.future_items.size()])
	_opening_resolving = false
	return true


func get_recent_events(limit := 5) -> Array[String]:
	var first_index: int = max(0, event_log.size() - max(0, limit))
	return event_log.slice(first_index)


func _record_event(entry: String) -> void:
	event_log.append(entry)
	state_changed.emit()
