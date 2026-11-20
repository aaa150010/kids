class_name ArtLibrary
extends RefCounted

static var cache: Dictionary = {}
static var manifest: Array = []
static var indexed := false
const SEMANTIC_SLOTS := {
	"back":0,"close":1,"pause":2,"play":3,"continue":4,"rules":5,"sound":6,"music":7,
	"speech":8,"haptics":9,"hint":10,"restart":11,"home":12,"profile":13,"shuffle":14,"sort":15,
	"settings":16,"check":17,"next":18,"listen":19,"repeat":20,"favorite":21,"search":22,"undo":23,
	"erase":24,"lock":25,"star":26,"trophy":27,"game":28,"practice":29,"story":30,"poem":31,
}
const CONTENT_RULES := [
	["动物","animal"],["fruit","fruit"],["水果","fruit"],["车","vehicle"],["船","vehicle"],
	["飞机","vehicle"],["火车","vehicle"],["地铁","vehicle"],["游戏","game"],["故事","story"],
	["诗","poem"],["数学","math"],
]
const COVER_SLOTS := {
	"jungle":0,"poetry":1,"math":2,"pinyin":3,"memory":4,"patterns":5,"animals":6,
	"gomoku":7,"chess":8,"sudoku":9,"military":10,"workbook":11,"stories":12,
}
const JUNGLE_PIECES := ["elephant","lion","tiger","leopard","wolf","dog","cat","rat"]
const AVATAR_NAMES := {
	"🦊":"小狐狸","🐼":"小熊猫","🐯":"小老虎","🐰":"小兔子","🐻":"小熊",
	"🦁":"小狮子","🐧":"小企鹅","🐨":"小考拉","🦉":"猫头鹰","🐬":"小海豚",
}
const EMOJI_ANIMALS := [
	"🐟","🐤","🦋","🐰","🐦","🐞","🐴","🐮","🐑","🐱","🐶","🐔","🦆","🐷","🐯","🐘",
	"🦁","🐼","🦌","🦢","🐝","🐠","🐻","🦊","🐺","🐿️","🐒","🦉","🦔","🐇","🐬","🐋",
	"🐳","🦈","🐧","🐻‍❄️","🦭","🦃","🕊️","🐜","🦗","🦡","🐆","🦍","🦦","🐙","🐢",
	"🦥","🐌","🐸","🐫","🦎","🦒","🦓","🐋","🦀",
]
const EMOJI_FRUITS := ["🍎","🍌","🍊","🍓","🍇","🍉","🍐","🍑","🍍","🥭","🍒","🍋","🫐","🥝","🍈","🥥"]
const EMOJI_VEHICLES := ["🚗","🚌","🚆","🚄","✈️","🚁","🚢","⛵","🚤","🚒","🚑","🚓","🚕","🚚","🚜","🏍️","🛴","🚇","🚀","🛸","🛷","🛺","🚋","🚡","🛶","⛴️","🚐","🚝","🚲"]


static func semantic_texture(name: String, _kind: String = "ui") -> Texture2D:
	var key := name.strip_edges().to_lower()
	if not SEMANTIC_SLOTS.has(key):
		return _content_texture(name)
	var cache_key := "semantic:" + key
	if cache.has(cache_key):
		return cache[cache_key]
	var path := "res://assets/original/ui/icons.svg"
	if not ResourceLoader.exists(path):
		cache[cache_key] = null
		return null
	var source: Texture2D = load(path)
	if source == null:
		cache[cache_key] = null
		return null
	var slot := int(SEMANTIC_SLOTS[key])
	var columns := 8
	var cell := Vector2(source.get_width() / float(columns), source.get_height() / 4.0)
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = Rect2(Vector2(float(slot % columns) * cell.x, float(int(slot / columns)) * cell.y), cell)
	cache[cache_key] = atlas
	return atlas


static func semantic_picture(name: String, kind: String = "ui", minimum: Vector2 = Vector2(32, 32)) -> Control:
	var texture_value := semantic_texture(name, kind)
	if texture_value != null:
		var image := TextureRect.new()
		image.texture = texture_value
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size = minimum
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		return image
	var glyph := OriginalGlyph.new()
	glyph.configure(name, name, kind, Color("#d56c29"), kind != "ui", minimum)
	return glyph


