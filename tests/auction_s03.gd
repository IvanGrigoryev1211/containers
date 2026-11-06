extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, description: String) -> void:
	print(("PASS " if ok else "FAIL ") + description)
	if not ok:
		failures += 1


func key(scene: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	scene._input(event)


func run() -> void:
	var scene = load("res://Workshop.tscn").instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame
	var state = root.get_node("GameState")
	var ui = scene.auction_screen
	check(state.tokens == 750 and not state.lot_a_won, "startup 750; unowned")
	check(ui.LOT_A.visible_evidence.size() == 4, "four data-driven clues")
	# Reach the actual terminal with the production ray and E route.
	var terminal = scene.get_node("Терминал_аукциона")
	scene.player.position = terminal.position + Vector3(0, 1.7, 2.2)
	scene.camera.look_at(terminal.position + Vector3(0, 0.5, 0))
	await physics_frame
	await physics_frame
	key(scene, KEY_E)
	check(ui.visible, "terminal E opens auction (low geometry ray)")
	var pos: Vector3 = scene.player.position
	Input.action_press("move_forward")
	await physics_frame
	await physics_frame
	Input.action_release("move_forward")
	check(scene.player.position.is_equal_approx(pos), "modal blocks movement")
	key(scene, KEY_E)
	check(ui.visible and state.tokens == 750, "E while modal cannot interact or spend")
	key(scene, KEY_ESCAPE)
	check(not ui.visible and state.tokens == 750 and state.event_log.size() == 1, "Esc cancels without money/log mutation")
	check(state.submit_lot_a_bid(519, "below") == "invalid", "below start rejected")
	check(state.submit_lot_a_bid(621, "above") == "invalid", "above 620 rejected")
	check(state.tokens == 750 and state.event_log.size() == 1, "invalid limits have no effects")
	ui.open()
	ui.bid.value = 1
	check(ui.bid.value == 520, "UI minimum 520")
	ui.bid.value = 999
	check(ui.bid.value == 620, "UI maximum 620")
	state.spend(200, "QA: balance cap")
	check(ui.bid.max_value == 550, "UI maximum follows balance")
	check(state.submit_lot_a_bid(580, "too much") == "invalid" and state.tokens == 550, "above balance rejected")
	state.spend(100, "QA: below start")
	check(ui.confirm_button.disabled and not ui.bid.editable, "no valid limit below start balance")
	ui.close()
	key(scene, KEY_F4)
	check(state.tokens == 750 and not state.lot_a_won, "F4 fresh auction")
	ui.open()
	ui.bid.value = 579
	ui.hypothesis.text = "Прибор; риск воды"
	await process_frame
	ui.confirm_button.pressed.emit()
	check(state.tokens == 750 and not state.lot_a_won, "579 loses deterministically without payment")
	check("Фиксированные соперники" in state.event_log[-1], "rival rule logged on loss")
	# During spend's state_changed signal, a repeated call must not settle again.
	var reenter := func():
		if state.tokens == 170:
			check(state.submit_lot_a_bid(580, "reentrant") == "already_won", "reentrant submission blocked")
	state.state_changed.connect(reenter)
	ui.bid.value = 620
	await process_frame
	ui.confirm_button.pressed.emit()
	state.state_changed.disconnect(reenter)
	check(state.tokens == 170 and state.lot_a_paid == 580 and state.lot_a_bid_limit == 620, "limit 620 wins for 580 exactly once")
	await process_frame
	check(ui.bid_summary.visible and ui.bid_summary.text == "620" and not ui.bid.visible, "winning limit remains visible as read-only 620")
	check(state.lot_a_won and state.lot_a_hypothesis == "Прибор; риск воды", "ownership and hypothesis recorded")
	check(state.current_stage == "лот A выигран; вскрытие ещё не реализовано", "stage updated")
	var logs: String = "\n".join(state.event_log)
	check("предел 620; гипотеза: Прибор; риск воды" in logs and "победу за 580" in logs, "bid, hypothesis and rival rule logged")
	var spent := 0
	for entry in state.event_log:
		if entry.begins_with("Списано"):
			spent += 1
	check(spent == 1, "exactly one spend entry")
	check(ui.confirm_button.disabled and not ui.hypothesis.editable and "следующей сессией" in ui.result_label.text, "win placeholder and disabled controls")
	ui.confirm_button.pressed.emit()
	ui.close()
	ui.open()
	ui._confirm()
	check(state.submit_lot_a_bid(580, "again") == "already_won" and state.tokens == 170, "double click/reopen/direct resubmit never charges")
	ui.close()
	key(scene, KEY_F2)
	check(state.tokens == 270 and state.lot_a_won, "F2 preserves ownership")
	key(scene, KEY_F3)
	check(state.tokens == 170 and state.lot_a_won, "F3 preserves ownership")
	key(scene, KEY_F4)
	check(state.tokens == 750 and not state.lot_a_won and state.lot_a_paid == 0, "F4 resets ownership and money explicitly")
	check(state.submit_lot_a_bid(580, "") == "won" and state.tokens == 170, "exact threshold 580 and optional blank hypothesis")
	print("S03_FAILURES=", failures)
	quit(0 if failures == 0 else 1)
