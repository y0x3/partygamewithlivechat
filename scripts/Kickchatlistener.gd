extends Node
class_name ChatListener
## ChatListener
## ------------------
## Recibe mensajes de Twitch y Kick mediante
## el WebSocket Server de Streamer.bot.
## Emite la señal `chat_message` por cada mensaje recibido.


signal chat_message(source: String, username: String, content: String)


const STREAMERBOT_URL: String = "ws://127.0.0.1:8080/"

var socket: WebSocketPeer = WebSocketPeer.new()
var _was_connected: bool = false


func _ready() -> void:
	var err: Error = socket.connect_to_url(STREAMERBOT_URL)

	if err != OK:
		push_error(
			"No se pudo iniciar conexión a Streamer.bot: %s"
			% err
		)
	else:
		print(
			"Conectando a Streamer.bot en ",
			STREAMERBOT_URL,
			"..."
		)


func _subscribe_to_chat() -> void:

	var request: Dictionary = {
		"request": "Subscribe",
		"id": "chat-sub",
		"events": {
			"Twitch": ["ChatMessage"],
			"Kick": ["ChatMessage"]
		}
	}

	socket.send_text(JSON.stringify(request))

	print("Suscripción enviada para Twitch y Kick.")


func _process(_delta: float) -> void:

	socket.poll()

	var state: WebSocketPeer.State = socket.get_ready_state()


	# ==========================================
	# CONEXIÓN ABIERTA
	# ==========================================

	if state == WebSocketPeer.STATE_OPEN:

		if not _was_connected:

			_was_connected = true

			print("================================")
			print("Conectado a Streamer.bot")
			print("================================")

			_subscribe_to_chat()


		while socket.get_available_packet_count() > 0:

			var packet: PackedByteArray = socket.get_packet()

			var message: String = packet.get_string_from_utf8()

			_on_message_received(message)


	# ==========================================
	# CONEXIÓN CERRADA
	# ==========================================

	elif state == WebSocketPeer.STATE_CLOSED:

		if _was_connected:

			var code: int = socket.get_close_code()

			print(
				"Conexión cerrada (code %d). Reintentando en 3s..."
				% code
			)

			_was_connected = false

			await get_tree().create_timer(3.0).timeout

			socket.connect_to_url(STREAMERBOT_URL)


func _on_message_received(raw_json: String) -> void:

	var parsed: Variant = JSON.parse_string(raw_json)


	# ==========================================
	# JSON INVÁLIDO
	# ==========================================

	if parsed == null:

		push_warning(
			"Mensaje no es JSON válido: %s"
			% raw_json
		)

		return


	# ==========================================
	# DEBUG
	# ==========================================

	print("[RAW] ", parsed)


	# ==========================================
	# RESPUESTA A UNA PETICIÓN
	# ==========================================

	if parsed is Dictionary:

		var parsed_dict: Dictionary = parsed

		if parsed_dict.has("status"):

			print(
				"[RESPUESTA] id=%s status=%s"
				% [
					str(parsed_dict.get("id", "?")),
					str(parsed_dict.get("status", "?"))
				]
			)

			return


		# ==========================================
		# EVENTO
		# ==========================================

		if not parsed_dict.has("event"):
			return


		var event_info_variant: Variant = parsed_dict.get(
			"event",
			{}
		)

		if not event_info_variant is Dictionary:
			return


		var event_info: Dictionary = event_info_variant

		var source: String = str(
			event_info.get("source", "")
		)

		var event_type: String = str(
			event_info.get("type", "")
		)


		print(
			"[EVENTO] %s.%s"
			% [
				source,
				event_type
			]
		)


		# ==========================================
		# TWITCH
		# ==========================================

		if source == "Twitch" and event_type == "ChatMessage":

			_process_twitch_message(parsed_dict)


		# ==========================================
		# KICK
		# ==========================================

		elif source == "Kick" and event_type == "ChatMessage":

			_process_kick_message(parsed_dict)


# ==================================================
# TWITCH
# ==================================================

func _process_twitch_message(parsed: Dictionary) -> void:

	var data_variant: Variant = parsed.get(
		"data",
		{}
	)

	if not data_variant is Dictionary:
		return

	var data: Dictionary = data_variant

	var username: String = "???"
	var content: String = str(
		data.get("text", "")
	)


	# ==========================================
	# USUARIO
	# ==========================================

	var user_variant: Variant = data.get(
		"user",
		null
	)

	if user_variant is Dictionary:

		var user_data: Dictionary = user_variant

		username = str(
			user_data.get(
				"name",
				user_data.get(
					"login",
					"???"
				)
			)
		)


	print("================================")
	print("MENSAJE DE TWITCH")
	print("Usuario: ", username)
	print("Mensaje: ", content)
	print("================================")

	chat_message.emit("Twitch", username, content.strip_edges())


# ==================================================
# KICK
# ==================================================

func _process_kick_message(parsed: Dictionary) -> void:

	var data_variant: Variant = parsed.get(
		"data",
		{}
	)

	if not data_variant is Dictionary:
		return

	var data: Dictionary = data_variant

	var username: String = "???"
	var content: String = ""


	# ==========================================
	# USUARIO
	# ==========================================

	var user_variant: Variant = data.get(
		"user",
		null
	)

	if user_variant is Dictionary:

		var user_data: Dictionary = user_variant

		username = str(
			user_data.get(
				"name",
				user_data.get(
					"username",
					"???"
				)
			)
		)


	# ==========================================
	# MENSAJE
	# ==========================================

	content = str(
		data.get(
			"text",
			data.get(
				"message",
				data.get(
					"content",
					""
				)
			)
		)
	)


	print("================================")
	print("MENSAJE DE KICK")
	print("Usuario: ", username)
	print("Mensaje: ", content)
	print("================================")

	chat_message.emit("Kick", username, content.strip_edges())