static func cover_texture(game_id: String) -> Texture2D:
	if not COVER_SLOTS.has(game_id):
		return null
	var cache_key := "illustrated-cover:" + game_id
	if cache.has(cache_key):
		return cache[cache_key]
	var illustrated_path := "res://assets/covers/" + game_id + ".webp"
	if ResourceLoader.exists(illustrated_path):
		var illustrated: Texture2D = load(illustrated_path)
		if illustrated != null:
			cache[cache_key] = illustrated
			return illustrated
	var path := "res://assets/original/covers/covers.svg"
	if not ResourceLoader.exists(path):
		cache[cache_key] = null
		return null
	var source: Texture2D = load(path)
	if source == null:
		cache[cache_key] = null
		return null
	var slot := int(COVER_SLOTS[game_id])
	var cell := Vector2(source.get_width() / 4.0, source.get_height() / 4.0)
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = Rect2(Vector2(float(slot % 4) * cell.x, float(int(slot / 4)) * cell.y), cell)
	cache[cache_key] = atlas
	return atlas


static func jungle_piece(kind: String) -> Texture2D:
	if not kind in JUNGLE_PIECES:
		return null
	var cache_key := "jungle-piece:" + kind
	if cache.has(cache_key):
		return cache[cache_key]
	var path := "res://assets/jungle/" + kind + ".webp"
	var result: Texture2D = load(path) if ResourceLoader.exists(path) else null
	cache[cache_key] = result
	return result


static func profile_picture(profile: Dictionary, minimum: Vector2 = Vector2(42, 42)) -> Control:
	var token := str(profile.get("avatar", "🦊"))
	var name := str(AVATAR_NAMES.get(token, profile.get("name", "小朋友")))
	var tint := _safe_color(str(profile.get("color", "#d56c29")))
	var glyph := OriginalGlyph.new()
	glyph.configure(name, token, "animal", tint, false, minimum)
	return glyph


static func semantic_key(value: String) -> String:
	var source := value.strip_edges().to_lower()
	for entry in CONTENT_RULES:
		if source.contains(str(entry[0])):
			return str(entry[1])
	if _contains_any(source, ["熊猫","狮子","老虎","大象","长颈鹿","猴子","兔子","松鼠","狐狸","狼","鹿","熊","企鹅","海豚","鲸","鲨鱼","章鱼","海龟","螃蟹","蜜蜂","蝴蝶","瓢虫","蚂蚁","猫","狗","马","牛","羊","鸡","鸭"]):
		return "animal"
	if _contains_any(source, ["苹果","香蕉","橙子","柚子","草莓","葡萄","西瓜","梨","桃子","菠萝","芒果","樱桃","柠檬","蓝莓","猕猴桃","火龙果","石榴","哈密瓜","椰子","木瓜","山楂","红枣","无花果","杨梅","枇杷","荔枝","龙眼","柿子","桑葚","榴莲"]):
		return "fruit"
	if _contains_any(source, ["自行车","汽车","公交车","火车","高铁","飞机","直升机","轮船","帆船","快艇","消防车","救护车","警车","出租车","卡车","拖拉机","摩托车","滑板车","地铁","热气球","火箭","飞碟","雪橇","三轮车","电车","缆车","独木舟","货船","货车","列车"]):
		return "vehicle"
	return "object"


static func content_kind(value: String) -> String:
	var source := value.strip_edges().to_lower()
	if source.begins_with("animals-"):
		return "animal"
	if source.begins_with("fruits-"):
		return "fruit"
	if source.begins_with("vehicles-"):
		return "vehicle"
	if source.begins_with("objects-"):
		return "object"
	if source in EMOJI_ANIMALS or EMOJI_ANIMALS.any(func(token): return source.contains(str(token))):
		return "animal"
	if source in EMOJI_FRUITS or EMOJI_FRUITS.any(func(token): return source.contains(str(token))):
		return "fruit"
	if source in EMOJI_VEHICLES or EMOJI_VEHICLES.any(func(token): return source.contains(str(token))):
		return "vehicle"
	return semantic_key(source)


