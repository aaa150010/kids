extends Node

signal changed
signal save_failed(message: String)

const SAVE_PATH := "user://save-v1.json"
const BACKUP_PATH := "user://save-v1.backup.json"
const TEMP_SUFFIX := ".tmp"
const STORE_SCHEMA_VERSION := 2
const MAX_PROFILES := 8

var data: Dictionary = {}
var contexts: Dictionary = {}
var last_save_ok := true
var last_save_error := ""
var _primary_was_valid := false
var _save_path := SAVE_PATH
var _backup_path := BACKUP_PATH
var _flush_pending := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	var override_path := OS.get_environment("KIDS_PLAYGROUND_SAVE_PATH").strip_edges()
	if not override_path.is_empty() and override_path.begins_with("user://"):
		_save_path = override_path
		_backup_path = override_path + ".backup"
	data = _default_data() if OS.get_environment("KIDS_PLAYGROUND_AUDIT") == "1" else _load()


func _notification(what: int) -> void:
	if what in [
		NOTIFICATION_APPLICATION_FOCUS_OUT,
		NOTIFICATION_APPLICATION_PAUSED,
		NOTIFICATION_WM_CLOSE_REQUEST,
	]:
		flush()


func _default_data() -> Dictionary:
	return {
		"schemaVersion": STORE_SCHEMA_VERSION,
		"profiles": [],
		"settings": {
			"soundOn": true,
			"musicOn": true,
			"speechOn": true,
			"hapticsOn": true,
			"sfxVolume": 1.0,
			"musicVolume": 1.0,
			"speechVolume": 0.72,
		},
		"selections": {},
		"lobbyOrder": [],
		"gameSaves": {},
		"progress": {},
		"records": {},
		"sessionSaves": {},
		"sessionProgress": {},
		"learning": {},
		"recordedSessions": {},
		"difficulty": {},
	}


func _load() -> Dictionary:
	var primary: Variant = _read_json(_save_path)
	if _valid_envelope(primary):
		_primary_was_valid = _sections_are_typed(primary)
		if not _primary_was_valid:
			push_warning("存档部分内容损坏，已按可恢复部分载入，并保留现有备份。")
		return _normalize(primary)
	_primary_was_valid = false
	for path in [_save_path + TEMP_SUFFIX, _backup_path]:
		var recovered: Variant = _read_json(path)
		if _valid_envelope(recovered):
			push_warning("存档主文件不可用，已从 %s 恢复。" % path)
			return _normalize(recovered)
	return _default_data()


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	return parser.data


