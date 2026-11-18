extends SceneTree

const EXTENSIONS := ["json","png","webp","svg","ogg","wav","mp3","otf","ttf","txt"]
const IMPORTED := ["ctex","stex","oggvorbisstr","mp3str","sample","fontdata"]
var packer := PCKPacker.new()
var included := {}
var failed := false

func _init() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		push_error("请提供内容包的输出路径。")
		quit(1)
		return
	if packer.pck_start(arguments[0]) != OK:
		quit(1)
		return
	_walk("res://content")
	_walk("res://assets")
	if failed or packer.flush() != OK:
		quit(1)
		return
	print("已生成只包含数据与资源的内容包：%s 个文件。" % included.size())
	quit(0)

func _walk(path: String) -> void:
	var directories: Array = []
	for directory in DirAccess.get_directories_at(path):
		directories.append(directory)
	directories.sort()
	for directory in directories:
		_walk(path.path_join(directory))
	var files: Array = []
	for filename in DirAccess.get_files_at(path):
		files.append(filename)
	files.sort()
	for filename in files:
		if not filename.get_extension().to_lower() in EXTENSIONS:
			continue
		var file := path.path_join(filename)
		_add(file)
		var remap := file+".import"
		if not FileAccess.file_exists(remap):
			continue
		var config := ConfigFile.new()
		if config.load(remap) != OK:
			failed = true
			continue
		_add(remap)
		var dependencies: Variant = config.get_value("deps","dest_files",[])
		for dependency in dependencies:
			var resource := str(dependency)
			if not resource.begins_with("res://.godot/imported/") or not resource.get_extension() in IMPORTED:
				push_error("拒绝内容包中的非资源依赖："+resource)
				failed = true
				continue
			_add(resource)

func _add(path: String) -> void:
	if included.has(path):
		return
	if packer.add_file(path,path) != OK:
		push_error("内容资源打包失败："+path)
		failed = true
	else:
		included[path] = true
