extends Node2D
class_name Minigame
## Minigame "Semáforo"
## ------------------
## Minijuego party sencillo: la pantalla se divide en cuadros verde/rojo.
## Cada ronda reparte un patrón aleatorio y da un tiempo para moverse; al
## terminar, quien esté sobre rojo muere. Gana el último jugador en pie.
## El streamer abre el menú con Tab para iniciar/parar y ajustar opciones.


signal player_eliminated(player: Node)
signal game_finished(winner: String)
## Se emite cuando cambia la cantidad de filas/columnas de la grilla
## (por el crecimiento de dificultad) para mantener sincronizado el overlay.
signal grid_changed(cols: int, rows: int)

enum State { IDLE, RUNNING, FINISHED }

const GREEN_COLOR := Color(0.0, 1.0, 0.0, 0.35)
const RED_COLOR := Color(1.0, 0.0, 0.0, 0.45)
const GRID_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.08)

const MIN_PLAYERS: int = 1
const BETWEEN_ROUNDS_DELAY: float = 1.5
const WINNER_SHOW_TIME: float = 5.0
const MESSAGE_SHOW_TIME: float = 3.0

## Dificultad progresiva: la grilla arranca en GRID_MIN_SIZE y crece
## +1 en filas y columnas cada GROW_EVERY_ROUNDS rondas completadas,
## hasta un máximo de GRID_MAX_SIZE.
const GRID_MIN_SIZE: int = 3
const GRID_MAX_SIZE: int = 10
const GROW_EVERY_ROUNDS: int = 2
const ROUND_TIME_DEFAULT: float = 10.0
const RED_CHANCE_DEFAULT: float = 0.4
## Cada ronda la probabilidad de casilla roja sube RED_INCREASE_PER_ROUND
## partiendo del valor base del menú, hasta RED_CHANCE_MAX. Así aparecen
## cada vez menos cuadros verdes a medida que avanza la partida.
const RED_INCREASE_PER_ROUND: float = 0.04
const RED_CHANCE_MAX: float = 0.95
## Ronda en que se declara el empate (la grilla supera el máximo). Hoy = 17.
const DRAW_ROUND: int = (GRID_MAX_SIZE - GRID_MIN_SIZE + 1) * GROW_EVERY_ROUNDS + 1
## Desde esta ronda hay EXACTAMEntE 3/2/1 casillas verdes.
const FINAL_ROUND_START: int = DRAW_ROUND - 3

@onready var _info_label: Label = $HUD/InfoLabel
@onready var _result_label: Label = $HUD/ResultLabel
@onready var _menu_panel: PanelContainer = $Menu/MenuPanel
@onready var _players_label: Label = $Menu/MenuPanel/Margin/VBox/PlayersLabel
@onready var _time_spin: SpinBox = $Menu/MenuPanel/Margin/VBox/Time/TimeSpin
@onready var _red_spin: SpinBox = $Menu/MenuPanel/Margin/VBox/Red/RedSpin
@onready var _start_button: Button = $Menu/MenuPanel/Margin/VBox/Buttons/StartButton
@onready var _stop_button: Button = $Menu/MenuPanel/Margin/VBox/Buttons/StopButton
@onready var _close_button: Button = $Menu/MenuPanel/Margin/VBox/Buttons/CloseButton

var _state: State = State.IDLE
var _main: Node
var _players_node: Node2D
var _alive: Array = []
var _cells: Array = []
var _cols: int = GRID_MIN_SIZE
var _rows: int = GRID_MIN_SIZE
var _round_time: float = ROUND_TIME_DEFAULT
var _red_chance: float = RED_CHANCE_DEFAULT
## Probabilidad efectiva de casilla roja para la ronda actual (base +
## incremento por ronda, con tope).
var _current_red_chance: float = RED_CHANCE_DEFAULT
var _round: int = 0
var _time_left: float = 0.0
var _delay_left: float = 0.0
var _result_left: float = 0.0

## Si al iniciar hay un solo jugador, el juego corre en modo supervivencia:
## rondas infinitas y se muestra cuántas completó cuando cae sobre rojo.
var _single_player: bool = false