func _valid_envelope(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var source: Dictionary = value
	var schema := int(source.get("schemaVersion", -1))
	return schema in [1, STORE_SCHEMA_VERSION]


func _sections_are_typed(source: Dictionary) -> bool:
	var expected := {
		"profiles": TYPE_ARRAY,
		"settings": TYPE_DICTIONARY,
		"selections": TYPE_DICTIONARY,
		"lobbyOrder": TYPE_ARRAY,
		"gameSaves": TYPE_DICTIONARY,
		"progress": TYPE_DICTIONARY,
		"records": TYPE_DICTIONARY,
		"sessionSaves": TYPE_DICTIONARY,
		"sessionProgress": TYPE_DICTIONARY,
		"learning": TYPE_DICTIONARY,
		"recordedSessions": TYPE_DICTIONARY,
		"difficulty": TYPE_DICTIONARY,
	}
	for key in expected:
		if source.has(key) and typeof(source[key]) != int(expected[key]):
			return false
	return true


func _normalize(source: Dictionary) -> Dictionary:
	var result := _default_data()
	result.schemaVersion = STORE_SCHEMA_VERSION
	var source_settings: Variant = source.get("settings", {})
	if source_settings is Dictionary:
		for key in ["soundOn", "musicOn", "speechOn", "hapticsOn"]:
			if source_settings.get(key) is bool:
				result.settings[key] = bool(source_settings[key])
		for key in ["sfxVolume", "musicVolume", "speechVolume"]:
			var value: Variant = source_settings.get(key, result.settings[key])
			var fallback := 0.72 if key == "speechVolume" else 1.0
			result.settings[key] = clampf(float(value), 0.0, 1.0) if (value is float or value is int) and is_finite(float(value)) else fallback
	var source_order: Variant = source.get("lobbyOrder", [])
	if source_order is Array:
		result.lobbyOrder = source_order.filter(func(id): return id is String)
	var source_profiles: Variant = source.get("profiles", [])
	if source_profiles is Array:
		for item in source_profiles:
			if not item is Dictionary or result.profiles.size() >= MAX_PROFILES:
				continue
			var profile := _normalize_profile(item)
			if profile.is_empty() or result.profiles.any(func(existing): return str(existing.get("id", "")) == str(profile.id)):
				continue
			result.profiles.append(profile)
	var valid_ids: Array = result.profiles.map(func(profile): return profile.id)
	var source_selections: Variant = source.get("selections", {})
	if source_selections is Dictionary:
		for game_id in source_selections:
			var ids: Variant = source_selections[game_id]
			if ids is Array:
				result.selections[game_id] = ids.filter(func(id): return id in valid_ids).slice(0, 4)
	var source_game_saves: Variant = source.get("gameSaves", {})
	if source_game_saves is Dictionary:
		for game_id in source_game_saves:
			var saves: Variant = source_game_saves[game_id]
			if not saves is Dictionary:
				continue
			result.gameSaves[game_id] = {}
			for profile_id in saves:
				if profile_id in valid_ids and saves[profile_id] is Dictionary:
					result.gameSaves[game_id][profile_id] = saves[profile_id].duplicate(true)
	var source_progress: Variant = source.get("progress", {})
	if source_progress is Dictionary:
		for game_id in source_progress:
			if source_progress[game_id] is Dictionary:
				result.progress[game_id] = source_progress[game_id].duplicate(true)
	var source_records: Variant = source.get("records", {})
	if source_records is Dictionary:
		for profile_id in source_records:
			if profile_id in valid_ids and source_records[profile_id] is Dictionary:
				result.records[profile_id] = _normalize_record(source_records[profile_id])
	var source_sessions: Variant = source.get("sessionSaves", {})
	if source_sessions is Dictionary:
		for game_id in source_sessions:
			var entries: Variant = source_sessions[game_id]
			if not entries is Dictionary:
				continue
			result.sessionSaves[game_id] = {}
			for session_key in entries:
				if entries[session_key] is Dictionary:
					result.sessionSaves[game_id][str(session_key)] = entries[session_key].duplicate(true)
	var source_session_progress: Variant = source.get("sessionProgress", {})
	if source_session_progress is Dictionary:
		for progress_key in source_session_progress:
			if source_session_progress[progress_key] is Dictionary:
				result.sessionProgress[str(progress_key)] = source_session_progress[progress_key].duplicate(true)
	var source_learning: Variant = source.get("learning", {})
	if source_learning is Dictionary:
		for profile_id in source_learning:
			if not (profile_id in valid_ids) or not source_learning[profile_id] is Dictionary:
				continue
			result.learning[profile_id] = {}
			for learning_key in source_learning[profile_id]:
				var learning_value: Variant = source_learning[profile_id][learning_key]
				if learning_value is Dictionary:
					result.learning[profile_id][str(learning_key)] = learning_value.duplicate(true)
	var source_recorded: Variant = source.get("recordedSessions", {})
	if source_recorded is Dictionary:
		for profile_id in source_recorded:
			if not (profile_id in valid_ids) or not source_recorded[profile_id] is Dictionary:
				continue
			result.recordedSessions[profile_id] = {}
			for session_id in source_recorded[profile_id]:
				result.recordedSessions[profile_id][str(session_id)] = bool(source_recorded[profile_id][session_id])
	var source_difficulty: Variant = source.get("difficulty", {})
	if source_difficulty is Dictionary:
		for game_id in source_difficulty:
			if not source_difficulty[game_id] is Dictionary:
				continue
			result.difficulty[game_id] = {}
			for profile_id in source_difficulty[game_id]:
				if profile_id in valid_ids:
					var difficulty_value := GameTuning.normalize(source_difficulty[game_id][profile_id])
					if difficulty_value != "auto":
						result.difficulty[game_id][profile_id] = difficulty_value
	var clean_sessions := {}
	for game_id in result.sessionSaves:
		var entries_value: Variant = result.sessionSaves.get(game_id, {})
		if not entries_value is Dictionary:
			continue
		var entries: Dictionary = entries_value
		clean_sessions[game_id] = {}
		for session_key in entries:
			if not (entries[session_key] is Dictionary):
				continue
			var entry: Dictionary = (entries[session_key] as Dictionary).duplicate(true)
			var participants := _participants(entry)
			if participants.is_empty():
				continue
			var archived_ids: Array = entry.get("archivedProfileIds", []) if entry.get("archivedProfileIds") is Array else []
			var invalid_ids := participants.filter(func(id): return not (str(id) in valid_ids))
			if not invalid_ids.is_empty() and invalid_ids.any(func(id): return not (str(id) in archived_ids)):
				continue
			clean_sessions[game_id][session_key] = entry
	result.sessionSaves = clean_sessions
	var clean_progress := {}
	for progress_key in result.sessionProgress:
		var meta: Variant = result.sessionProgress[progress_key]
		if not meta is Dictionary:
			continue
		var meta_dict: Dictionary = meta
		var game_id := str(meta_dict.get("gameId", ""))
		var session_key := str(meta_dict.get("sessionKey", ""))
		if not clean_sessions.get(game_id, {}).has(session_key):
			continue
		meta_dict.participantIds = meta_dict.get("participantIds", []).filter(func(id): return str(id) in valid_ids)
		clean_progress[progress_key] = meta_dict
	result.sessionProgress = clean_progress
	return result


func _normalize_profile(source: Dictionary) -> Dictionary:
	var age := int(source.get("age", 0))
	var profile_id := str(source.get("id", "")).strip_edges()
	var name := str(source.get("name", "")).strip_edges()
	if profile_id.is_empty() or name.is_empty() or age < 4 or age > 12:
		return {}
	return {
		"id": profile_id,
		"name": name.left(12),
		"age": age,
		"avatar": str(source.get("avatar", "🦊")),
		"color": str(source.get("color", "#d56c29")),
	}


func _normalize_record(source: Dictionary) -> Dictionary:
	var games := {}
	var source_games: Variant = source.get("games", {})
	if source_games is Dictionary:
		for game_id in source_games:
			var entry: Variant = source_games[game_id]
			if not entry is Dictionary:
				continue
			games[str(game_id)] = {
				"plays": maxi(0, int(entry.get("plays", 0))),
				"wins": maxi(0, int(entry.get("wins", 0))),
				"draws": maxi(0, int(entry.get("draws", 0))),
				"losses": maxi(0, int(entry.get("losses", 0))),
				"correct": maxi(0, int(entry.get("correct", 0))),
				"answered": maxi(0, int(entry.get("answered", 0))),
				"bestScore": maxi(0, int(entry.get("bestScore", 0))),
				"lastPlayedAt": maxi(0, int(entry.get("lastPlayedAt", 0))),
				"lastOutcome": str(entry.get("lastOutcome", "played")),
			}
	var skills := {}
	var source_skills: Variant = source.get("skills", {})
	if source_skills is Dictionary:
		for axis in source_skills:
			var entry: Variant = source_skills[axis]
			if entry is Dictionary:
				skills[str(axis)] = {
					"correct": maxi(0, int(entry.get("correct", 0))),
					"answered": maxi(0, int(entry.get("answered", 0))),
				}
	var sessions: Array = []
	var source_sessions: Variant = source.get("sessions", [])
	if source_sessions is Array:
		for entry in source_sessions:
			if entry is Dictionary:
				sessions.append(entry.duplicate(true))
			if sessions.size() >= 40:
				break
	return {
		"games": games,
		"skills": skills,
		"sessions": sessions,
	}


func flush() -> bool:
	_flush_pending = false
	if OS.get_environment("KIDS_PLAYGROUND_AUDIT") == "1":
		last_save_ok = true
		last_save_error = ""
		return true
	if data.is_empty():
		last_save_ok = false
		last_save_error = "存档尚未初始化"
		save_failed.emit(last_save_error)
		return false
	data.schemaVersion = STORE_SCHEMA_VERSION
	if not _sections_are_typed(data):
		last_save_ok = false
		last_save_error = "存档内容格式异常"
		push_error(last_save_error)
		save_failed.emit(last_save_error)
		return false
	var text := JSON.stringify(data, "\t")
	var temporary := _save_path + TEMP_SUFFIX
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_save_ok = false
		last_save_error = "无法打开存档临时文件"
		push_warning("自动保存未完成：%s" % last_save_error)
		save_failed.emit(last_save_error)
		return false
	file.store_string(text)
	file.flush()
	file.close()
	# 只有确认主文件原本有效时才轮换备份，避免用损坏文件覆盖最后一个好备份。
	if _primary_was_valid and FileAccess.file_exists(_save_path):
		var backup_tmp := _backup_path + TEMP_SUFFIX
		if FileAccess.file_exists(backup_tmp):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_tmp))
		var copy_error := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(_save_path),
			ProjectSettings.globalize_path(backup_tmp)
		)
		if copy_error == OK:
			if FileAccess.file_exists(_backup_path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(_backup_path))
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(backup_tmp),
				ProjectSettings.globalize_path(_backup_path)
			)
	var error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary),
		ProjectSettings.globalize_path(_save_path)
	)
	if error != OK:
		last_save_ok = false
		last_save_error = "存档替换失败，已保留临时文件供下次恢复"
		push_warning("自动保存未完成：%s" % last_save_error)
		save_failed.emit(last_save_error)
		return false
	_primary_was_valid = true
	last_save_ok = true
	last_save_error = ""
	return true


