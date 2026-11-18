extends Node

signal update_available(info: Dictionary)
signal check_finished(info: Dictionary)
signal check_failed(message: String)
signal content_downloaded(version: int)
signal apk_downloaded(path: String)
signal install_started

const UPDATE_BASE := "https://lynote.xyz/play-app/"
const CONTENT_DIR := "user://content/"
const CONTENT_PACK := CONTENT_DIR + "current.pck"
const CONTENT_META := CONTENT_DIR + "current.json"
const PREVIOUS_PACK := CONTENT_DIR + "previous.pck"
const PREVIOUS_META := CONTENT_DIR + "previous.json"
const APK_PATH := "user://updates/kids-playground.apk"
const CHECK_INTERVAL_SECONDS := 21600
const PUBLIC_KEY_PATH := "res://trust/update_public_key.pem"

var latest: Dictionary = {}
var checking := false
var last_check_at := 0.0
var last_error := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_environment("KIDS_PLAYGROUND_AUDIT") == "1":
		checking = true
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTENT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://updates/"))
	call_deferred("_schedule_initial_check")


func _notification(what: int) -> void:
	if OS.get_environment("KIDS_PLAYGROUND_AUDIT") == "1":
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if Time.get_unix_time_from_system() - last_check_at >= CHECK_INTERVAL_SECONDS:
			check_for_updates(false)


func _schedule_initial_check() -> void:
	await get_tree().create_timer(2.5).timeout
	check_for_updates(false)


func app_version_code() -> int:
	var plugin: Object = update_plugin()
	if plugin != null and plugin.has_method("getVersionCode"):
		return int(plugin.call("getVersionCode"))
	return 1


func app_version_name() -> String:
	var plugin: Object = update_plugin()
	if plugin != null and plugin.has_method("getVersionName"):
		return str(plugin.call("getVersionName"))
	return str(ProjectSettings.get_setting("application/config/version", "1.0.0"))


func update_plugin() -> Object:
	if not Engine.has_singleton("UpdateInstaller"):
		return null
	return Engine.get_singleton("UpdateInstaller")


func check_for_updates(manual: bool = false) -> void:
	if checking:
		return
	checking = true
	last_check_at = Time.get_unix_time_from_system()
	var payload_result: Dictionary = await _fetch_bytes(UPDATE_BASE + "latest.json")
	if not bool(payload_result.ok):
		_finish_check_failure("暂时连不上更新服务器。")
		return
	var signature_result: Dictionary = await _fetch_bytes(UPDATE_BASE + "latest.sig")
	if not bool(signature_result.ok):
		_finish_check_failure("更新校验文件下载失败。")
		return
	if not verify_manifest(payload_result.bytes, signature_result.bytes):
		_finish_check_failure("更新文件签名不正确，已拒绝安装。")
		return
	var parsed: Variant = JSON.parse_string(payload_result.bytes.get_string_from_utf8())
	if not parsed is Dictionary or int(parsed.get("schema", 0)) != 1:
		_finish_check_failure("更新清单格式不正确。")
		return
	latest = parsed
	var apk: Dictionary = latest.get("apk", {})
	var remote_code := int(apk.get("versionCode", 0))
	var current_code := app_version_code()
	if remote_code > current_code:
		update_available.emit(latest)
	var content: Dictionary = latest.get("content", {})
	var min_app := int(content.get("minAppVersionCode", 0))
	var max_app := int(content.get("maxAppVersionCode", 2147483647))
	var remote_content_version := int(content.get("version", 0))
	if remote_content_version > ContentDB.content_version and current_code >= min_app and current_code <= max_app:
		await download_content(content)
	checking = false
	check_finished.emit(latest)


func _finish_check_failure(message: String) -> void:
	checking = false
	last_error = message
	check_failed.emit(message)


func verify_manifest(payload: PackedByteArray, signature: PackedByteArray) -> bool:
	if OS.is_debug_build() and not FileAccess.file_exists(PUBLIC_KEY_PATH):
		return true
	if payload.is_empty() or signature.is_empty() or not FileAccess.file_exists(PUBLIC_KEY_PATH):
		return false
	var key := CryptoKey.new()
	var error := key.load_from_string(FileAccess.get_file_as_string(PUBLIC_KEY_PATH), true)
	if error != OK:
		return false
	var crypto := Crypto.new()
	return crypto.verify(
		HashingContext.HASH_SHA256,
		_sha256_bytes(payload),
		Marshalls.base64_to_raw(signature.get_string_from_utf8().strip_edges()),
		key
	)


