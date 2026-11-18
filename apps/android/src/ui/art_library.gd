class_name ArtLibrary
extends RefCounted

static var cache: Dictionary = {}
static var manifest: Array = []
static var indexed := false
const ANIMAL_TOKENS := {"elephant":"🐘","lion":"🦁","tiger":"🐯","leopard":"🐆","wolf":"🐺","dog":"🐶","cat":"🐱","rat":"🐭"}
const KENNEY := {"🐘":"elephant","🐼":"panda","🐧":"penguin","🐰":"rabbit","🐇":"rabbit","🐒":"monkey","🐵":"monkey","🐍":"snake","🐷":"pig","🐖":"pig","🦒":"giraffe","🦜":"parrot","🦛":"hippo"}

static func texture(token: String) -> Texture2D:
	if cache.has(token):
		return cache[token]
	var path := ""
	if KENNEY.has(token):
		path = "res://assets/kenney/animals/" + str(KENNEY[token]) + ".png"
	else:
		var codes: Array[String] = []
		for index in token.length():
			codes.append(_hex(token.unicode_at(index)))
		path = "res://assets/icons/" + "-".join(codes) + ".svg"
	var result: Texture2D = load(path) if ResourceLoader.exists(path) else null
	cache[token] = result
	return result


static func _hex(value: int) -> String:
	var digits := "0123456789ABCDEF"
	if value <= 0:
		return "0"
	var result := ""
	while value > 0:
		result = digits[value % 16] + result
		value = int(value / 16)
	return result

static func symbols(text: String) -> Array:
	if not indexed:
		if FileAccess.file_exists("res://content/art.json"):
			var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/art.json"))
			if value is Dictionary:
				manifest = value.get("downloaded",[])
		manifest.sort_custom(func(first,second): return str(first.token).length() > str(second.token).length())
		indexed = true
	var result: Array = []
	var cursor := 0
	while cursor < text.length():
		var found := false
		for entry in manifest:
			var token := str(entry.token)
			if text.substr(cursor,token.length()) == token:
				result.append(token)
				cursor += token.length()
				found = true
				break
		if not found:
			cursor += 1
	return result

static func picture(token: String, minimum: Vector2 = Vector2(100,100)) -> TextureRect:
	var node := TextureRect.new()
	node.texture = texture(token)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.custom_minimum_size = minimum
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return node
