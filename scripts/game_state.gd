extends Node

## Runtime-only state for the vertical slice. No save system is involved yet.
signal state_changed

const STARTING_TOKENS := 750

var tokens: int = STARTING_TOKENS
var current_stage := "Мастерская — техническая сессия 2"
var event_log: Array[String] = []


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
	tokens = STARTING_TOKENS
	event_log.clear()
	_record_event("DEBUG: состояние сброшено. Баланс: %d." % tokens)


func get_recent_events(limit := 5) -> Array[String]:
	var first_index: int = max(0, event_log.size() - max(0, limit))
	return event_log.slice(first_index)


func _record_event(entry: String) -> void:
	event_log.append(entry)
	state_changed.emit()
