extends Node2D
## Main
## ------------------
## Escena principal del overlay transparente para OBS.
## Escucha los mensajes de chat, crea un jugador con !play
## y lo mueve por la pantalla con comandos de chat.


const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

## Píxeles que se mueve un jugador por cada comando recibido.
const STEP: float = 60.0

## Intervalo entre ticks del juego (en segundos).
## Durante cada tick se acumulan los movimientos de chat
## y al liberarlo se aplican todos en orden.
const TICK_INTERVAL: float = 3.0

const CMD_PLAY := "!play"
const CMD_STOP := ["!stop", "!salir"]
const CMD_UP := ["!up", "!arriba"]
const CMD_DOWN := ["!down", "!abajo"]
const CMD_LEFT := ["!left", "!izq", "!izquierda"]
const CMD_RIGHT := ["!right", "!der", "!derecha"]
const CMD_SIT := ["!sit", "!sentar"]
const CMD_EMOTE := ["!emote", "!bailar"]

@onready var _players: Node2D = $Players
@onready var _listener: ChatListener = $ChatListener as ChatListener
@onready var _minigame: Minigame = $Minigame as Minigame

var _players_by_user: Dictionary = {}

## Cuenta regresiva hasta el próximo tick del juego.
var _tick_time: float = TICK_INTERVAL

## Movimientos de chat acumulados durante el tick actual.
## user_key -> Array de offsets (Vector2) a aplicar en el próximo tick.
var _pending_moves: Dictionary = {}


func _ready() -> void:
	_enable_window_transparency()
	_listener.chat_message.connect(_on_chat_message)
	_minigame.setup(self, _players)
	_minigame.player_eliminated.connect(_on_player_eliminated)
	print("Overlay listo. Escribe !play en el chat para crear un jugador.")


func _process(delta: float) -> void:
	_tick_time -= delta

	if _tick_time <= 0.0:
		_release_tick()
		_tick_time += TICK_INTERVAL


func get_players() -> Array:
	return _players.get_children()


func _on_player_eliminated(player: Node) -> void:
	for key in _players_by_user.keys():
		if _players_by_user[key] == player:
			_players_by_user.erase(key)
			_pending_moves.erase(key)
			break

	if player.has_method("die"):
		player.die()

	print("[JUEGO] Jugador eliminado por el minijuego.")


func _enable_window_transparency() -> void:
	get_viewport().transparent_bg = true
	DisplayServer.window_set_flag(
		DisplayServer.WINDOW_FLAG_TRANSPARENT,
		true
	)


func _on_chat_message(
	_source: String,
	username: String,
	content: String
) -> void:
	var user_key: String = username.to_lower()
	var command: String = content.to_lower()

	if command == CMD_PLAY:
		_spawn_player(user_key, username)
		return

	if command in CMD_STOP:
		_remove_player(user_key)
		return

	var player: Player = _players_by_user.get(user_key, null) as Player

	if player == null:
		return

	if command in CMD_SIT:
		player.sit()
		return

	if command in CMD_EMOTE:
		player.emote()
		return

	var direction: Vector2 = _command_direction(command)

	if direction != Vector2.ZERO:
		_queue_move(user_key, direction)
		return

	if content.begins_with("!"):
		return

	player.show_message(content)


func _command_direction(command: String) -> Vector2:
	if command in CMD_UP:
		return Vector2.UP
	if command in CMD_DOWN:
		return Vector2.DOWN
	if command in CMD_LEFT:
		return Vector2.LEFT
	if command in CMD_RIGHT:
		return Vector2.RIGHT
	return Vector2.ZERO


func _queue_move(user_key: String, direction: Vector2) -> void:
	var steps: Array = _pending_moves.get(user_key, [])
	steps.append(direction * STEP)
	_pending_moves[user_key] = steps


func _release_tick() -> void:
	for user_key in _pending_moves.keys():
		var steps: Array = _pending_moves[user_key]

		if steps.is_empty():
			continue

		var player: Player = _players_by_user.get(user_key, null) as Player

		if player == null:
			continue

		player.queue_steps(steps)

	_pending_moves.clear()


func _spawn_player(user_key: String, username: String) -> void:
	if _players_by_user.has(user_key):
		return

	if _minigame.is_running():
		return

	var player: Player = PLAYER_SCENE.instantiate() as Player
	_players.add_child(player)
	player.setup(username)

	var view_size: Vector2 = get_viewport_rect().size
	player.position = Vector2(
		randf_range(0.0, view_size.x),
		randf_range(0.0, view_size.y)
	)
	player.clamp_to_screen(view_size)

	_players_by_user[user_key] = player
	print("[JUEGO] Jugador creado: ", username)


func _remove_player(user_key: String) -> void:
	var player: Player = _players_by_user.get(user_key, null) as Player

	if player == null:
		return

	player.queue_free()
	_players_by_user.erase(user_key)
	_pending_moves.erase(user_key)
	print("[JUEGO] Jugador eliminado.")
