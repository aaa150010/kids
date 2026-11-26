class_name ShopRules
extends GameSession

const SHOP_VERSION := 1
const COIN_VALUES := [1, 2, 5, 10, 20, 50]


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var catalog: Dictionary = context.get("catalog", {})
	var order: Dictionary = context.get("order", {})
	var total := order_total(order, catalog)
	state.merge({
		"shopVersion": SHOP_VERSION,
		"modeId": str(context.get("modeId", "classic")),
		"phase": "basket",
		"levelId": int(context.get("levelId", 1)),
		"catalog": catalog.duplicate(true),
		"order": order.duplicate(true),
		"basket": {},
		"paidCoins": [],
		"paid": 0,
		"total": total,
		"change": 0,
		"score": 0,
		"stars": 0,
		"hints": 0,
		"hintsMax": maxi(0, int(context.get("hintsMax", 2))),
		"mistakes": 0,
		"reported": false,
		"view": "counter",
	}, true)
	if catalog.is_empty() or order.is_empty() or total <= 0:
		state.phase = "empty"
	return state


func restore(value: Dictionary) -> bool:
	if int(value.get("shopVersion", 0)) != SHOP_VERSION:
		return false
	if not super.restore(value):
		return false
	if not (str(state.get("phase", "")) in ["basket", "pay", "finished", "empty"]):
		return false
	if not state.get("catalog") is Dictionary or not state.get("order") is Dictionary:
		return false
	if not state.get("basket") is Dictionary:
		return false
	var catalog: Dictionary = state.catalog
	var order: Dictionary = state.order
	if catalog.is_empty() or order.is_empty():
		return false
	for requirement in order.get("items", []):
		if not requirement is Dictionary:
			return false
		var item_id := str(requirement.get("item", ""))
		var qty := int(requirement.get("qty", 0))
		if not catalog.has(item_id) or qty <= 0:
			return false
	var clean_basket := {}
	for item_id in state.basket:
		var qty := int(state.basket[item_id])
		if not catalog.has(str(item_id)) or qty <= 0:
			return false
		clean_basket[str(item_id)] = qty
	state.basket = clean_basket
	state.total = order_total(order, catalog)
	if state.total <= 0:
		return false
	state.levelId = maxi(1, int(state.get("levelId", 1)))
	state.paid = maxi(0, int(state.get("paid", 0)))
	state.change = maxi(0, int(state.get("change", 0)))
	state.score = maxi(0, int(state.get("score", 0)))
	state.stars = clampi(int(state.get("stars", 0)), 0, 3)
	state.hints = maxi(0, int(state.get("hints", 0)))
	state.hintsMax = maxi(0, int(state.get("hintsMax", 2)))
	state.mistakes = maxi(0, int(state.get("mistakes", 0)))
	var coins: Variant = state.get("paidCoins", [])
	if not coins is Array:
		coins = []
	var clean_coins: Array = []
	for coin in coins:
		var amount := int(coin)
		if amount in COIN_VALUES:
			clean_coins.append(amount)
	state.paidCoins = clean_coins
	if str(state.phase) in ["pay", "finished"] and not _basket_matches():
		return false
	if str(state.phase) == "finished" and state.paid < state.total:
		return false
	state.view = str(state.get("view", "counter"))
	return true