func _request_flush() -> void:
	if _flush_pending:
		return
	_flush_pending = true
	call_deferred("_flush_deferred")


func _flush_deferred() -> void:
	if not _flush_pending:
		return
	flush()


func save_status_text() -> String:
	return "已保存" if last_save_ok else "等待重试：%s" % last_save_error


func storage_paths() -> Dictionary:
	return {"save": _save_path, "backup": _backup_path}


func profiles() -> Array:
	return data.get("profiles", [])


func add_profile(name: String, age: int, avatar: String = "🦊", tint: String = "#d56c29") -> Dictionary:
	if profiles().size() >= MAX_PROFILES:
		return {}
	var profile := _normalize_profile({
		"id": "%s-%s" % [Time.get_unix_time_from_system(), randi()],
		"name": name,
		"age": age,
		"avatar": avatar,
		"color": tint,
	})
	if profile.is_empty():
		return {}
	data.profiles.append(profile)
	records_for(profile.id)
	flush()
	changed.emit()
	return profile


func update_profile(profile_id: String, name: String, age: int, avatar: String, tint: String) -> bool:
	for index in data.profiles.size():
		if data.profiles[index].id != profile_id:
			continue
		var next := _normalize_profile({
			"id": profile_id,
			"name": name,
			"age": age,
			"avatar": avatar,
			"color": tint,
		})
		if next.is_empty():
			return false
		data.profiles[index] = next
		flush()
		changed.emit()
		return true
	return false


