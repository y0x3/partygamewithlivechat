extends Node2D
class_name Player
## Player
## ------------------
## Personaje controlado por comandos de chat. Se crea con !play,
## se mueve al centro de cada zona (escribiendo su número) y alterna
## entre idle, run, sit y emote.


const TEX_IDLE: Texture2D = preload("res://sprites/idle.png")
const TEX_RUN: Texture2D = preload("res://sprites/run.png")
const TEX_SIT: Texture2D = preload("res://sprites/sit.png")
const TEX_EMOTE: Texture2D = preload("res://sprites/emote.png")

## Grilla del sprite sheet.
const SHEET_COLS: int = 13
const SHEET_ROWS: int = 4
const FRAME_SIZE: float = 64.0

## Frames por animación dentro de cada fila.
const IDLE_FRAMES: int = 2
const RUN_FRAMES: int = 8
const SIT_FRAMES: int = 3
const EMOTE_FRAMES: int = 3

const SPRITE_SCALE: float = 3.0
const ANIM_FPS: float = 12.0
const MOVE_DURATION: float = 0.3
## Velocidad de caminata usada para escalar el tiempo de viaje a un destino
## lejano (como cruzar toda la pantalla), manteniendo un ritmo de "caminar".
const MOVE_SPEED: float = 1200.0
const MOVE_MAX_DURATION: float = 1.5
const DEATH_DURATION: float = 0.4

## Burbuja con el mensaje de chat del jugador.
const MESSAGE_DURATION: float = 4.0
const MESSAGE_FADE: float = 0.6
const MESSAGE_MAX_CHARS: int = 120
const MESSAGE_MAX_WIDTH: float = 1200.0
const MESSAGE_PADDING_H: float = 24.0
const MESSAGE_PADDING_V: float = 14.0

## Orden de filas del sprite sheet: 0=arriba, 1=izquierda, 2=abajo, 3=derecha.
const ROW_UP: int = 0
const ROW_LEFT: int = 1
const ROW_DOWN: int = 2
const ROW_RIGHT: int = 3

enum Anim { IDLE, RUN, SIT, EMOTE }

const ANIM_TEXTURES: Dictionary = {
	Anim.IDLE: TEX_IDLE,
	Anim.RUN: TEX_RUN,
	Anim.SIT: TEX_SIT,
	Anim.EMOTE: TEX_EMOTE,
}

const ANIM_FRAMES: Dictionary = {
	Anim.IDLE: IDLE_FRAMES,
	Anim.RUN: RUN_FRAMES,
	Anim.SIT: SIT_FRAMES,
	Anim.EMOTE: EMOTE_FRAMES,
}

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _label: Label = $Label
@onready var _bubble: Panel = $MessageBubble
@onready var _bubble_label: Label = $MessageBubble/MessageLabel

var username: String = ""
var _row: int = ROW_DOWN
var _anim: Anim = Anim.IDLE
var _anim_time: float = 0.0
var _frame: int = -1
var _tween: Tween
var _message_time_left: float = 0.0

## Destinos de movimiento pendientes (centros de zona, Vector2 absolutos)
## recibidos del chat. Se visitan en orden, uno tras otro.
var _target_queue: Array[Vector2] = []


func setup(p_username: String) -> void:
	username = p_username
	_label.text = p_username
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_sprite.hframes = SHEET_COLS
	_sprite.vframes = SHEET_ROWS

	var half: float = FRAME_SIZE * SPRITE_SCALE * 0.5
	_label.offset_left = -150.0
	_label.offset_right = 150.0
	_label.offset_top = -half - 30.0
	_label.offset_bottom = -half - 6.0

	_bubble.visible = false
	_bubble.modulate.a = 1.0
	_bubble.resized.connect(_center_bubble)

	_set_anim(Anim.IDLE)


func show_message(text: String) -> void:
	if text.length() > MESSAGE_MAX_CHARS:
		text = text.substr(0, MESSAGE_MAX_CHARS - 1) + "..."

	_bubble_label.text = text
	_bubble.size = _message_bubble_size(text)
	_bubble.visible = true
	_bubble.modulate.a = 1.0
	_message_time_left = MESSAGE_DURATION
	_center_bubble()


func sit() -> void:
	_clear_steps()
	_stop_moving()
	_set_anim(Anim.SIT)


func emote() -> void:
	_clear_steps()
	_stop_moving()
	_set_anim(Anim.EMOTE)


func die() -> void:
	_clear_steps()
	_stop_moving()
	set_process(false)
	_bubble.visible = false

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, DEATH_DURATION)
	tween.tween_property(self, "scale", Vector2(0.6, 0.6), DEATH_DURATION)
	tween.finished.connect(queue_free)


