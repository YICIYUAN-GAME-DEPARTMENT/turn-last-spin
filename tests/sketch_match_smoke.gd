extends SceneTree
## 测试 Godot 实际场景的商店输入、原钱包和镜头切换。
const ClientScene = preload("res://scenes/main.tscn")
const Rules = preload("res://scripts/core/game_rules.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 820)
	var scene := ClientScene.instantiate()
	root.add_child(scene)
	var game = scene.game
	var view = scene.match_view
	var shop = view.shop
	var stop_hold: float = view.presentation_timing.wheel_stop_hold
	var intro_seconds: float = view.presentation_timing.turn_intro_seconds
	game.start_local_test(8, 1)
	if not await _until(func(): return view.round_announcement.visible and view.round_announcement.modulate.a > 0.9, intro_seconds + 0.5):
		_fail("首轮缺少居中的回合提示")
		return
	if view.round_announcement.text != "turn 1" or game.phase != "round_intro" or view.round_label.visible:
		_fail("首轮回合提示的数字或时机错误")
		return
	await _capture("round_one_intro")
	if not await _until(func(): return game.phase == "choosing" and view._initial_spin and view.wheel.view_height > 0.99 and absf(view.wheel.needle_angle - view.wheel.seat_angle(view.wheel.start_index)) < 0.001, intro_seconds + 2.5):
		_fail("开局没有转到定位点")
		return
	if stop_hold >= 0.1:
		await create_timer(stop_hold * 0.45).timeout
		if not view._initial_spin or view.wheel.view_height < 0.99 or not view.primary_button.disabled:
			_fail("开局停盘时提前进入出牌阶段")
			return
		if not view.wheel.self_deal.is_empty() or not is_zero_approx(view.wheel.deal_progress):
			_fail("俯视停盘时不应发牌")
			return
	if not await _until(func(): return view.wheel.deal_progress > 0.52, stop_hold + 2.0):
		_fail("回到正视后未发牌")
		return
	if not is_zero_approx(view.wheel.view_height) or view.wheel.self_deal.is_empty():
		_fail("发牌必须从正视镜头下的牌堆起飞")
		return
	await _capture("deck_deal")
	if not await _until(func(): return game.can_act() and not view._initial_spin, intro_seconds + stop_hold + 3.5):
		_fail("经典模式未进入出牌视角")
		return
	if view.round_announcement.visible or not view.round_label.visible:
		_fail("进入出牌阶段后未恢复顶部回合号")
		return
	if game.balance != 50 or game.card_prices != {"defense": 100, "change": 100, "super": 500}:
		_fail("经典模式原始钱包或定价丢失")
		return
	await _click(shop.entry)
	if not await _until(func(): return is_equal_approx(shop.progress, 1.0), 1.5):
		_fail("商店未推镜")
		return
	if not shop.pickup_buttons.all(func(button): return button.disabled):
		_fail("经典模式 50r 不足以购买特殊牌")
		return
	await _capture("shop_classic")
	await _click_at(Vector2(300, 165), MOUSE_BUTTON_RIGHT)
	if not await _until(func(): return is_zero_approx(shop.progress), 1.5):
		_fail("右键未退出商店")
		return

	game.economy_settings.starting_balance = 450
	game.start_local_test(8, 1, Rules.Mode.GREED)
	if not await _until(func(): return game.can_act() and not view._initial_spin, intro_seconds + stop_hold + 3.5):
		_fail("贪婪模式未进入出牌视角")
		return
	if game.card_prices != {"defense": 50, "change": 50, "super": 250} or int(view.coins.reading) != 450:
		_fail("贪婪模式定价或钱包显示错误")
		return
	await _click(shop.entry)
	if not await _until(func(): return is_equal_approx(shop.progress, 1.0), 1.5):
		_fail("贪婪模式未推镜")
		return
	await _click(shop.add_buttons[1])
	var listing: Button = shop.card_buttons[1]
	var motion := InputEventMouseMotion.new()
	motion.position = _button_center(listing)
	Input.parse_input_event(motion)
	await process_frame
	await _capture("shop")
	await _click(shop.pickup_buttons[1])
	if game.balance != 350 or game.special_cards != {"change": 2}:
		_fail("单槽多张购买没有按原价一次扣款并入暗牌库存")
		return
	if game.public.hands[game.local_id()].size() != 1 or game.public.hidden_card_counts[game.local_id()] != 2:
		_fail("购买的特殊牌改变了公开手牌")
		return
	await create_timer(0.42).timeout
	await _capture("chips")
	await create_timer(1.21).timeout
	await _capture("delivery")
	await _click(shop.back)
	if not await _until(func(): return is_zero_approx(shop.progress), 1.5):
		_fail("左下角返回按钮未退出商店")
		return
	await _capture("table")
	if not view.status_label.text.is_empty() or view.wheel.countdown_seconds != game.seconds_left():
		_fail("出牌倒计时应显示在装置里")
		return
	var seconds: int = view.wheel.countdown_seconds
	if not await _until(func(): return view.wheel.countdown_seconds < seconds, 1.3):
		_fail("装置里的倒计时没有继续走")
		return
	var own: int = game.local_id()
	var waiting: Dictionary = view.wheel.table_cards
	if waiting.size() != 7 or not waiting.values().all(func(cards): return cards[0] == {"face_up": false}):
		_fail("其他玩家的锁定牌应只有背面")
		return
	var hand: Array = game.public.hands[own]
	var card_id: int = hand[0].id
	var card_path := "HandCard_%d" % card_id
	await _click(view.hand_fan.get_node(card_path))
	if not view.action_overlay.visible:
		_fail("点击手牌后未弹出出牌菜单")
		return
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	await _click(view.action_menu.get_node("Column/Choices/Plus"))
	if not await _until(func(): return game.phase == "settlement", 1.5):
		_fail("没有进入结算")
		return
	if view.hand_fan.has_node(card_path) or not view.wheel.table_cards.get(own, {}).get(0, {}).get("face_up", false):
		_fail("打出的牌应离开手牌并正面摆在桌上")
		return
	if not view.status_label.text.is_empty() or view.wheel.countdown_seconds != game.seconds_left() or view.wheel.center_caption != "初始":
		_fail("轮盘启动前应通过装置显示倒计时和初始指向")
		return
	if view.wheel.table_cards.get(2, {}).get(0, {}) != {"face_up": false}:
		_fail("结算转动前对手牌面泄露到界面")
		return
	await create_timer(0.35).timeout
	await _capture("cards_covered")
	var before_balance: int = view.coins.amount
	var before_seats: Dictionary = view._wheel_balances.duplicate()
	var before_statistics: String = view.stats_totals.text
	await _click(view.primary_button)
	if not await _until(func(): return is_equal_approx(view.wheel.view_height, 1.0), 1.5):
		_fail("转盘结算没有升到正俯视")
		return
	if view.wheel.center_steps != "—" or view.wheel.target_index != -1 or view.wheel.countdown_seconds != -1:
		_fail("升镜时提前显示最终位移或落点，或残留操作倒计时")
		return
	if stop_hold >= 0.1:
		if not await _until(func(): return view.wheel.center_caption == "停盘", 2.0):
			_fail("结算转盘没有停稳")
			return
		await create_timer(stop_hold * 0.45).timeout
		if view.wheel.target_index != -1 or view.wheel.center_steps != "—" or view.reward.visible:
			_fail("停盘等待时提前显示最终结果")
			return
	if view.coins.amount != before_balance or view._wheel_balances != before_seats or view.stats_totals.text != before_statistics:
		_fail("转盘结算期间提前更新筹码或统计")
		return
	if not await _until(func(): return view.wheel.target_index >= 0, stop_hold + 1.5):
		_fail("停盘后没有显示落点")
		return
	if not is_equal_approx(view.wheel.play_progress, 1.0) or not view.wheel.table_cards.get(2, {}).get(0, {}).get("face_up", false):
		_fail("对手盖牌没有在转盘开始前翻开")
		return
	await _capture("overhead")
	if not await _until(func(): return is_zero_approx(view.wheel.view_height) and not view._presenting_result, 2.0):
		_fail("转盘停下后没有回到牌桌")
		return
	if view._wheel_balances != game.public.balances:
		_fail("回到正视后未显示最终筹码")
		return
	if not await _until(func(): return view.round_announcement.visible and view.round_announcement.modulate.a > 0.9, intro_seconds + stop_hold + 5.0):
		_fail("第二轮开始时没有显示回合提示")
		return
	if view.round_announcement.text != "turn 2" or game.phase != "round_intro":
		_fail("第二轮回合提示没有更新实际回合数")
		return
	await _capture("round_two_intro")
	if not await _until(func(): return game.phase == "choosing" and game.public.round == 2 and view.wheel.view_height > 0.99, intro_seconds + stop_hold + 7.0):
		_fail("第二轮没有再次升到俯视")
		return
	var overhead_extent: Vector2 = view.wheel.table_extent()
	if not await _until(func(): return game.can_act() and not view._initial_spin, stop_hold + 4.0):
		_fail("第二轮没有回到正视出牌")
		return
	var seated_extent: Vector2 = view.wheel.table_extent()
	if absf(overhead_extent.y / overhead_extent.x - 1.0) > 0.02 or seated_extent.y / seated_extent.x > 0.40:
		_fail("正视和俯视的转盘透视没有明显区分")
		return
	await _capture("round_two")
	print("TURN_SKETCH_MATCH_OK")
	quit()

func _button_center(button: Button) -> Vector2:
	return root.get_final_transform() * (button.get_global_transform() * (button.size * 0.5))

func _click(button: Button) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = _button_center(button)
	Input.parse_input_event(motion)
	await process_frame
	await _click_at(_button_center(button), MOUSE_BUTTON_LEFT)

func _click_at(point: Vector2, index: MouseButton) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = index
		event.pressed = pressed
		Input.parse_input_event(event)
	await process_frame

func _until(condition: Callable, seconds: float) -> bool:
	var timeout := create_timer(seconds)
	while not condition.call() and timeout.time_left > 0.0:
		await process_frame
	return condition.call()

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/sketch_" + name + ".png")
	await process_frame

func _fail(reason: String) -> void:
	push_error("TURN_SKETCH_MATCH_FAIL: " + reason)
	quit(2)