func delete_profile(profile_id: String) -> void:
	data.profiles = data.profiles.filter(func(profile): return profile.id != profile_id)
	for game_id in data.selections:
		data.selections[game_id] = data.selections[game_id].filter(func(id): return id != profile_id)
	for game_id in data.gameSaves:
		data.gameSaves[game_id].erase(profile_id)
	data.records.erase(profile_id)
	data.learning.erase(profile_id)
	data.recordedSessions.erase(profile_id)
	for game_id in data.difficulty:
		data.difficulty[game_id].erase(profile_id)
	for game in data.sessionSaves:
		for key in data.sessionSaves[game].keys():
			var entry: Dictionary = data.sessionSaves[game][key]
			var participants := _participants(entry)
			if not (profile_id in participants):
				continue
			if participants.size() <= 1:
				data.sessionSaves[game].erase(key)
				data.sessionProgress.erase(str(game) + ":" + str(key))
			else:
				# 共享局属于多个孩子，删除一位档案时只归档，不静默清除另一位孩子的数据。
				var archived: Array = entry.get("archivedProfileIds", [])
				if not (profile_id in archived):
					archived.append(profile_id)
				entry.archivedProfileIds = archived
				entry.archivedAt = Time.get_unix_time_from_system()
				data.sessionSaves[game][key] = entry
				data.sessionProgress.erase(str(game) + ":" + str(key))
	flush()
	changed.emit()