static func _contains_any(value: String, needles: Array) -> bool:
	for needle in needles:
		if value.contains(str(needle)):
			return true
	return false


static func _safe_color(value: String) -> Color:
	return Color(value) if Color.html_is_valid(value) else Color("#d56c29")


static func _content_texture(value: String) -> Texture2D:
	var cache_key := "content:" + value
	if cache.has(cache_key):
		return cache[cache_key]
	var kind := content_kind(value)
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var hash_value := 17
	for index in value.length():
		hash_value = (hash_value * 31 + value.unicode_at(index)) % 1000003
	var accents := [
		Color("#d56c29"), Color("#2878c8"), Color("#64a244"), Color("#8657a7"),
		Color("#8ead28"), Color("#b69014"), Color("#2c6a4b"), Color("#167d74"),
	]
	var tint: Color = accents[hash_value % accents.size()]
	var soft := tint.lerp(Color.WHITE, 0.80)
	_fill_circle(image, 48, 48, 43, soft)
	match kind:
		"animal":
			_draw_animal_art(image, hash_value, tint)
		"fruit":
			_draw_fruit_art(image, value, hash_value, tint)
		"vehicle":
			_draw_vehicle_art(image, value, tint)
		"story":
			_draw_story_art(image, tint)
		"poem":
			_draw_poem_art(image, tint)
		"game":
			_draw_game_art(image, tint)
		_:
			_draw_object_art(image, value, hash_value, tint)
	var texture := ImageTexture.create_from_image(image)
	cache[cache_key] = texture
	return texture


static func _draw_animal_art(image: Image, seed: int, tint: Color) -> void:
	var ink := tint.darkened(0.35)
	var body := tint.lerp(Color.WHITE, 0.25)
	var ear_height := 14 + seed % 9
	_fill_triangle(image, Vector2i(28, 38), Vector2i(18, 38 - ear_height), Vector2i(43, 29), body)
	_fill_triangle(image, Vector2i(68, 38), Vector2i(78, 38 - ear_height), Vector2i(53, 29), body)
	_fill_circle(image, 48, 52, 27, body)
	_fill_circle(image, 38, 48, 4, ink)
	_fill_circle(image, 58, 48, 4, ink)
	_fill_triangle(image, Vector2i(44, 58), Vector2i(52, 58), Vector2i(48, 64), ink)
	if seed % 3 == 0:
		_draw_line(image, 35, 29, 39, 42, ink, 4)
		_draw_line(image, 61, 29, 57, 42, ink, 4)
	elif seed % 3 == 1:
		for index in 5:
			_fill_circle(image, 32 + index * 8, 66 + (index % 2) * 3, 2, ink)


static func _draw_fruit_art(image: Image, value: String, seed: int, tint: Color) -> void:
	var body := tint.lerp(Color.WHITE, 0.08)
	if value.contains("香蕉"):
		for index in 7:
			_fill_circle(image, 30 + index * 6, 58 - int(sin(float(index) / 6.0 * PI) * 25.0), 8, body)
	else:
		_fill_circle(image, 48, 55, 31, body)
		if _contains_any(value, ["菠萝","榴莲","杨梅"]):
			for index in 12:
				var angle := TAU * float(index) / 12.0
				_draw_line(image, int(48 + cos(angle) * 29.0), int(55 + sin(angle) * 29.0), int(48 + cos(angle) * 39.0), int(55 + sin(angle) * 39.0), tint.darkened(0.25), 3)
		if value.contains("西瓜"):
			_draw_line(image, 20, 55, 76, 55, Color("#4f8f47"), 5)
			for index in 7:
				_fill_circle(image, 27 + index * 7, 62 + (index % 2) * 7, 2, Color("#47321f"))
	_draw_line(image, 48, 24, 52, 14, Color("#4f8f47"), 5)
	_fill_triangle(image, Vector2i(52, 18), Vector2i(73, 14), Vector2i(60, 28), Color("#64a244"))
	_fill_circle(image, seed % 2 + 31, 46, 5, Color(1, 1, 1, 0.42))


