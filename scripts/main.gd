extends Node2D
## Main
## ------------------
## Escena principal del overlay transparente para OBS.
## Escucha los mensajes de chat, crea un jugador con !play
## y lo mueve por la pantalla con comandos de chat.


const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

## Grilla de zonas. Los espectadores escriben el número de la zona
## (1..N), con o sin prefijo "!", para mover a su jugador hasta su centro.
## El tamaño lo fija el minijuego (crece cada 2 rondas) y los números
## están barajados para que haya que leer cuál va a cada casilla.
var _grid_cols: int = 3
var _grid_rows: int = 3

## Número mostrado en cada celda: _cell_to_number[celda] = etiqueta 1..N.
var _cell_to_number: Array[int] = []

const CMD_PLAY := "!play"
const CMD_STOP := ["!stop", "!salir"]
const CMD_SIT := ["!sit", "!sentar"]
const CMD_EMOTE := ["!emote", "!bailar"]

@onready var _players: Node2D = $Players
@onready var _listener: ChatListener = $ChatListener as ChatListener
@onready var _minigame: Minigame = $Minigame as Minigame

var _players_by_user: Dictionary = {}


func _ready() -> void:
	_enable_window_transparency()
	_listener.chat_message.connect(_on_chat_message)
	_minigame.setup(self, _players)
	_minigame.player_eliminated.connect(_on_player_eliminated)
	_minigame.grid_changed.connect(_on_grid_changed)
	_reshuffle_numbers()
	print("Overlay listo. Escribe !play en el chat para crear un jugador.")


func _on_grid_changed(cols: int, rows: int) -> void:
	_grid_cols = cols
	_grid_rows = rows
	## Se baraja en cada ronda para que los chaters tengan que releer los números.
	_reshuffle_numbers()
	queue_redraw()


func get_players() -> Array:
	return _players.get_children()


func _on_player_eliminated(player: Node) -> void:
	for key in _players_by_user.keys():
		if _players_by_user[key] == player:
			_players_by_user.erase(key)
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

	var zone: int = _parse_zone(command)

	if zone > 0:
		player.queue_targets([_zone_center(zone, get_viewport_rect().size)])
		return

	if content.begins_with("!"):
		return

	player.show_message(content)


## Convierte un comando de chat en un número de zona (1..N).
## Acepta "5" o "!5". Devuelve 0 si no es un número válido.
func _parse_zone(command: String) -> int:
	var trimmed: String = command.trim_prefix("!").strip_edges()

	if not trimmed.is_valid_int():
		return 0

	var value: int = trimmed.to_int()
	var total_cells: int = _grid_cols * _grid_rows

	if value < 1 or value > total_cells:
		return 0

	return value


## Genera una permutación aleatoria de los números 1..N para las casillas.
func _reshuffle_numbers() -> void:
	var total: int = _grid_cols * _grid_rows
	_cell_to_number.clear()

	for i in range(1, total + 1):
		_cell_to_number.append(i)

	_cell_to_number.shuffle()


## Centro absoluto (en coordenadas de pantalla) de la celda que muestra
## el número dado. Devuelve Vector2.ZERO si no se encuentra.
func _zone_center(number: int, view_size: Vector2) -> Vector2:
	var cell: int = _cell_to_number.find(number)

	if cell < 0:
		return Vector2.ZERO

	var col: int = cell % _grid_cols
	var row: int = cell / _grid_cols
	var cell_size: Vector2 = Vector2(
		view_size.x / float(_grid_cols),
		view_size.y / float(_grid_rows)
	)
	return Vector2(
		cell_size.x * (col + 0.5),
		cell_size.y * (row + 0.5)
	)


## Dibuja la grilla con los números de las zonas para guiar al chat.
## El tamaño lo sincroniza el minijuego con grid_changed.
func _draw() -> void:
	var view_size: Vector2 = get_viewport_rect().size
	var cell_size: Vector2 = Vector2(
		view_size.x / float(_grid_cols),
		view_size.y / float(_grid_rows)
	)
	var line_color := Color(1.0, 1.0, 1.0, 0.2)
	var text_color := Color(1.0, 1.0, 1.0, 0.95)
	var outline_color := Color(0.0, 0.0, 0.0, 0.95)
	var font: Font = ThemeDB.fallback_font
	var font_size: int = clampi(
		int(minf(cell_size.x, cell_size.y) / 6.0),
		24,
		80
	)
	var outline_size: int = maxi(font_size / 12, 3)

	for col in range(_grid_cols + 1):
		var x: float = col * cell_size.x
		draw_line(Vector2(x, 0.0), Vector2(x, view_size.y), line_color, 2.0)

	for row in range(_grid_rows + 1):
		var y: float = row * cell_size.y
		draw_line(Vector2(0.0, y), Vector2(view_size.x, y), line_color, 2.0)

	for cell in _cell_to_number.size():
		var col: int = cell % _grid_cols
		var row: int = cell / _grid_cols
		var center := Vector2(
			cell_size.x * (col + 0.5),
			cell_size.y * (row + 0.5)
		)
		var label: String = str(_cell_to_number[cell])
		var size: Vector2 = font.get_string_size(
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size
		)
		var pos: Vector2 = center - size * 0.5
		font.draw_string_outline(
			get_canvas_item(),
			pos,
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size,
			outline_size,
			outline_color,
			3,
			TextServer.DIRECTION_AUTO,
			TextServer.ORIENTATION_HORIZONTAL
		)
		font.draw_string(
			get_canvas_item(),
			pos,
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size,
			text_color,
			3,
			TextServer.DIRECTION_AUTO,
			TextServer.ORIENTATION_HORIZONTAL
		)


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
	print("[JUEGO] Jugador eliminado.")
