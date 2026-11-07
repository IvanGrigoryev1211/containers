extends SceneTree

const State = preload("res://scripts/game_state.gd").OpeningState
const WRENCH := "rusted_wrench_set"
const RAGS := "oily_rags_and_fasteners"
const V12 := "calibrator_v12"
const LABEL := "calibration_lab_label"

var failures := 0
var scene: Node
var state: Node
var ui: CanvasLayer


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, description: String) -> void:
	print(("PASS " if ok else "FAIL ") + description)
	if not ok:
		failures += 1


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	scene._input(event)


func aim(station: Node3D, point: Vector3) -> void:
	scene.player.position = station.position + Vector3(0, 1.7, 2.2)
	scene.player.rotation = Vector3.ZERO
	scene.camera_pivot.rotation = Vector3.ZERO
	scene.camera.rotation = Vector3.ZERO
	scene.camera.look_at(station.position + point)
	await physics_frame
	await physics_frame


func close_modal() -> void:
	if scene._active_modal() != null:
		key(KEY_ESCAPE)


func reset_state() -> void:
	close_modal()
	state.reset_for_debug()
	ui.refresh()


func prepare_phase(phase: int, wrench_zone := "хранение", rags_zone := "хранение") -> void:
	reset_state()
	if phase >= State.SEALED:
		state.submit_lot_a_bid(580, "S05 test")
	if phase >= State.UNSEALED:
		state.cut_seal()
	if phase >= State.SORTING:
		state.open_lid()
	if phase == State.COMPLETE:
		for item in state.LOT_A.future_items:
			var zone := "хранение"
			if item.id == WRENCH:
				zone = wrench_zone
			elif item.id == RAGS:
				zone = rags_zone
			state.assign_item(item.id, zone)
	ui.refresh()


func item_by_id(id: String) -> ItemDefinition:
	for item in state.LOT_A.future_items:
		if item.id == id:
			return item
	return null


func sale_log_count() -> int:
	var count := 0
	for entry in state.event_log:
		if entry.begins_with("Начислено") and "Быстрая продажа:" in entry:
			count += 1
	return count


func run_sale_order(first_id: String, second_id: String, first_balance: int) -> void:
	prepare_phase(State.COMPLETE, "рабочий стол", "быстрая продажа")
	ui.open()
	var stale: Button = ui.rows[first_id].button
	var nested_results: Array[bool] = []
	var reenter := func():
		nested_results.append(state.quick_sell_item(first_id))
		nested_results.append(state.quick_sell_item(second_id))
		state.reset_for_debug()
	state.state_changed.connect(reenter)
	stale.pressed.emit()
	state.state_changed.disconnect(reenter)
	check(nested_results == [false, false], "reentrant same/other sale blocked for " + first_id)
	check(state.tokens == first_balance and state.sold_item_ids.has(first_id) and not state.sold_item_ids.has(second_id), "first sale balance/status " + first_id)
	check(sale_log_count() == 1 and state.opening_state == State.COMPLETE, "first sale exactly one earn and F4 reentry blocked")
	stale.pressed.emit()
	check(state.tokens == first_balance and sale_log_count() == 1, "stale/double click does not pay again " + first_id)
	ui.close()
	ui.open()
	check(ui.rows[first_id].button.disabled and not ui.rows[second_id].button.disabled, "reopen preserves sale state")
	ui.rows[second_id].button.pressed.emit()
	check(state.tokens == 235 and state.sold_item_ids.size() == 2 and sale_log_count() == 2, "second sale reaches 235 exactly once")
	check(state.current_stage == "Базовые находки проданы; V-12 ждёт S06", "final S05 stage")
	var logs := "\n".join(state.event_log)
	for id in [first_id, second_id]:
		var item := item_by_id(id)
		check(item.display_name in logs and str(item.quick_sale_value) in logs, "journal has name and amount " + id)
	check("Баланс: 235" in logs, "journal has final balance")
	ui.rows[second_id].button.pressed.emit()
	ui.close()
	ui.open()
	check(state.tokens == 235 and sale_log_count() == 2 and ui.rows[first_id].button.disabled and ui.rows[second_id].button.disabled, "repeat/reopen after both sales stable")
	ui.close()