## Encola los destinos recibidos del chat.
## Cada destino (centro de zona) se recorre en orden: el siguiente
## inicia su animación al terminar el anterior.
func queue_targets(targets: Array) -> void:
	if targets.is_empty():
		return

	for target in targets:
		if target is Vector2:
			_target_queue.append(target)

	if _tween == null or not _tween.is_running():
		_advance_next_step()


func move_to(target: Vector2) -> void:
	var view_size: Vector2 = get_viewport_rect().size
	var half: Vector2 = _visual_half_size()
	target.x = clampf(target.x, half.x, maxf(half.x, view_size.x - half.x))
	target.y = clampf(target.y, half.y, maxf(half.y, view_size.y - half.y))

	_row = _direction_row(target - position)
	_stop_moving()
	_set_anim(Anim.RUN)

	var duration: float = clampf(
		position.distance_to(target) / MOVE_SPEED,
		MOVE_DURATION,
		MOVE_MAX_DURATION
	)
	_tween = create_tween()
	_tween.tween_property(self, "position", target, duration)
	_tween.finished.connect(_on_move_finished)


func clamp_to_screen(view_size: Vector2) -> void:
	var half: Vector2 = _visual_half_size()
	position.x = clampf(position.x, half.x, maxf(half.x, view_size.x - half.x))
	position.y = clampf(position.y, half.y, maxf(half.y, view_size.y - half.y))


func _process(delta: float) -> void:
	_advance_animation(delta)

	if _bubble.visible:
		_message_time_left -= delta

		if _message_time_left <= 0.0:
			_bubble.visible = false
		elif _message_time_left < MESSAGE_FADE:
			_bubble.modulate.a = _message_time_left / MESSAGE_FADE


func _advance_animation(delta: float) -> void:
	var frame_count: int = ANIM_FRAMES[_anim]

	match _anim:
		Anim.IDLE, Anim.RUN:
			_anim_time += delta
			_show_frame(int(_anim_time * ANIM_FPS) % frame_count)
		Anim.SIT:
			_anim_time += delta
			_show_frame(mini(int(_anim_time * ANIM_FPS), frame_count - 1))
		Anim.EMOTE:
			_anim_time += delta
			var index: int = int(_anim_time * ANIM_FPS)

			if index >= frame_count:
				_set_anim(Anim.IDLE)
			else:
				_show_frame(index)


func _show_frame(index: int) -> void:
	if index != _frame:
		_frame = index
		_sprite.frame = _row * SHEET_COLS + _frame


func _center_bubble() -> void:
	var half: float = FRAME_SIZE * SPRITE_SCALE * 0.5
	var bubble_size: Vector2 = _bubble.size
	var top: float = -half - 34.0 - bubble_size.y

	if global_position.y + top < 0.0:
		top = half + 10.0

	_bubble.position = Vector2(-bubble_size.x * 0.5, top)


func _message_bubble_size(text: String) -> Vector2:
	var font: Font = _bubble_label.get_theme_font("font")
	var font_size: int = _bubble_label.get_theme_font_size("font_size")
	var line_width: float = font.get_string_size(
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	).x
	var max_content_width: float = MESSAGE_MAX_WIDTH - MESSAGE_PADDING_H * 2.0
	var wrap_width: float = minf(
		line_width + 4.0,
		max_content_width
	)
	var wrapped_height: float = font.get_multiline_string_size(
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		wrap_width,
		font_size
	).y
	return Vector2(
		wrap_width + MESSAGE_PADDING_H * 2.0,
		wrapped_height + MESSAGE_PADDING_V * 2.0
	)


func _on_move_finished() -> void:
	_advance_next_step()


func _advance_next_step() -> void:
	if _target_queue.is_empty():
		_set_anim(Anim.IDLE)
		return

	var target: Vector2 = _target_queue.pop_front()
	move_to(target)


func _clear_steps() -> void:
	_target_queue.clear()


func _set_anim(anim: Anim) -> void:
	_anim = anim
	_sprite.texture = ANIM_TEXTURES[anim]
	_sprite.hframes = SHEET_COLS
	_sprite.vframes = SHEET_ROWS
	_anim_time = 0.0
	_frame = -1


func _stop_moving() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


func _direction_row(offset: Vector2) -> int:
	if absf(offset.x) >= absf(offset.y):
		return ROW_RIGHT if offset.x > 0.0 else ROW_LEFT
	return ROW_DOWN if offset.y > 0.0 else ROW_UP


func _visual_half_size() -> Vector2:
	var half: float = FRAME_SIZE * SPRITE_SCALE * 0.5
	return Vector2(half, half)
