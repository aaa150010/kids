class_name NativeShopGame
extends NativeGameScreen

const GAME_COLOR := Color("#7c7a2d")

var engine := ShopRules.new()
var game_header: Control
var counter: ShopCounter
var order_panel: PanelContainer
var basket_panel: PanelContainer
var action_panel: VBoxContainer
var status_label: Label
var _catalog: Dictionary = {}
var _orders: Array = []
var _data_loaded := false
var _result_visible := false
var _view := "map"


func _ready() -> void:
	build_shell()
	_load_data()
	var stored := SaveStore.load_state(game_id, players.map(func(player): return str(player.id)))
	stored.modeId = mode_id
	if engine.restore(stored):
		players = engine.state.players.duplicate(true)
		difficulty = str(engine.state.get("difficulty", difficulty))
		level_id = int(engine.state.get("levelId", 1))
		_view = str(engine.state.get("view", "counter"))
		if str(engine.state.phase) == "finished" and not bool(stored.get("resume", true)):
			_show_map()
			return
		if _view == "map":
			_show_map()
			return
		_build_game()
		_render(false)
	elif mode_id in ["adventure", "classic"]:
		_show_map()
		return
	call_deferred("begin_lesson")


func _load_data() -> void:
	if _data_loaded:
		return
	_data_loaded = true
	var data: Variant = ContentDB._json_dictionary("shop.json")
	if not data is Dictionary:
		return
	_catalog = {}
	for item in data.get("items", []):
		if not item is Dictionary:
			continue
		var item_id := str(item.get("id", ""))
		if not item_id.is_empty():
			_catalog[item_id] = item.duplicate(true)
	_orders = data.get("orders", []).duplicate(true)


func _show_map() -> void:
	_view = "map"
	_result_visible = false
	PlaygroundUI.clear(content_root)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_child(PlaygroundUI.label("今天开哪一家小店？", 30, accent, 700, true))
	copy.add_child(PlaygroundUI.label("每完成一单，就会记住你的找零本领。", 18, PlaygroundUI.INK_SOFT, 500, true))
	heading.add_child(copy)
	heading.add_child(PlaygroundUI.semantic_icon_button("hint", "怎么玩", accent, show_help, "soft"))
	content_root.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var grid := GridContainer.new()
	var viewport_width := get_viewport_rect().size.x
	grid.columns = 3 if viewport_width <= 1180.0 else 4 if viewport_width < 1500.0 else 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var learning := SaveStore.learning(str(players[0].id), game_id, mode_id)
	for index in _orders.size():
		var number := index + 1
		var order: Dictionary = _orders[index]
		var unlocked := SaveStore.level_unlocked(str(players[0].id), game_id, number, mode_id)
		var stars := clampi(int(learning.stars.get(str(number), 0)), 0, 3)
		var button := PlaygroundUI.semantic_icon_button(
			"play" if unlocked else "lock",
			"第 %s 单\n%s\n%s" % [
				number,
				str(order.get("title", "小小商店")),
				"已获 %s / 3 星" % stars if unlocked else "继续完成上一单解锁",
			],
			accent,
			_choose_level.bind(number),
			"soft"
		)
		button.custom_minimum_size = Vector2(0, 116)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not unlocked
		grid.add_child(button)
	scroll.add_child(grid)
	content_root.add_child(scroll)
	if not engine.state.is_empty():
		_save("正在选择商店订单")


func _choose_level(number: int) -> void:
	if not SaveStore.level_unlocked(str(players[0].id), game_id, number, mode_id):
		show_toast("先完成上一单，再来挑战这一单。")
		return
	_start_level(number)
	begin_lesson()


func _start_level(number: int) -> void:
	_load_data()
	if _catalog.is_empty() or _orders.is_empty():
		show_toast("商店内容暂未准备好")
		return
	level_id = clampi(number, 1, _orders.size())
	_result_visible = false
	var order: Dictionary = _orders[level_id - 1]
	engine.create_session({
		"gameId": game_id,
		"modeId": mode_id,
		"players": players.duplicate(true),
		"levelId": level_id,
		"seed": Time.get_ticks_usec(),
		"difficulty": difficulty,
		"catalog": _catalog,
		"order": order,
		"hintsMax": int(GameTuning.value(game_id, difficulty, "hints", 2)),
	})
	_view = "counter"
	_build_game()
	_render(false)
	_save("开始第 %s 单" % level_id)


