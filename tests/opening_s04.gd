extends SceneTree

const State = preload("res://scripts/game_state.gd").OpeningState
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


func prepare(target: int) -> void:
	if scene._active_modal() != null:
		key(KEY_ESCAPE)
	key(KEY_F4)
	if target >= State.SEALED:
		state.submit_lot_a_bid(580, "S04 test")
	if target >= State.UNSEALED:
		state.cut_seal()
	if target >= State.SORTING:
		state.open_lid()
	if target == State.COMPLETE:
		for item in state.LOT_A.future_items:
			state.assign_item(item.id, state.OPENING_ZONES[0])


func reopen(expected: int) -> void:
	var before: Dictionary = state.item_zones.duplicate()
	var log_size: int = state.event_log.size()
	key(KEY_ESCAPE)
	check(scene._active_modal() == null, "Esc closes stage " + str(expected))
	key(KEY_E)
	check(ui.visible and state.opening_state == expected and state.item_zones == before and state.event_log.size() == log_size, "E resumes stage " + str(expected))


func run() -> void:
	scene = load("res://Workshop.tscn").instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame
	state = root.get_node("GameState")
	ui = scene.opening_screen
	var items = state.LOT_A.future_items
	var table = scene.get_node("Стол_вскрытия")
	check(items.size() == 4, "four resource items")
	check(state.opening_state == State.LOCKED and state.item_zones.is_empty(), "initial LOCKED")
	await aim(table, Vector3(0, 0.5, 0))
	key(KEY_E)
	check(ui.visible and "сначала выиграйте" in ui.status_label.text and ui.rows.is_empty() and state.get_opening_items().is_empty(), "table before purchase: message and no contents")
	check(not state.cut_seal() and not state.open_lid() and not state.assign_item(items[0].id, state.OPENING_ZONES[0]), "all actions rejected while locked")
	await reopen(State.LOCKED)
	key(KEY_ESCAPE)
	state.submit_lot_a_bid(579, "loss")
	key(KEY_E)
	check(state.opening_state == State.LOCKED and ui.rows.is_empty() and state.tokens == 750, "loss keeps table locked and contents hidden")
	prepare(State.SEALED)
	key(KEY_E)
	check(ui.visible and ui.cut_button.visible and not ui.lid_button.visible and ui.rows.is_empty(), "SEALED UI has only cut seal")
	check(not state.open_lid() and not state.assign_item(items[0].id, state.OPENING_ZONES[0]), "cannot skip seal")
	await reopen(State.SEALED)
	var nested := func():
		check(not state.cut_seal() and not state.open_lid() and not state.assign_item(items[0].id, state.OPENING_ZONES[0]), "all nested opening actions blocked")
	state.state_changed.connect(nested)
	ui.cut_button.pressed.emit()
	state.state_changed.disconnect(nested)
	check(state.opening_state == State.UNSEALED and not state.cut_seal() and not state.assign_item(items[0].id, state.OPENING_ZONES[0]), "seal transitions once; no assignment before lid")
	check(ui.rows.is_empty() and state.get_opening_items().is_empty(), "UNSEALED still hides contents")
	await reopen(State.UNSEALED)
	state.state_changed.connect(nested)
	ui.lid_button.pressed.emit()
	state.state_changed.disconnect(nested)
	check(state.opening_state == State.SORTING and not state.open_lid(), "lid transitions once")
	check(ui.rows.size() == 4 and state.get_opening_items() == items, "exactly four rows from resource order")
	var row_ids = ui.rows.keys()
	for i in items.size():
		var row_text: String = ui.rows[items[i].id].label.text
		check(row_ids[i] == items[i].id and items[i].display_name in row_text and items[i].initial_condition in row_text, "data-driven row with initial condition " + str(i))
	var log_size: int = state.event_log.size()
	check(not state.assign_item("unknown", state.OPENING_ZONES[0]) and not state.assign_item(items[0].id, "unknown") and not state.assign_item(items[1].id, state.OPENING_ZONES[0]), "unknown id/zone and out of order rejected")
	check(state.item_zones.is_empty() and state.event_log.size() == log_size, "invalid calls do not mutate")
	var first_button: Button = ui.rows[items[0].id].buttons[0]
	var nested_assignment := func():
		check(state.item_zones.has(items[0].id) and state.opening_state == State.SORTING, "assignment visible before state_changed")
		check(not state.assign_item(items[1].id, state.OPENING_ZONES[0]), "nested next valid item blocked")
	state.state_changed.connect(nested_assignment)
	first_button.pressed.emit()
	state.state_changed.disconnect(nested_assignment)
	first_button.pressed.emit()
	check(state.item_zones.size() == 1 and not state.assign_item(items[0].id, state.OPENING_ZONES[1]), "stale double click and reassignment rejected")
	await reopen(State.SORTING)
	check(ui.rows.size() == 4 and state.item_zones.size() == 1, "reopen neither duplicates nor resets assignments")
	for i in range(1, 4):
		ui.rows[items[i].id].buttons[i % 3].pressed.emit()
		check(state.opening_state == (State.COMPLETE if i == 3 else State.SORTING), "COMPLETE only after fourth assignment " + str(i))
	check(state.tokens == 170 and state.item_zones.size() == 4 and "Итоговое распределение" in ui.summary_label.text, "four assignments, summary, balance 170")
	check(not state.assign_item(items[0].id, state.OPENING_ZONES[0]) and not state.cut_seal() and not state.open_lid(), "COMPLETE rejects repeated actions")
	await reopen(State.COMPLETE)
	for item in items:
		check(item.display_name in ui.summary_label.text and item.initial_condition in ui.summary_label.text and state.item_zones[item.id] in ui.summary_label.text, "summary contains resource item, initial condition and zone")
	# Each item x each zone gets a separate reset and a full four-item cycle.
	for target_index in items.size():
		for zone in state.OPENING_ZONES:
			prepare(State.SORTING)
			for i in items.size():
				var chosen: String = zone if i == target_index else state.OPENING_ZONES[2]
				check(state.assign_item(items[i].id, chosen), "4x3 assign index=%d target=%d zone=%s" % [i, target_index, zone])
			check(state.opening_state == State.COMPLETE and state.item_zones[items[target_index].id] == zone and state.tokens == 170, "4x3 cycle complete without money change")
	# Malformed data must not allow ambiguous/duplicate IDs. Restore resource immediately.
	prepare(State.UNSEALED)
	var original_id: String = items[1].id
	items[1].id = items[0].id
	var duplicate_rejected: bool = not state.open_lid()
	items[1].id = original_id
	check(duplicate_rejected and state.opening_state == State.UNSEALED, "duplicate resource IDs rejected before reveal")
	check(state.open_lid(), "restored data opens normally")
	for phase in [State.LOCKED, State.SEALED, State.UNSEALED, State.SORTING, State.COMPLETE]:
		prepare(phase)
		if phase == State.SORTING:
			state.assign_item(items[0].id, state.OPENING_ZONES[0])
		key(KEY_E)
		var balance: int = state.tokens
		var assignments: Dictionary = state.item_zones.duplicate()
		for code in [KEY_F2, KEY_F3, KEY_F4]:
			key(code)
		check(ui.visible and state.tokens == balance and state.opening_state == phase and state.item_zones == assignments, "modal blocks F2/F3/F4 phase " + str(phase))
		var pos: Vector3 = scene.player.position
		var rotation: Vector3 = scene.player.rotation
		Input.action_press("move_forward")
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(100, 100)
		scene._input(motion)
		await physics_frame
		await physics_frame
		Input.action_release("move_forward")
		check(scene.player.position.is_equal_approx(pos) and scene.player.rotation == rotation, "modal blocks movement/mouse phase " + str(phase))
		key(KEY_ESCAPE)
		key(KEY_F4)
		check(state.opening_state == State.LOCKED and state.item_zones.is_empty() and not state.lot_a_won and state.tokens == 750 and state.event_log.size() == 1 and ui.rows.is_empty(), "F4 fully resets phase " + str(phase))
	prepare(State.SEALED)
	key(KEY_F2)
	check(state.tokens == 270 and state.opening_state == State.SEALED, "F2 regression")
	key(KEY_F3)
	check(state.tokens == 170 and state.opening_state == State.SEALED, "F3 regression")
	# Production modal switch keeps a single visible screen.
	scene._show_modal(scene.auction_screen)
	scene._show_modal(ui)
	check(ui.visible and not scene.auction_screen.visible and scene._active_modal() == ui, "shared modality: only opening visible")
	scene._show_modal(scene.auction_screen)
	check(not ui.visible and scene.auction_screen.visible, "shared modality: only auction visible")
	key(KEY_ESCAPE)
	prepare(State.LOCKED)
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
			check(scene.get_world_3d().direct_space_state.intersect_ray(query).get("collider") == station, "ray collider is station, not Player")
			key(KEY_E)
			if title == "Терминал аукциона":
				check(scene.auction_screen.visible, "ray E auction")
				key(KEY_ESCAPE)
			elif title == "Стол вскрытия":
				check(ui.visible, "ray E opening")
				key(KEY_ESCAPE)
			else:
				check(scene.debug_label.text == "DEBUG: взаимодействие — " + title, "ray E other station")
	check(stations == 5, "15 points across five stations")
	print("S04_FAILURES=", failures)
	quit(0 if failures == 0 else 1)