func profile(profile_id: String) -> Dictionary:
	for item in profiles():
		if item.id == profile_id:
			return item
	return {}


func selected_profiles(game_id: String, minimum: int = 1, maximum: int = 2) -> Array:
	var ids: Array = data.selections.get(game_id, [])
	var selected: Array = []
	for profile_id in ids:
		var item := profile(profile_id)
		if not item.is_empty():
			selected.append(item)
	if selected.is_empty():
		selected = profiles().slice(0, minimum)
	elif selected.size() > maximum:
		selected = selected.slice(0, maximum)
	if selected.is_empty() and minimum > 0:
		return []
	return selected


func select_profiles(game_id: String, ids: Array) -> void:
	data.selections[game_id] = ids.duplicate()
	flush()
	changed.emit()


func primary_id(game_id: String) -> String:
	var selected := selected_profiles(game_id)
	return selected[0].id if not selected.is_empty() else ""


func save_state(game_id: String, profile_id: String, state: Dictionary, note: String = "", resume: bool = true) -> void:
	if profile_id.is_empty():
		return
	var context: Dictionary = contexts.get(game_id, {})
	var mode_id := str(state.get("modeId", context.get("modeId", "classic")))
	var ids := _participants(state)
	if ids.is_empty():
		ids = context.get("ids", [profile_id]).duplicate()
	var key := _session_key(mode_id, ids)
	if not data.sessionSaves.has(game_id):
		data.sessionSaves[game_id] = {}
	var snapshot := state.duplicate(true)
	snapshot.modeId = mode_id
	snapshot.participantIds = ids
	snapshot.resume = resume
	snapshot.saveFormat = STORE_SCHEMA_VERSION
	snapshot.savedAt = Time.get_unix_time_from_system()
	if not snapshot.has("gameId"):
		snapshot.gameId = game_id
	data.sessionSaves[game_id][key] = snapshot
	var meta := {
		"gameId": game_id,
		"modeId": mode_id,
		"participantIds": ids,
		"sessionKey": key,
		"lastPlayedAt": Time.get_unix_time_from_system(),
		"note": note,
		"resume": resume,
		"levelId": int(state.get("levelId", 1)),
		"phase": str(state.get("phase", "")),
		"difficulty": str(state.get("difficulty", "")),
	}
	data.progress[game_id] = meta
	data.sessionProgress[game_id + ":" + key] = meta
	_request_flush()
	changed.emit()


func load_state(game_id: String, profile_ids: Array) -> Dictionary:
	var mode_id := str(contexts.get(game_id, {}).get("modeId", "classic"))
	var key := _session_key(mode_id, profile_ids)
	var saved: Variant = data.sessionSaves.get(game_id, {}).get(key)
	if saved is Dictionary and _snapshot_matches(game_id, mode_id, profile_ids, saved):
		return saved.duplicate(true)
	if mode_id != "classic":
		return {}
	var saves: Dictionary = data.gameSaves.get(game_id, {})
	for profile_id in profile_ids:
		if saves.get(profile_id) is Dictionary:
			var legacy: Dictionary = saves[profile_id]
			var ids := _participants(legacy)
			if _session_key(mode_id, ids) == key or (ids.is_empty() and profile_ids.size() == 1):
				return legacy.duplicate(true)
	return {}