func setup(main: Node, players_node: Node2D) -> void:
	_main = main
	_players_node = players_node


func _ready() -> void:
	_menu_panel.visible = false
	_info_label.visible = false
	_result_label.visible = false
	_start_button.pressed.connect(_on_start_pressed)
	_stop_button.pressed.connect(_on_stop_pressed)
	_close_button.pressed.connect(_on_close_pressed)


func is_running() -> bool:
	return _state == State.RUNNING


func start_game() -> void:
	if _state == State.RUNNING:
		return

	var players: Array = _get_players()

	if players.size() < MIN_PLAYERS:
		var message: String = (
			"Se necesita al menos 1 jugador."
			if MIN_PLAYERS == 1
			else "Se necesitan al menos %d jugadores." % MIN_PLAYERS
		)
		_show_result(message, MESSAGE_SHOW_TIME)
		return

	_apply_menu_settings()
	_menu_panel.visible = false
	_single_player = players.size() == 1
	_alive = players
	_round = 0
	_cols = GRID_MIN_SIZE
	_rows = GRID_MIN_SIZE
	grid_changed.emit(_cols, _rows)
	_state = State.RUNNING
	_info_label.visible = true
	_start_round()


func stop_game() -> void:
	if _state == State.IDLE:
		return

	_state = State.IDLE
	_alive.clear()
	_cells.clear()
	_time_left = 0.0
	_delay_left = 0.0
	_single_player = false
	_info_label.visible = false
	queue_redraw()


func _process(delta: float) -> void:
	if _result_left > 0.0:
		_result_left -= delta

		if _result_left <= 0.0:
			_result_label.visible = false

	if _state == State.FINISHED and not _result_label.visible:
		_state = State.IDLE

	if _state != State.RUNNING:
		return

	if _delay_left > 0.0:
		_delay_left -= delta

		if _delay_left <= 0.0:
			_start_round()

		return

	_time_left -= delta
	_update_info()

	if _time_left <= 0.0:
		_end_round()


func _input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_TAB
	):
		_toggle_menu()
		get_viewport().set_input_as_handled()


func _start_round() -> void:
	_round += 1
	_alive = _alive.filter(func(player): return is_instance_valid(player))

	_current_red_chance = clampf(
		_red_chance + (_round - 1) * RED_INCREASE_PER_ROUND,
		0.0,
		RED_CHANCE_MAX
	)

	var size: int = _grid_size_for_round(_round)

	if size > GRID_MAX_SIZE:
		_finish_draw()
		return

	if size != _cols or size != _rows:
		_cols = size
		_rows = size

	## Se emite en cada ronda para que el overlay baraje los números.
	grid_changed.emit(_cols, _rows)

	_generate_pattern()
	_time_left = _round_time
	_delay_left = 0.0
	_result_label.visible = false
	queue_redraw()
	_update_info()


## Tamaño de la grilla (cuadrada) según la ronda: GRID_MIN_SIZE de inicio
## y +1 cada GROW_EVERY_ROUNDS rondas completadas.
func _grid_size_for_round(round: int) -> int:
	return GRID_MIN_SIZE + int((round - 1) / GROW_EVERY_ROUNDS)


func _end_round() -> void:
	var survivors: Array = []

	for player in _alive:
		if not is_instance_valid(player):
			continue

		if _is_deadly(player.position):
			player_eliminated.emit(player)
		else:
			survivors.append(player)

	_alive = survivors

	if _single_player:
		if _alive.is_empty():
			_finish_game()
		else:
			_delay_left = BETWEEN_ROUNDS_DELAY
		return

	if _alive.size() <= 1:
		_finish_game()
	else:
		_delay_left = BETWEEN_ROUNDS_DELAY


func _finish_game() -> void:
	_state = State.FINISHED
	_cells.clear()
	_info_label.visible = false
	queue_redraw()

	var winner: String = "Nadie"

	if _single_player:
		var rounds: int = maxi(_round - 1, 0)
		_show_result(
			"¡Sobreviviste %d ronda%s!" % [
				rounds,
				"s" if rounds != 1 else ""
			],
			WINNER_SHOW_TIME
		)
		winner = "Nadie"
		game_finished.emit(winner)
		return

	if _alive.size() == 1 and is_instance_valid(_alive[0]):
		winner = _alive[0].username

	_show_result("%s GANA!" % winner, WINNER_SHOW_TIME)
	game_finished.emit(winner)