static func _draw_vehicle_art(image: Image, value: String, tint: Color) -> void:
	var body := tint.lerp(Color.WHITE, 0.14)
	var ink := tint.darkened(0.42)
	if _contains_any(value, ["船","艇","舟"]):
		_fill_polygon(image, PackedVector2Array([Vector2(15, 55), Vector2(81, 55), Vector2(69, 76), Vector2(27, 76)]), body)
		_draw_line(image, 48, 54, 48, 21, ink, 4)
		_fill_triangle(image, Vector2i(50, 24), Vector2i(72, 52), Vector2i(50, 52), Color("#fff3c7"))
	elif _contains_any(value, ["飞机","火箭","飞碟"]):
		_fill_polygon(image, PackedVector2Array([Vector2(12, 50), Vector2(78, 40), Vector2(57, 58), Vector2(19, 64)]), body)
		_fill_triangle(image, Vector2i(34, 48), Vector2i(56, 18), Vector2i(62, 48), softish(body))
	else:
		_fill_rect(image, 17, 40, 62, 28, body)
		_fill_rect(image, 31, 27, 33, 22, body)
		_fill_rect(image, 37, 31, 20, 12, Color("#d8f0f6"))
		_fill_circle(image, 31, 73, 9, ink)
		_fill_circle(image, 66, 73, 9, ink)


static func _draw_object_art(image: Image, value: String, seed: int, tint: Color) -> void:
	var body := tint.lerp(Color.WHITE, 0.72)
	var soft := tint.lerp(Color.WHITE, 0.80)
	var ink := tint.darkened(0.25)
	_fill_rect(image, 23, 25, 50, 52, body)
	_fill_rect(image, 25, 27, 46, 48, Color(1, 1, 1, 0.32))
	if _contains_any(value, ["书","本"]):
		_draw_line(image, 36, 27, 36, 77, ink, 4)
		_draw_line(image, 42, 40, 62, 40, ink, 3)
		_draw_line(image, 42, 50, 62, 50, ink, 3)
	elif _contains_any(value, ["笔","尺"]):
		_draw_line(image, 31, 70, 67, 34, ink, 5)
	elif _contains_any(value, ["杯","碗","锅"]):
		_fill_polygon(image, PackedVector2Array([Vector2(30, 34), Vector2(66, 34), Vector2(60, 72), Vector2(36, 72)]), body)
	elif _contains_any(value, ["房子","家"]):
		_fill_triangle(image, Vector2i(17, 43), Vector2i(48, 18), Vector2i(79, 43), tint)
		_fill_rect(image, 25, 43, 46, 36, body)
	elif _contains_any(value, ["伞"]):
		_fill_triangle(image, Vector2i(17, 45), Vector2i(48, 18), Vector2i(79, 45), tint)
		_draw_line(image, 48, 45, 48, 79, ink, 4)
	elif _contains_any(value, ["月"]):
		_fill_circle(image, 50, 48, 26, Color("#f1c851"))
		_fill_circle(image, 64, 40, 24, soft)
	elif _contains_any(value, ["树","林"]):
		_fill_rect(image, 43, 44, 10, 36, ink)
		_fill_circle(image, 38, 38, 19, Color("#6fa45a"))
		_fill_circle(image, 58, 36, 20, Color("#78af61"))
		_fill_circle(image, 49, 25, 16, Color("#87bd6c"))
	elif _contains_any(value, ["山"]):
		_fill_triangle(image, Vector2i(14, 74), Vector2i(40, 35), Vector2i(59, 74), Color("#7791a8"))
		_fill_triangle(image, Vector2i(37, 74), Vector2i(63, 23), Vector2i(84, 74), Color("#617d94"))
	else:
		var arm := 13 + seed % 8
		_draw_line(image, 48 - arm, 48, 48 + arm, 48, ink, 5)
		_draw_line(image, 48, 48 - arm, 48, 48 + arm, ink, 5)