func handle_input(action: Dictionary) -> Dictionary:
	if str(state.get("phase", "")) in ["empty", "finished"]:
		return {"ok": false, "message": "这一单已经完成啦"}
	match str(action.get("type", "")):
		"add_item":
			if str(state.phase) != "basket":
				return {"ok": false, "message": "先去收银台付款"}
			var item_id := str(action.get("item_id", ""))
			if not state.catalog.has(item_id):
				return {"ok": false, "message": "货架上没有这件商品"}
			state.basket[item_id] = int(state.basket.get(item_id, 0)) + 1
			return {"ok": true, "event": "basket", "item_id": item_id}
		"remove_item":
			if str(state.phase) != "basket":
				return {"ok": false, "message": "现在不能修改购物篮"}
			var remove_id := str(action.get("item_id", ""))
			var current := int(state.basket.get(remove_id, 0))
			if current <= 0:
				return {"ok": false}
			if current == 1:
				state.basket.erase(remove_id)
			else:
				state.basket[remove_id] = current - 1
			return {"ok": true, "event": "basket", "item_id": remove_id}
		"clear_basket":
			if str(state.phase) != "basket":
				return {"ok": false}
			state.basket = {}
			return {"ok": true, "event": "basket"}
		"checkout":
			if str(state.phase) != "basket":
				return {"ok": false}
			if not _basket_matches():
				state.mistakes = int(state.mistakes) + 1
				return {"ok": false, "message": "商品和顾客清单还不能对上，再检查一下"}
			state.phase = "pay"
			return {"ok": true, "event": "pay", "total": int(state.total)}
		"pay":
			if str(state.phase) != "pay":
				return {"ok": false}
			var coin := int(action.get("value", 0))
			if not (coin in COIN_VALUES):
				return {"ok": false, "message": "请选一种硬币或纸币"}
			state.paidCoins.append(coin)
			state.paid = int(state.paid) + coin
			return {"ok": true, "event": "pay", "paid": int(state.paid)}
		"confirm_payment":
			if str(state.phase) != "pay":
				return {"ok": false}
			if int(state.paid) < int(state.total):
				state.mistakes = int(state.mistakes) + 1
				return {"ok": false, "message": "还差 %s 元，再数一数" % (int(state.total) - int(state.paid))}
			state.change = int(state.paid) - int(state.total)
			state.phase = "finished"
			state.score = maxi(1, 10 - int(state.hints) - int(state.mistakes))
			state.stars = _calculate_stars()
			return {"ok": true, "event": "finished", "change": int(state.change)}
		"back_to_basket":
			if str(state.phase) != "pay":
				return {"ok": false}
			state.phase = "basket"
			state.paid = 0
			state.paidCoins = []
			state.change = 0
			return {"ok": true, "event": "basket"}
		"hint":
			if int(state.hints) >= int(state.hintsMax):
				return {"ok": false, "message": "这一档难度的提示次数已经用完"}
			state.hints = int(state.hints) + 1
			if str(state.phase) == "basket":
				return {"ok": true, "hint": "先看顾客清单，把每样商品和数量都放进购物篮。"}
			if str(state.phase) == "pay":
				return {"ok": true, "hint": "这一单一共 %s 元，先付够总价，再点完成付款。" % int(state.total)}
			return {"ok": false}
	return {"ok": false}


func order_lines() -> Array[String]:
	var result: Array[String] = []
	for requirement in state.get("order", {}).get("items", []):
		var item_id := str(requirement.get("item", ""))
		var item: Dictionary = state.catalog.get(item_id, {})
		result.append("%s × %s（%s 元）" % [
			str(item.get("name", item_id)),
			int(requirement.get("qty", 0)),
			int(item.get("price", 0)),
		])
	return result


func basket_lines() -> Array[String]:
	var result: Array[String] = []
	for item_id in state.get("basket", {}):
		var item: Dictionary = state.catalog.get(str(item_id), {})
		result.append("%s × %s" % [str(item.get("name", item_id)), int(state.basket[item_id])])
	return result


func basket_count() -> int:
	var count := 0
	for qty in state.get("basket", {}).values():
		count += int(qty)
	return count


func item(item_id: String) -> Dictionary:
	return state.get("catalog", {}).get(item_id, {})


func result() -> Dictionary:
	if str(state.get("phase", "")) != "finished":
		return {}
	return {
		"score": int(state.get("score", 0)),
		"stars": int(state.get("stars", 0)),
		"change": int(state.get("change", 0)),
		"reason": "订单完成，找零 %s 元" % int(state.get("change", 0)),
	}


static func order_total(order: Dictionary, catalog: Dictionary) -> int:
	var total := 0
	for requirement in order.get("items", []):
		if not requirement is Dictionary:
			continue
		var item_id := str(requirement.get("item", ""))
		var item: Dictionary = catalog.get(item_id, {})
		total += int(item.get("price", 0)) * int(requirement.get("qty", 0))
	return total


func _basket_matches() -> bool:
	var requirements: Dictionary = {}
	for requirement in state.get("order", {}).get("items", []):
		if not requirement is Dictionary:
			return false
		var item_id := str(requirement.get("item", ""))
		var qty := int(requirement.get("qty", 0))
		if qty <= 0:
			return false
		requirements[item_id] = qty
	if requirements.size() != state.get("basket", {}).size():
		return false
	for item_id in requirements:
		if int(state.basket.get(item_id, 0)) != int(requirements[item_id]):
			return false
	return true


func _calculate_stars() -> int:
	if int(state.hints) == 0 and int(state.mistakes) == 0:
		return 3
	if int(state.hints) <= 1 and int(state.mistakes) <= 1:
		return 2
	return 1