## Cuando se alcanza la grilla máxima sin que nadie haya perdido:
## el juego termina en empate y todos los que sigan en pie mueren.
func _finish_draw() -> void:
	_state = State.FINISHED
	_cells.clear()
	_info_label.visible = false
	queue_redraw()

	for player in _alive:
		player_eliminated.emit(player)

	_alive.clear()
	_show_result("¡Empate! Mortalidad máxima", WINNER_SHOW_TIME)
	game_finished.emit("Nadie")


func _generate_pattern() -> void:
	_cells.clear()

	for r in _rows:
		var row: Array = []

		for c in _cols:
			row.append(randf() < _current_red_chance)

		_cells.append(row)

	if _round >= FINAL_ROUND_START:
		_fit_exact_green(DRAW_ROUND - _round)
	else:
		_fit_min_green(1)


## Convierte exactamente `count` casillas en verdes (el resto rojas).
func _fit_exact_green(count: int) -> void:
	var index: Array = []

	for r in _rows:
		for c in _cols:
			index.append(Vector2i(c, r))

	index.shuffle()

	for i in index.size():
		var cell: Vector2i = index[i]
		_cells[cell.y][cell.x] = i >= count


## Garantiza al menos `count` casillas verdes, convirtiendo rojas aleatorias.
func _fit_min_green(count: int) -> void:
	var green: int = 0

	for r in _rows:
		for c in _cols:
			if not _cells[r][c]:
				green += 1

	var need: int = count - green

	while need > 0:
		var col: int = randi() % _cols
		var row_index: int = randi() % _rows

		if _cells[row_index][col]:
			_cells[row_index][col] = false
			need -= 1


func _is_deadly(pos: Vector2) -> bool:
	var cell: Vector2i = _cell_at(pos)
	return _cells[cell.y][cell.x]


func _cell_at(pos: Vector2) -> Vector2i:
	var size: Vector2 = _cell_size()
	var col: int = clampi(int(pos.x / size.x), 0, _cols - 1)
	var row: int = clampi(int(pos.y / size.y), 0, _rows - 1)
	return Vector2i(col, row)


func _cell_size() -> Vector2:
	var view: Vector2 = get_viewport_rect().size
	return Vector2(view.x / float(_cols), view.y / float(_rows))


func _draw() -> void:
	if _state != State.RUNNING or _cells.is_empty():
		return

	var size: Vector2 = _cell_size()

	for r in _rows:
		for c in _cols:
			var rect := Rect2(Vector2(c, r) * size, size)
			draw_rect(rect, RED_COLOR if _cells[r][c] else GREEN_COLOR)

	for c in _cols + 1:
		var x: float = c * size.x
		draw_line(Vector2(x, 0.0), Vector2(x, _rows * size.y), GRID_LINE_COLOR)

	for r in _rows + 1:
		var y: float = r * size.y
		draw_line(Vector2(0.0, y), Vector2(_cols * size.x, y), GRID_LINE_COLOR)


func _toggle_menu() -> void:
	_menu_panel.visible = not _menu_panel.visible

	if _menu_panel.visible:
		_players_label.text = "Jugadores en pantalla: %d" % _get_players().size()


func _apply_menu_settings() -> void:
	_round_time = float(_time_spin.value)
	_red_chance = float(_red_spin.value) / 100.0


func _update_info() -> void:
	_info_label.text = "RONDA %d  |  %dx%d  |  %d s  |  Vivos: %d" % [
		_round,
		_cols,
		_rows,
		ceili(maxf(_time_left, 0.0)),
		_alive.size()
	]


func _show_result(text: String, duration: float) -> void:
	_result_label.text = text
	_result_label.visible = true
	_result_left = duration


func _get_players() -> Array:
	if _players_node != null:
		return _players_node.get_children()

	return []


func _on_start_pressed() -> void:
	start_game()


func _on_stop_pressed() -> void:
	stop_game()


func _on_close_pressed() -> void:
	_menu_panel.visible = false
