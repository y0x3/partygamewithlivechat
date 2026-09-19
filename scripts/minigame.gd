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

enum State { IDLE, RUNNING, FINISHED }

const GREEN_COLOR := Color(0.0, 1.0, 0.0, 0.35)
const RED_COLOR := Color(1.0, 0.0, 0.0, 0.45)
const GRID_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.08)

const MIN_PLAYERS: int = 2
const BETWEEN_ROUNDS_DELAY: float = 1.5
const WINNER_SHOW_TIME: float = 5.0
const MESSAGE_SHOW_TIME: float = 3.0

const GRID_COLS_DEFAULT: int = 16
const GRID_ROWS_DEFAULT: int = 9
const ROUND_TIME_DEFAULT: float = 10.0
const RED_CHANCE_DEFAULT: float = 0.4

@onready var _info_label: Label = $HUD/InfoLabel
@onready var _result_label: Label = $HUD/ResultLabel
@onready var _menu_panel: PanelContainer = $Menu/MenuPanel
@onready var _players_label: Label = $Menu/MenuPanel/Margin/VBox/PlayersLabel
@onready var _cols_spin: SpinBox = $Menu/MenuPanel/Margin/VBox/Cols/ColsSpin
@onready var _rows_spin: SpinBox = $Menu/MenuPanel/Margin/VBox/Rows/RowsSpin
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
var _cols: int = GRID_COLS_DEFAULT
var _rows: int = GRID_ROWS_DEFAULT
var _round_time: float = ROUND_TIME_DEFAULT
var _red_chance: float = RED_CHANCE_DEFAULT
var _round: int = 0
var _time_left: float = 0.0
var _delay_left: float = 0.0
var _result_left: float = 0.0


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
		_show_result(
			"Se necesitan al menos %d jugadores." % MIN_PLAYERS,
			MESSAGE_SHOW_TIME
		)
		return

	_apply_menu_settings()
	_menu_panel.visible = false
	_alive = players
	_round = 0
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
	_generate_pattern()
	_time_left = _round_time
	_delay_left = 0.0
	_result_label.visible = false
	queue_redraw()
	_update_info()


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

	if _alive.size() == 1 and is_instance_valid(_alive[0]):
		winner = _alive[0].username

	_show_result("%s GANA!" % winner, WINNER_SHOW_TIME)
	game_finished.emit(winner)


func _generate_pattern() -> void:
	_cells.clear()

	for r in _rows:
		var row: Array = []

		for c in _cols:
			row.append(randf() < _red_chance)

		_cells.append(row)


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
	_cols = int(_cols_spin.value)
	_rows = int(_rows_spin.value)
	_round_time = float(_time_spin.value)
	_red_chance = float(_red_spin.value) / 100.0


func _update_info() -> void:
	_info_label.text = "RONDA %d   |   %d s   |   Vivos: %d" % [
		_round,
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