func _snapshot_matches(game_id: String, mode_id: String, profile_ids: Array, snapshot: Dictionary) -> bool:
	if snapshot.get("archivedProfileIds") is Array and not snapshot.archivedProfileIds.is_empty():
		return false
	if snapshot.has("gameId") and str(snapshot.gameId) != game_id:
		return false
	if str(snapshot.get("modeId", mode_id)) != mode_id:
		return false
	var participants := _participants(snapshot)
	if participants.is_empty():
		return false
	var ordered_expected := profile_ids.duplicate()
	ordered_expected.sort()
	var ordered_actual := participants.duplicate()
	ordered_actual.sort()
	return ordered_actual == ordered_expected


func clear_state(game_id: String, profile_id: String) -> void:
	var context: Dictionary = contexts.get(game_id, {})
	var key := _session_key(str(context.get("modeId", "classic")), context.get("ids", [profile_id]))
	if data.sessionSaves.get(game_id) is Dictionary:
		data.sessionSaves[game_id].erase(key)
	data.sessionProgress.erase(game_id + ":" + key)
	if str(context.get("modeId", "classic")) == "classic" and data.gameSaves.get(game_id) is Dictionary:
		data.gameSaves[game_id].erase(profile_id)
	data.progress[game_id] = {
		"lastPlayedAt": Time.get_unix_time_from_system(),
		"note": "",
		"resume": false,
	}
	flush()
	changed.emit()


func progress(game_id: String) -> Dictionary:
	return data.progress.get(game_id, {})


func all_progress() -> Dictionary:
	return data.progress


func settings() -> Dictionary:
	return data.settings


func set_setting(key: String, value: Variant, persist: bool = true) -> void:
	data.settings[key] = value
	changed.emit()
	if persist:
		flush()


func difficulty(game_id: String, profile_id: String) -> String:
	return GameTuning.normalize(data.get("difficulty", {}).get(game_id, {}).get(profile_id, "auto"))


func set_difficulty(game_id: String, profile_id: String, value: String) -> void:
	if profile_id.is_empty():
		return
	if not data.has("difficulty"):
		data.difficulty = {}
	if not data.difficulty.has(game_id):
		data.difficulty[game_id] = {}
	var normalized := GameTuning.normalize(value)
	if normalized == "auto":
		data.difficulty[game_id].erase(profile_id)
	else:
		data.difficulty[game_id][profile_id] = normalized
	flush()
	changed.emit()


func lobby_order(defaults: Array) -> Array[String]:
	var saved: Array = data.get("lobbyOrder", [])
	var result: Array[String] = []
	for id in saved:
		if id in defaults and not (id in result):
			result.append(str(id))
	var content := get_tree().root.get_node_or_null("/root/ContentDB")
	for id in defaults:
		if id in result:
			continue
		var group := "games"
		if content != null:
			group = str(content.game(str(id)).get("group", "games"))
		var insertion := result.size()
		var found_group := false
		for index in range(result.size() - 1, -1, -1):
			var prior_group := "games"
			if content != null:
				prior_group = str(content.game(str(result[index])).get("group", "games"))
			if prior_group == group:
				insertion = index + 1
				found_group = true
				break
		if not found_group and group == "games":
			for index in result.size():
				var prior_group := "games"
				if content != null:
					prior_group = str(content.game(str(result[index])).get("group", "games"))
				if prior_group != "games":
					insertion = index
					break
		result.insert(insertion, str(id))
	return result


func set_lobby_order(order: Array) -> void:
	data.lobbyOrder = order.duplicate()
	flush()
	changed.emit()