func _build_game() -> void:
	_view = "counter"
	PlaygroundUI.clear(content_root)
	game_header = HBoxContainer.new()
	game_header.add_theme_constant_override("separation", 12)
	var title := VBoxContainer.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(PlaygroundUI.label("第 %s 单 · %s" % [level_id, str(engine.state.order.get("title", "小小商店"))], 26, accent, 700, true))
	title.add_child(PlaygroundUI.label("顾客在等你，先把商品放进购物篮。", 16, PlaygroundUI.INK_SOFT, 500, true))
	game_header.add_child(title)
	game_header.add_child(_player_badge(0))
	if players.size() > 1:
		game_header.add_child(_player_badge(1))
	game_header.add_child(PlaygroundUI.semantic_icon_button("back", "订单地图", accent, _show_map, "soft"))
	content_root.add_child(game_header)

	var main := HBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 16)
	content_root.add_child(main)

	counter = ShopCounter.new()
	counter.configure(_items_array(), accent)
	counter.set_basket(engine.state.basket)
	counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	counter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	counter.size_flags_stretch_ratio = 1.45
	counter.item_pressed.connect(_on_item_pressed)
	main.add_child(counter)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 430
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	main.add_child(right)
	order_panel = PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.9), 22, PlaygroundUI.mix(accent, Color.WHITE, 0.5), 2)
	order_panel.custom_minimum_size.y = 160
	right.add_child(order_panel)
	basket_panel = PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.94), 22, PlaygroundUI.LINE, 1)
	basket_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(basket_panel)
	action_panel = VBoxContainer.new()
	action_panel.add_theme_constant_override("separation", 10)
	right.add_child(action_panel)
	status_label = PlaygroundUI.label("", 17, PlaygroundUI.INK_SOFT, 600, true)
	right.add_child(status_label)
	_on_immersive_changed(immersive)


func _on_immersive_changed(value: bool) -> void:
	if game_header != null and is_instance_valid(game_header):
		game_header.visible = not value


