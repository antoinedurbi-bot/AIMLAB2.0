extends Node
## Autoload « Sfx » : petits sons de retour synthétisés au démarrage (aucun
## fichier audio). Chaque son est une sinusoïde glissante avec enveloppe
## exponentielle, écrite en PCM 16 bits dans un AudioStreamWAV.

const MIX_RATE := 44100
const VOICES := 8

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_voice: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_streams[&"shot"] = _make_tone(520.0, 180.0, 0.05, 0.22, 60.0)
	_streams[&"hit"] = _make_tone(1250.0, 1250.0, 0.06, 0.4, 45.0)
	_streams[&"kill"] = _make_tone(900.0, 1900.0, 0.11, 0.45, 26.0)
	_streams[&"miss"] = _make_tone(210.0, 130.0, 0.09, 0.35, 30.0)
	_streams[&"beep"] = _make_tone(1000.0, 1000.0, 0.12, 0.45, 8.0)
	_streams[&"tick"] = _make_tone(660.0, 660.0, 0.07, 0.4, 20.0)
	_streams[&"go"] = _make_tone(880.0, 1320.0, 0.2, 0.45, 10.0)
	_streams[&"success"] = _make_tone(700.0, 1500.0, 0.22, 0.45, 9.0)
	_streams[&"fail"] = _make_tone(420.0, 140.0, 0.28, 0.45, 8.0)
	_streams[&"step"] = _make_tone(150.0, 90.0, 0.06, 0.3, 45.0)
	for index in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	GameSettings.audio_changed.connect(_apply_volume)
	_apply_volume()


## Joue un son par son nom (shot, hit, kill, miss, beep, tick, go, success, fail).
func play(sound: StringName, pitch: float = 1.0) -> void:
	var stream := _streams.get(sound) as AudioStreamWAV
	if stream == null:
		return
	var player := _players[_next_voice]
	_next_voice = (_next_voice + 1) % _players.size()
	player.stream = stream
	player.pitch_scale = pitch
	player.play()


## Flux audio d'un son, pour le jouer ailleurs (par exemple en 3D).
func get_stream(sound: StringName) -> AudioStream:
	return _streams.get(sound) as AudioStream


func _apply_volume() -> void:
	var volume: float = GameSettings.sfx_volume
	AudioServer.set_bus_mute(0, volume <= 0.001)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))


## Sinusoïde glissant de `from_hz` à `to_hz`, atténuée en exp(-decay * t).
func _make_tone(from_hz: float, to_hz: float, duration: float, volume: float, decay: float) -> AudioStreamWAV:
	var frames := maxi(int(duration * float(MIX_RATE)), 1)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var phase := 0.0
	for index in frames:
		var progress := float(index) / float(frames)
		var time := float(index) / float(MIX_RATE)
		phase += TAU * lerpf(from_hz, to_hz, progress) / float(MIX_RATE)
		# Attaque de 2 ms et extinction sur les 10 derniers pour cent : pas de clic.
		var envelope := exp(-decay * time) * minf(time / 0.002, 1.0) * minf((1.0 - progress) / 0.1, 1.0)
		var sample := sin(phase) * envelope * volume
		data.encode_s16(index * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