func records_for(profile_id: String) -> Dictionary:
	if not data.records.has(profile_id) or not data.records[profile_id] is Dictionary:
		data.records[profile_id] = {
			"games": {},
			"skills": {},
			"sessions": [],
		}
	var record: Dictionary = data.records[profile_id]
	if not record.get("games") is Dictionary:
		record.games = {}
	if not record.get("skills") is Dictionary:
		record.skills = {}
	if not record.get("sessions") is Array:
		record.sessions = []
	data.records[profile_id] = record
	return record


func record_outcome(
	profile_id: String,
	game_id: String,
	outcome: String,
	score: int,
	correct: int = 0,
	answered: int = 0,
	skills: Dictionary = {},
	session_id: String = ""
) -> bool:
	var records_before: Dictionary = data.records.duplicate(true)
	var recorded_before: Dictionary = data.recordedSessions.duplicate(true)
	if not session_id.is_empty():
		if not data.recordedSessions.has(profile_id) or not data.recordedSessions[profile_id] is Dictionary:
			data.recordedSessions[profile_id] = {}
		if data.recordedSessions[profile_id].has(session_id):
			return true
		data.recordedSessions[profile_id][session_id] = true
	var record := records_for(profile_id)
	var game_value: Variant = record.games.get(game_id, {})
	var game: Dictionary = game_value if game_value is Dictionary else {}
	if game.is_empty():
		game = {
		"plays": 0,
		"wins": 0,
		"draws": 0,
		"losses": 0,
		"correct": 0,
		"answered": 0,
		"bestScore": 0,
		"lastPlayedAt": 0,
		"lastOutcome": "played",
		}
	game.plays = int(game.plays) + 1
	game.wins = int(game.wins) + (1 if outcome == "win" else 0)
	game.draws = int(game.draws) + (1 if outcome == "draw" else 0)
	game.losses = int(game.losses) + (1 if outcome == "loss" else 0)
	game.correct = int(game.correct) + correct
	game.answered = int(game.answered) + answered
	game.bestScore = maxi(int(game.bestScore), score)
	game.lastPlayedAt = Time.get_unix_time_from_system()
	game.lastOutcome = outcome
	record.games[game_id] = game
	for axis in skills:
		if not skills[axis] is Dictionary:
			continue
		var current_value: Variant = record.skills.get(axis, {"correct": 0, "answered": 0})
		var current: Dictionary = current_value if current_value is Dictionary else {"correct": 0, "answered": 0}
		current.correct = int(current.get("correct", 0)) + int(skills[axis].get("correct", 0))
		current.answered = int(current.get("answered", 0)) + int(skills[axis].get("answered", 0))
		record.skills[axis] = current
	record.sessions.push_front({
		"gameId": game_id,
		"playedAt": Time.get_unix_time_from_system(),
		"outcome": outcome,
		"score": score,
		"correct": correct,
		"answered": answered,
	})
	record.sessions = record.sessions.slice(0, 40)
	if not flush():
		data.records = records_before
		data.recordedSessions = recorded_before
		changed.emit()
		return false
	changed.emit()
	return true


func set_context(game_id: String, mode_id: String, player_ids: Array) -> void:
	contexts[game_id] = {"modeId":mode_id,"ids":player_ids.duplicate()}


func _participants(value: Dictionary) -> Array:
	if value.get("participantIds") is Array:
		return value.participantIds.duplicate()
	if value.get("players") is Array:
		return value.players.filter(func(player): return player is Dictionary and player.has("id")).map(func(player): return str(player.id))
	if value.get("player") is Dictionary:
		return [str(value.player.get("id", ""))]
	if value.get("battle") is Dictionary and value.battle.get("player") is Dictionary:
		return [str(value.battle.player.get("id", ""))]
	return []


func _session_key(mode_id: String, ids: Array) -> String:
	var ordered := ids.duplicate()
	ordered.sort()
	return JSON.stringify([mode_id, ordered])


