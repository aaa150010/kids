class_name PressFeedback
extends RefCounted

## 通用按压反馈：按下缩放 0.95（pivot 居中）+ 短音效，释放回弹
## 用法：PressFeedback.attach(button) 或 PressFeedback.attach(button, &"select")

const PRESS_SCALE := 0.95
const MIN_TOUCH := 48.0 # 触摸目标下限（像素）


static func attach(button: BaseButton, sfx_name: StringName = &"tap") -> void:
	if button.has_meta("press_feedback"):
		return
	button.set_meta("press_feedback", true)
	# 触摸目标检查：自定义最小尺寸与实际尺寸都不足 48px 时给出警告
	if minf(button.custom_minimum_size.x, button.custom_minimum_size.y) < MIN_TOUCH \
		and minf(button.size.x, button.size.y) < MIN_TOUCH:
		push_warning("PressFeedback: [%s] 触摸目标不足 48px，孩子可能点不中" % button.name)
	button.resized.connect(_sync_pivot.bind(button))
	button.button_down.connect(func():
		button.pivot_offset = button.size * 0.5
		SfxMap.play(sfx_name)
		MotionKit.kill_owner(button)
		MotionKit.tween(button).tween_property(
			button, "scale", Vector2.ONE * PRESS_SCALE, MotionKit.PRESS_DOWN
		)
	)
	button.button_up.connect(func():
		MotionKit.kill_owner(button)
		MotionKit.tween(button).tween_property(
			button, "scale", Vector2.ONE, MotionKit.PRESS_UP
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)


static func _sync_pivot(button: BaseButton) -> void:
	button.pivot_offset = button.size * 0.5