static func _draw_story_art(image: Image, tint: Color) -> void:
	var paper := Color("#fff7df")
	_fill_rect(image, 18, 26, 30, 46, paper)
	_fill_rect(image, 48, 26, 30, 46, paper)
	_draw_line(image, 48, 26, 48, 72, tint.darkened(0.2), 4)
	for row in 4:
		_draw_line(image, 24, 37 + row * 8, 42, 37 + row * 8, tint.darkened(0.1), 2)
		_draw_line(image, 54, 37 + row * 8, 72, 37 + row * 8, tint.darkened(0.1), 2)


static func _draw_poem_art(image: Image, tint: Color) -> void:
	_fill_rect(image, 24, 18, 48, 60, Color("#fff6df"))
	_fill_circle(image, 24, 24, 7, Color("#a65f3e"))
	_fill_circle(image, 24, 72, 7, Color("#a65f3e"))
	for row in 4:
		_draw_line(image, 35, 31 + row * 10, 63, 31 + row * 10, tint.darkened(0.2), 2)


static func _draw_game_art(image: Image, tint: Color) -> void:
	_fill_rect(image, 18, 24, 60, 48, Color("#fff4d7"))
	for index in range(1, 4):
		_draw_line(image, 18, 24 + index * 12, 78, 24 + index * 12, tint.darkened(0.25), 2)
		_draw_line(image, 18 + index * 15, 24, 18 + index * 15, 72, tint.darkened(0.25), 2)
	_fill_circle(image, 33, 30, 7, tint)
	_fill_circle(image, 63, 66, 7, tint.darkened(0.25))


static func softish(value: Color) -> Color:
	return value.lerp(Color.WHITE, 0.42)


static func _fill_rect(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	for py in range(maxi(0, y), mini(image.get_height(), y + height)):
		for px in range(maxi(0, x), mini(image.get_width(), x + width)):
			image.set_pixel(px, py, color)


static func _fill_circle(image: Image, center_x: int, center_y: int, radius: int, color: Color) -> void:
	var radius_squared := radius * radius
	for py in range(maxi(0, center_y - radius), mini(image.get_height(), center_y + radius + 1)):
		for px in range(maxi(0, center_x - radius), mini(image.get_width(), center_x + radius + 1)):
			var dx := px - center_x
			var dy := py - center_y
			if dx * dx + dy * dy <= radius_squared:
				image.set_pixel(px, py, color)


static func _draw_line(image: Image, x0: int, y0: int, x1: int, y1: int, color: Color, width: int = 1) -> void:
	var dx := absi(x1 - x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var error := dx + dy
	while true:
		_fill_circle(image, x0, y0, maxi(1, int(width / 2.0)), color)
		if x0 == x1 and y0 == y1:
			break
		var twice := 2 * error
		if twice >= dy:
			error += dy
			x0 += sx
		if twice <= dx:
			error += dx
			y0 += sy


static func _fill_triangle(image: Image, a: Vector2i, b: Vector2i, c: Vector2i, color: Color) -> void:
	var min_x := maxi(0, mini(a.x, mini(b.x, c.x)))
	var max_x := mini(image.get_width() - 1, maxi(a.x, maxi(b.x, c.x)))
	var min_y := maxi(0, mini(a.y, mini(b.y, c.y)))
	var max_y := mini(image.get_height() - 1, maxi(a.y, maxi(b.y, c.y)))
	for py in range(min_y, max_y + 1):
		for px in range(min_x, max_x + 1):
			var first := (b.x - a.x) * (py - a.y) - (b.y - a.y) * (px - a.x)
			var second := (c.x - b.x) * (py - b.y) - (c.y - b.y) * (px - b.x)
			var third := (a.x - c.x) * (py - c.y) - (a.y - c.y) * (px - c.x)
			if (first >= 0 and second >= 0 and third >= 0) or (first <= 0 and second <= 0 and third <= 0):
				image.set_pixel(px, py, color)


static func _fill_polygon(image: Image, points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	for point_index in range(1, points.size() - 1):
		_fill_triangle(
			image,
			Vector2i(roundi(points[0].x), roundi(points[0].y)),
			Vector2i(roundi(points[point_index].x), roundi(points[point_index].y)),
			Vector2i(roundi(points[point_index + 1].x), roundi(points[point_index + 1].y)),
			color
		)


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