func resumable_sessions() -> Array:
	var result: Array = []
	for entry in data.sessionProgress.values():
		if entry is Dictionary and bool(entry.get("resume", false)):
			var game_id := str(entry.get("gameId", ""))
			var session_key := str(entry.get("sessionKey", ""))
			var snapshot: Variant = data.sessionSaves.get(game_id, {}).get(session_key)
			if not snapshot is Dictionary:
				continue
			if snapshot.get("archivedProfileIds") is Array and not snapshot.archivedProfileIds.is_empty():
				continue
			var valid := true
			for profile_id in entry.get("participantIds", []):
				if profile(str(profile_id)).is_empty():
					valid = false
					break
			if valid:
				result.append(entry.duplicate(true))
	for game_id in data.progress:
		var entry: Dictionary = data.progress[game_id]
		if not entry.has("sessionKey") and bool(entry.get("resume", false)):
			var legacy_saves: Dictionary = data.gameSaves.get(game_id, {})
			if legacy_saves.is_empty():
				continue
			var legacy_ids: Array = data.selections.get(game_id, [])
			if legacy_ids.is_empty() or legacy_ids.any(func(id): return profile(str(id)).is_empty()):
				continue
			var legacy := entry.duplicate(true)
			legacy.gameId = game_id
			legacy.modeId = "classic"
			legacy.participantIds = data.selections.get(game_id, []).duplicate()
			result.append(legacy)
	result.sort_custom(func(first, second): return float(first.get("lastPlayedAt", 0)) > float(second.get("lastPlayedAt", 0)))
	return result


func shared_sessions_for(profile_id: String) -> Array:
	var result: Array = []
	for game_id in data.sessionSaves:
		var entries: Dictionary = data.sessionSaves.get(game_id, {})
		for session_key in entries:
			var snapshot: Variant = entries[session_key]
			if not snapshot is Dictionary:
				continue
			var participants := _participants(snapshot)
			if profile_id in participants and participants.size() > 1:
				var archived: Array = snapshot.get("archivedProfileIds", []) if snapshot.get("archivedProfileIds") is Array else []
				if profile_id in archived:
					continue
				result.append({
					"gameId": game_id,
					"modeId": str(snapshot.get("modeId", "classic")),
					"sessionKey": session_key,
					"participantIds": participants.duplicate(),
				})
	return result


func learning(profile_id: String, game_id: String, mode_id: String = "classic") -> Dictionary:
	if not data.learning.has(profile_id) or not data.learning[profile_id] is Dictionary:
		data.learning[profile_id] = {}
	var key := game_id + ":" + mode_id
	if mode_id == "classic" and not data.learning[profile_id].has(key) and data.learning[profile_id].get(game_id) is Dictionary:
		data.learning[profile_id][key] = data.learning[profile_id][game_id]
	if not data.learning[profile_id].has(key) or not data.learning[profile_id][key] is Dictionary:
		data.learning[profile_id][key] = {"stars":{},"wrongIds":[],"recentIds":[],"learnedIds":[],"tutorialSeen":false}
	var progress_data: Dictionary = data.learning[profile_id][key]
	for field in ["wrongIds", "recentIds", "learnedIds"]:
		if not (progress_data.get(field) is Array):
			progress_data[field] = []
	if not (progress_data.get("stars") is Dictionary):
		progress_data["stars"] = {}
	if not progress_data.has("tutorialSeen"):
		progress_data["tutorialSeen"] = false
	return progress_data


func complete_level(profile_id: String, game_id: String, level_id: int, stars: int, mode_id: String = "classic") -> void:
	var progress_data := learning(profile_id, game_id, mode_id)
	progress_data.stars[str(level_id)] = maxi(int(progress_data.stars.get(str(level_id),0)), stars)
	flush()


func level_unlocked(profile_id: String, game_id: String, level_id: int, mode_id: String = "classic") -> bool:
	return level_id <= 1 or int(learning(profile_id,game_id,mode_id).stars.get(str(level_id-1),0)) > 0