func run() -> void:
	scene = load("res://Workshop.tscn").instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame
	state = root.get_node("GameState")
	ui = scene.sale_screen
	var items: Array[ItemDefinition] = state.LOT_A.future_items
	var terminal = scene.get_node("Терминал_продажи")
	check(items.size() == 4 and state.QUICK_SALE_ITEM_IDS == [WRENCH, RAGS], "four items and exact two-ID allowlist")
	# LOCKED through SORTING: the real terminal opens, but inventory remains hidden.
	for phase in [State.LOCKED, State.SEALED, State.UNSEALED, State.SORTING]:
		prepare_phase(phase)
		await aim(terminal, Vector3(0, 1.05, 0))
		key(KEY_E)
		check(ui.visible and ui.rows.is_empty() and state.get_lot_a_inventory().is_empty(), "phase %d hides list" % phase)
		check("сначала завершите вскрытие" in ui.status_label.text and not state.quick_sell_item(WRENCH), "phase %d blocks sale with message" % phase)
		key(KEY_ESCAPE)
	# Complete projection: exactly four rows, resource order and all requested data.
	prepare_phase(State.COMPLETE, "рабочий стол", "быстрая продажа")
	await aim(terminal, Vector3(0, 1.05, 0))
	key(KEY_E)
	var inventory: Array[Dictionary] = state.get_lot_a_inventory()
	check(ui.visible and inventory.size() == 4 and ui.rows.size() == 4, "COMPLETE exposes exactly four rows")
	var row_ids = ui.rows.keys()
	var button_count := 0
	for i in items.size():
		var item := items[i]
		var entry: Dictionary = inventory[i]
		var text: String = ui.rows[item.id].label.text
		check(row_ids[i] == item.id and entry.id == item.id, "resource order row " + str(i))
		check(item.display_name in text and item.initial_condition in text and state.item_zones[item.id] in text and "Статус:" in text, "row data name/condition/zone/status " + item.id)
		if ui.rows[item.id].button != null:
			button_count += 1
	check(button_count == 2 and ui.rows[WRENCH].button != null and ui.rows[RAGS].button != null and ui.rows[V12].button == null and ui.rows[LABEL].button == null, "buttons only for exact allowlist")
	var before_log: int = state.event_log.size()
	check(not state.quick_sell_item(V12) and not state.quick_sell_item(LABEL) and not state.quick_sell_item("unknown"), "V-12, label and unknown ID rejected")
	check(item_by_id(V12).quick_sale_value == 310 and state.tokens == 170 and state.event_log.size() == before_log, "V-12 310 cannot be sold")
	# Modal behavior for the third screen.
	var position: Vector3 = scene.player.position
	var rotation: Vector3 = scene.player.rotation
	for code in [KEY_F2, KEY_F3, KEY_F4, KEY_E]:
		key(code)
	Input.action_press("move_forward")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, 100)
	scene._input(motion)
	await physics_frame
	await physics_frame
	Input.action_release("move_forward")
	check(state.tokens == 170 and state.opening_state == State.COMPLETE and state.sold_item_ids.is_empty(), "modal blocks E/F2/F3/F4")
	check(scene.player.position.is_equal_approx(position) and scene.player.rotation == rotation, "modal blocks movement and mouse look")
	ui.close()
	# Both sale orders, including nested and stale calls.
	run_sale_order(WRENCH, RAGS, 210)
	run_sale_order(RAGS, WRENCH, 195)
	# Prove prices are read from ItemDefinition at settlement and UI time.
	prepare_phase(State.COMPLETE)
	var wrench := item_by_id(WRENCH)
	var rags := item_by_id(RAGS)
	var wrench_price: int = wrench.quick_sale_value
	var rags_price: int = rags.quick_sale_value
	wrench.quick_sale_value = 47
	rags.quick_sale_value = 29
	ui.open()
	ui.refresh()
	check("47" in ui.rows[WRENCH].button.text and "29" in ui.rows[RAGS].button.text, "mutated resource prices appear in UI")
	ui.rows[WRENCH].button.pressed.emit()
	ui.rows[RAGS].button.pressed.emit()
	check(state.tokens == 246, "mutated data-driven prices pay 47+29")
	wrench.quick_sale_value = wrench_price
	rags.quick_sale_value = rags_price
	ui.close()
	# Zone assignments never gate either allowed sale: all 3x3 combinations.
	for wrench_zone in state.OPENING_ZONES:
		for rags_zone in state.OPENING_ZONES:
			prepare_phase(State.COMPLETE, wrench_zone, rags_zone)
			var projected: Array[Dictionary] = state.get_lot_a_inventory()
			check(projected[0].zone == wrench_zone and projected[1].zone == rags_zone, "projected zones %s / %s" % [wrench_zone, rags_zone])
			check(state.quick_sell_item(WRENCH) and state.quick_sell_item(RAGS) and state.tokens == 235, "both sales independent of zones")
	# F4 after zero, one and two sales, followed by a fresh cycle.
	for sold_count in [0, 1, 2]:
		prepare_phase(State.COMPLETE)
		if sold_count >= 1:
			state.quick_sell_item(WRENCH)
		if sold_count >= 2:
			state.quick_sell_item(RAGS)
		state.reset_for_debug()
		check(state.tokens == 750 and state.opening_state == State.LOCKED and state.sold_item_ids.is_empty() and state.item_zones.is_empty() and not state.lot_a_won and state.event_log.size() == 1, "F4 reset after %d sales" % sold_count)
		prepare_phase(State.COMPLETE)
		check(state.quick_sell_item(WRENCH) and state.quick_sell_item(RAGS) and state.tokens == 235, "fresh cycle after F4 count " + str(sold_count))
	# Shared modality: exactly one of three screens visible.
	reset_state()
	scene._show_modal(scene.auction_screen)
	scene._show_modal(scene.opening_screen)
	scene._show_modal(ui)
	check(ui.visible and not scene.auction_screen.visible and not scene.opening_screen.visible and scene._active_modal() == ui, "shared modality: only SaleScreen visible")
	key(KEY_ESCAPE)
	# Raycast regression: 15 points, with SaleScreen at the sales terminal.
	reset_state()
	var stations := 0
	for station in scene.get_children():
		if not station.has_meta("station_name"):
			continue
		stations += 1
		var title: String = station.get_meta("station_name")
		var top := Vector3(0, 1.52, -0.1)
		if title == "Стол вскрытия": top = Vector3(0.58, 1.30, 0)
		if title == "Рабочий стол": top = Vector3(-0.5, 1.50, 0)
		if title == "Стойка улучшения": top = Vector3(0, 1.80, 0)
		for point in [Vector3(0, 0.5, 0), Vector3(0, 1.05, 0), top]:
			await aim(station, point)
			scene._update_interaction_target()
			check(scene.target_station == station and scene.prompt_label.text == title + "\nE — взаимодействовать", "ray target/prompt " + title + str(point))
			var query := PhysicsRayQueryParameters3D.create(scene.camera.global_position, scene.camera.global_position - scene.camera.global_basis.z * 4)
			query.exclude = [scene.player.get_rid()]
			check(scene.get_world_3d().direct_space_state.intersect_ray(query).get("collider") == station, "ray collider station, not Player")
			key(KEY_E)
			if title == "Терминал аукциона":
				check(scene.auction_screen.visible, "ray E auction")
				key(KEY_ESCAPE)
			elif title == "Стол вскрытия":
				check(scene.opening_screen.visible, "ray E opening")
				key(KEY_ESCAPE)
			elif title == "Терминал продажи":
				check(ui.visible, "ray E sale")
				key(KEY_ESCAPE)
			else:
				check(scene.debug_label.text == "DEBUG: взаимодействие — " + title, "ray E other station")
	check(stations == 5, "15 points across five stations")
	print("S05_FAILURES=", failures)
	quit(0 if failures == 0 else 1)