func _sha256_bytes(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish()


func _fetch_bytes(url: String) -> Dictionary:
	if not is_inside_tree():
		return {"ok": false, "bytes": PackedByteArray()}
	var request := HTTPRequest.new()
	request.timeout = 20.0
	add_child(request)
	var error := request.request(url)
	if error != OK:
		request.queue_free()
		return {"ok": false, "bytes": PackedByteArray()}
	var response: Array = await request.request_completed
	request.queue_free()
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200:
		return {"ok": false, "bytes": PackedByteArray()}
	return {"ok": true, "bytes": response[3]}


func _download_file(url: String, destination: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
	if FileAccess.file_exists(destination):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(destination))
	var request := HTTPRequest.new()
	request.timeout = 120.0
	request.download_file = destination
	add_child(request)
	var error := request.request(url)
	if error != OK:
		request.queue_free()
		return {"ok": false, "status": 0}
	var response: Array = await request.request_completed
	request.queue_free()
	return {
		"ok": int(response[0]) == HTTPRequest.RESULT_SUCCESS and int(response[1]) == 200,
		"status": int(response[1]),
	}


func download_content(content: Dictionary) -> void:
	var url := absolute_url(str(content.get("url", "")))
	var temporary := CONTENT_DIR + "next.pck"
	var result := await _download_file(url, temporary)
	if not bool(result.ok):
		last_error = "内容更新下载失败。"
		return
	var expected_hash := str(content.get("sha256", "")).to_lower()
	if not expected_hash.is_empty() and file_sha256(temporary) != expected_hash:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		last_error = "内容更新校验失败，已保留旧版本。"
		return
	var expected_size := int(content.get("size", 0))
	if expected_size > 0 and _file_size(temporary) != expected_size:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		last_error = "内容更新大小不正确，已保留旧版本。"
		return
	var meta := {
		"schema": 1,
		"version": int(content.get("version", 0)),
		"sha256": expected_hash,
		"appVersionCode": app_version_code(),
		"minAppVersionCode": int(content.get("minAppVersionCode", 0)),
		"maxAppVersionCode": int(content.get("maxAppVersionCode", 2147483647)),
	}
	if FileAccess.file_exists(CONTENT_META):
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(CONTENT_META),
			ProjectSettings.globalize_path(PREVIOUS_META)
		)
	_write_json(CONTENT_META, meta)
	if FileAccess.file_exists(CONTENT_PACK):
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(CONTENT_PACK),
			ProjectSettings.globalize_path(PREVIOUS_PACK)
		)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONTENT_PACK))
	DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary),
		ProjectSettings.globalize_path(CONTENT_PACK)
	)
	content_downloaded.emit(int(content.get("version", 0)))


func load_applied_content_pack() -> void:
	if _load_pack_if_valid(CONTENT_PACK, CONTENT_META):
		return
	if _load_pack_if_valid(PREVIOUS_PACK, PREVIOUS_META):
		push_warning("当前内容包校验失败，已回退上一版本。")
		return


func _load_pack_if_valid(pack_path: String, meta_path: String) -> bool:
	if not FileAccess.file_exists(pack_path) or not FileAccess.file_exists(meta_path):
		return false
	var meta_value = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if not meta_value is Dictionary:
		return false
	var expected := str(meta_value.get("sha256", "")).to_lower()
	if expected.is_empty() or file_sha256(pack_path) != expected:
		return false
	var pack_version := int(meta_value.get("version", 0))
	var current_code := app_version_code()
	var minimum_app := int(meta_value.get("minAppVersionCode", 0))
	var maximum_app := int(meta_value.get("maxAppVersionCode", 2147483647))
	if pack_version < _builtin_content_version() or current_code < minimum_app or current_code > maximum_app:
		return false
	var absolute := ProjectSettings.globalize_path(pack_path)
	if not ProjectSettings.load_resource_pack(absolute, true):
		return false
	return true


func _builtin_content_version() -> int:
	var path := "res://content/version.json"
	if not FileAccess.file_exists(path):
		return 0
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return int(value.get("version", 0)) if value is Dictionary else 0


func _quarantine_pack() -> void:
	if FileAccess.file_exists(CONTENT_PACK):
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(CONTENT_PACK),
			ProjectSettings.globalize_path(CONTENT_DIR + "rejected.pck")
		)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONTENT_PACK))
	if FileAccess.file_exists(CONTENT_META):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONTENT_META))


func download_apk() -> void:
	var apk: Dictionary = latest.get("apk", {})
	if apk.is_empty():
		return
	var url := absolute_url(str(apk.get("url", "")))
	var result := await _download_file(url, APK_PATH)
	if not bool(result.ok):
		last_error = "安装包下载失败。"
		check_failed.emit(last_error)
		return
	var expected_hash := str(apk.get("sha256", "")).to_lower()
	if not expected_hash.is_empty() and file_sha256(APK_PATH) != expected_hash:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(APK_PATH))
		last_error = "安装包校验失败，已删除下载文件。"
		check_failed.emit(last_error)
		return
	var expected_size := int(apk.get("size", 0))
	if expected_size > 0 and _file_size(APK_PATH) != expected_size:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(APK_PATH))
		last_error = "安装包大小不正确，已删除下载文件。"
		check_failed.emit(last_error)
		return
	apk_downloaded.emit(ProjectSettings.globalize_path(APK_PATH))
	install_downloaded_apk()


func install_downloaded_apk() -> bool:
	if not FileAccess.file_exists(APK_PATH):
		return false
	SaveStore.flush()
	var plugin: Object = update_plugin()
	if plugin == null or not plugin.has_method("installApk"):
		last_error = "当前安装包没有更新安装组件。"
		check_failed.emit(last_error)
		return false
	var started := bool(plugin.call("installApk", ProjectSettings.globalize_path(APK_PATH)))
	if started:
		install_started.emit()
	return started


func install_permission_allowed() -> bool:
	var plugin: Object = update_plugin()
	if plugin == null or not plugin.has_method("canRequestPackageInstalls"):
		return false
	return bool(plugin.call("canRequestPackageInstalls"))


func open_install_permission_settings() -> void:
	var plugin: Object = update_plugin()
	if plugin != null and plugin.has_method("openInstallPermissionSettings"):
		plugin.call("openInstallPermissionSettings")


func absolute_url(value: String) -> String:
	if value.begins_with("http://") or value.begins_with("https://"):
		return value
	return UPDATE_BASE + value.trim_prefix("/")


func file_sha256(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while not file.eof_reached():
		context.update(file.get_buffer(1024 * 1024))
	file.close()
	return context.finish().hex_encode()


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var length := file.get_length()
	file.close()
	return length


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value))
		file.close()
