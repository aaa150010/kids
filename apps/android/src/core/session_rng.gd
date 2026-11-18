class_name SessionRng
extends RefCounted

var generator := RandomNumberGenerator.new()

func _init(seed_value: int = 1, state_value: int = 0) -> void:
	generator.seed = seed_value
	if state_value != 0:
		generator.state = state_value

func shuffled(source: Array) -> Array:
	var result := source.duplicate(true)
	for index in range(result.size() - 1, 0, -1):
		var target := generator.randi_range(0, index)
		var previous: Variant = result[index]
		result[index] = result[target]
		result[target] = previous
	return result

func next_int(minimum: int, maximum: int) -> int:
	return generator.randi_range(minimum, maximum)