func _player_badge(index: int) -> Control:
	var player: Dictionary = players[index] if index < players.size() else {}
	var tint := PlaygroundUI.color(str(player.get("color", "#7c7a2d")))
	var panel := PlaygroundUI.panel(PlaygroundUI.mix(tint, Color.WHITE, 0.86), 16, PlaygroundUI.mix(tint, Color.WHITE, 0.45), 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.add_child(ArtLibrary.profile_picture(player, Vector2(34, 34)))
	row.add_child(PlaygroundUI.label("一起看店" if players.size() > 1 else str(player.get("name", "小店长")), 16, PlaygroundUI.INK, 700))
	panel.add_child(row)
	return panel


func _items_array() -> Array:
	var result: Array = []
	for item in _catalog.values():
		result.append(item)
	return result


func _render(_animate: bool = true) -> void:
	if engine.state.is_empty():
		return
	if str(engine.state.phase) == "finished":
		_show_result()
		return
	var phase := str(engine.state.phase)
	counter.set_basket(engine.state.basket)
	counter.set_enabled(not paused and phase == "basket")
	_fill_order_panel()
	_fill_basket_panel()
	_fill_actions(phase)
	match phase:
		"basket":
			status_label.text = "把顾客清单上的商品都放进购物篮，然后去收银。"
		"pay":
			status_label.text = "点硬币或纸币付款。付够以后点“完成付款”。"
		"empty":
			status_label.text = "这单暂时没有内容。"


func _fill_order_panel() -> void:
	PlaygroundUI.clear(order_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	order_panel.add_child(column)
	column.add_child(PlaygroundUI.label("顾客清单", 18, accent, 700))
	for line in engine.order_lines():
		column.add_child(PlaygroundUI.label(str(line), 17, PlaygroundUI.INK, 600, true))


func _fill_basket_panel() -> void:
	PlaygroundUI.clear(basket_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	basket_panel.add_child(column)
	column.add_child(PlaygroundUI.label("购物篮 · %s 件" % engine.basket_count(), 18, accent, 700))
	var lines := engine.basket_lines()
	if lines.is_empty():
		column.add_child(PlaygroundUI.label("还没有拿商品", 16, PlaygroundUI.INK_SOFT, 500, true))
	else:
		for item_id in engine.state.basket:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var item: Dictionary = engine.item(str(item_id))
			row.add_child(PlaygroundUI.label("%s × %s" % [str(item.get("name", item_id)), int(engine.state.basket[item_id])], 17, PlaygroundUI.INK, 600, true))
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(spacer)
			var remove := PlaygroundUI.button("减一", accent, _remove_item.bind(str(item_id)), "ghost")
			remove.custom_minimum_size = Vector2(62, 44)
			row.add_child(remove)
			column.add_child(row)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(filler)


func _fill_actions(phase: String) -> void:
	PlaygroundUI.clear(action_panel)
	if phase == "basket":
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(PlaygroundUI.button("去收银", accent, _checkout, "primary"))
		row.add_child(PlaygroundUI.button("清空", accent, _clear_basket, "soft"))
		row.add_child(PlaygroundUI.button("提示", accent, _hint, "soft"))
		action_panel.add_child(row)
	elif phase == "pay":
		var totals := HBoxContainer.new()
		totals.add_theme_constant_override("separation", 8)
		totals.add_child(PlaygroundUI.chip("总价 %s 元" % int(engine.state.total), accent))
		totals.add_child(PlaygroundUI.chip("已付 %s 元" % int(engine.state.paid), accent))
		action_panel.add_child(totals)
		var money := GridContainer.new()
		money.columns = 3
		money.add_theme_constant_override("h_separation", 8)
		money.add_theme_constant_override("v_separation", 8)
		for value in ShopRules.COIN_VALUES:
			var button := PlaygroundUI.button("%s 元" % value, accent, _pay.bind(int(value)), "soft")
			button.custom_minimum_size = Vector2(0, 52)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			money.add_child(button)
		action_panel.add_child(money)
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 8)
		var can_finish := int(engine.state.paid) >= int(engine.state.total)
		var finish := PlaygroundUI.button("完成付款", accent, _confirm_payment, "primary")
		finish.disabled = not can_finish
		actions.add_child(finish)
		actions.add_child(PlaygroundUI.button("重新选商品", accent, _back_to_basket, "soft"))
		actions.add_child(PlaygroundUI.button("提示", accent, _hint, "soft"))
		action_panel.add_child(actions)
	elif phase == "empty":
		action_panel.add_child(PlaygroundUI.semantic_icon_button("back", "回订单地图", accent, _show_map, "soft"))


func _on_item_pressed(item_id: String) -> void:
	if paused or str(engine.state.phase) != "basket":
		return
	var result := engine.handle_input({"type": "add_item", "item_id": item_id})
	if not bool(result.ok):
		show_toast(str(result.get("message", "先看看货架")))
		return
	SfxMap.play(&"tap")
	_save("把商品放进购物篮")
	_render(false)


func _remove_item(item_id: String) -> void:
	if paused or str(engine.state.phase) != "basket":
		return
	var result := engine.handle_input({"type": "remove_item", "item_id": item_id})
	if bool(result.ok):
		SfxMap.play(&"tap")
		_save("从购物篮拿走商品")
		_render(false)


func _clear_basket() -> void:
	if paused:
		return
	var result := engine.handle_input({"type": "clear_basket"})
	if bool(result.ok):
		SfxMap.play(&"tap")
		_save("清空购物篮")
		_render(false)


func _checkout() -> void:
	if paused:
		return
	var result := engine.handle_input({"type": "checkout"})
	if not bool(result.ok):
		show_toast(str(result.get("message", "再检查一下商品")))
		return
	SfxMap.play(&"select")
	_save("去收银台")
	_render(false)


func _pay(value: int) -> void:
	if paused or str(engine.state.phase) != "pay":
		return
	var result := engine.handle_input({"type": "pay", "value": value})
	if not bool(result.ok):
		show_toast(str(result.get("message", "先选一种钱币")))
		return
	SfxMap.play(&"tap")
	_save("数钱付款")
	_render(false)


func _confirm_payment() -> void:
	if paused:
		return
	var result := engine.handle_input({"type": "confirm_payment"})
	if not bool(result.ok):
		show_toast(str(result.get("message", "再数一数钱")))
		return
	SfxMap.play(&"success")
	FeedbackKit.haptic(12)
	_save("订单完成", false)
	_render(false)


func _back_to_basket() -> void:
	if paused:
		return
	var result := engine.handle_input({"type": "back_to_basket"})
	if bool(result.ok):
		_save("重新选择商品")
		_render(false)


func _hint() -> void:
	if paused:
		return
	var result := engine.handle_input({"type": "hint"})
	if not bool(result.ok):
		show_toast(str(result.get("message", "提示次数用完了")))
		return
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.add_child(ArtLibrary.semantic_picture("hint", "ui", Vector2(56, 56)))
	body.add_child(PlaygroundUI.label(str(result.get("hint", "看看顾客清单和价格。")), 20, PlaygroundUI.INK, 600, true))
	open_modal("小店提示", body, [
		{"text": "继续看店", "icon": "back", "kind": "primary", "callback": func(): _close_top_modal()},
	], "提示不会直接替你付款")
	_save("看提示")


func _show_result() -> void:
	if _result_visible:
		return
	_result_visible = true
	var stars := int(engine.state.get("stars", 0))
	if not bool(engine.state.get("reported", false)):
		for player in players:
			var player_id := str(player.id)
			var outcome := "win" if mode_id == "adventure" and stars > 0 else "played"
			SaveStore.complete_level(player_id, game_id, level_id, stars, mode_id)
			SaveStore.record_outcome(
				player_id,
				game_id,
				outcome,
				int(engine.state.score),
				engine.basket_count(),
				engine.basket_count(),
				{"math": {"correct": engine.basket_count(), "answered": engine.basket_count()}},
				str(engine.state.sessionId)
			)
		engine.state.reported = true
		_save("订单完成", false)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(84, 84))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	body.add_child(PlaygroundUI.label("这一单完成啦！", 26, accent, 700))
	body.add_child(PlaygroundUI.label("找零 %s 元 · 本单得分 %s" % [int(engine.state.change), int(engine.state.score)], 20, PlaygroundUI.INK, 600, true))
	var star_row := HBoxContainer.new()
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	star_row.add_theme_constant_override("separation", 7)
	for index in 3:
		var star := ArtLibrary.semantic_picture("star", "ui", Vector2(36, 36))
		star.modulate = Color.WHITE if index < stars else Color(1, 1, 1, 0.24)
		star_row.add_child(star)
	body.add_child(star_row)
	var actions: Array = [{"text": "关卡地图", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal(); _show_map()}]
	if level_id < _orders.size():
		actions.append({"text": "下一单", "icon": "next", "kind": "primary", "callback": func(): _close_top_modal(); _choose_level(level_id + 1)})
	actions.append({"text": "再练一次", "icon": "repeat", "kind": "primary" if level_id >= _orders.size() else "soft", "callback": func(): _close_top_modal(); _start_level(level_id)})
	open_modal("订单完成", body, actions, "钱数算得清清楚楚")
	SfxMap.play(&"win")
	FeedbackKit.haptic(12)


func _extra_pause_actions() -> Array:
	return [{"text": "订单地图", "icon": "back", "kind": "soft", "callback": func(): _close_pause_tools(); _show_map()}]


func _save(note: String, resume: bool = true) -> void:
	if engine.state.is_empty():
		return
	engine.state.view = _view
	SaveStore.save_state(
		game_id,
		str(players[0].id),
		engine.snapshot(),
		note,
		resume and (str(engine.state.phase) in ["basket", "pay"] or _view == "map")
	)
