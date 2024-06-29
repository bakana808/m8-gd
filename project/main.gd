class_name M8SceneDisplay extends Panel

const MAIN_SCENE: PackedScene = preload ("res://scenes/desk_scene.tscn")

const FONT_01_SMALL: BitMap = preload ("res://assets/m8_fonts/5_7.bmp")
const FONT_01_BIG: BitMap = preload ("res://assets/m8_fonts/8_9.bmp")
const FONT_02_SMALL: BitMap = preload ("res://assets/m8_fonts/9_9.bmp")
const FONT_02_BOLD: BitMap = preload ("res://assets/m8_fonts/10_10.bmp")
const FONT_02_HUGE: BitMap = preload ("res://assets/m8_fonts/12_12.bmp")

const M8K_UP = 64
const M8K_DOWN = 32
const M8K_LEFT = 128
const M8K_RIGHT = 4
const M8K_SHIFT = 16
const M8K_PLAY = 8
const M8K_OPTION = 2
const M8K_EDIT = 1

const M8_ACTIONS := [
	"key_up", "key_down", "key_left", "key_right",
	"key_shift", "key_play", "key_option", "key_edit"]

signal m8_key_changed
signal m8_scene_changed

@export var visualizer_ca_amount = 1.0
@export var visualizer_glow_amount = 0.5
@export var visualizer_brightness_amount = 0.1

@onready var audio_monitor: AudioStreamPlayer

@onready var scene_viewport: SubViewport = %SceneViewport
@onready var current_scene: M8Scene = null

@onready var menu: MainMenu = %MainMenuPanel

@onready var config := M8Config.load()

@onready var m8_client := M8GD.new()
@onready var m8_connected := false
@onready var m8_audio_connected := false
@onready var m8_keystate: int = 0 # bitfield containing state of all 8 keys
@onready var m8_keystate_last: int = 0
@onready var m8_locally_controlled := false

## true if audio device is in the middle of connecting
var is_audio_connecting = false

var last_peak := 0.0

func _ready():

	# resize viewport with window
	DisplayServer.window_set_min_size(Vector2i(640, 480)) # 2x M8 screen size
	get_tree().get_root().size_changed.connect(on_window_size_changed)

	# initialize main menu
	print("initializing menu controls...")
	menu.initialize(self)

	# initialize main scene
	_preload_scene(MAIN_SCENE)

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit()

func quit():
	config.save()
	get_tree().quit()

## Temporarily show a message on the bottom-left of the screen.
func print_blink(msg: String) -> void:
	%LabelStatus.text = msg
	%LabelStatus.modulate.a = 1.0

## Return true if user is in the menu.
func is_menu_open() -> bool:
	return %MainMenuPanel.visible

## Reload the current scene.
func reload_scene() -> void:
	if current_scene:
		load_scene(current_scene.scene_file_path)

## Load a scene from a filepath.
func load_scene(scene_path) -> void:
	# load packed scene from file
	print("loading new scene from %s..." % scene_path)
	var packed_scene = load(scene_path.trim_suffix(".remap"))
	assert(packed_scene != null and packed_scene is PackedScene)

	_preload_scene(packed_scene)

func _preload_scene(packed_scene: PackedScene) -> void:

	# instantiate scene
	print("instantiating scene...")
	var scene: M8Scene = packed_scene.instantiate()
	assert(scene != null and scene is M8Scene)

	# remove existing scene from viewport
	if current_scene:
		print("freeing current scene...")
		scene_viewport.remove_child(current_scene)
		current_scene.queue_free()
		current_scene = null

	# add new scene and initialize
	print("adding new scene...")
	scene_viewport.add_child(scene)
	scene.initialize(self)
	current_scene = scene
	current_scene.spectrum_analyzer = AudioServer.get_bus_effect_instance(1, 0)

	print("scene loaded!")
	m8_scene_changed.emit()

# Signal callbacks
################################################################################

func on_window_size_changed() -> void:
	scene_viewport.size = DisplayServer.window_get_size()

# M8 client methods
################################################################################

func m8_device_connect(port: String) -> void:

	var m8_ports: Array = M8GD.list_devices()

	if !port in m8_ports:
		menu.set_status_serialport("Failed: port not found: %s" % port)
		return

	menu.set_status_serialport("Connecting to serial port %s..." % m8_ports[0])

	if !m8_client.connect(port):
		menu.set_status_serialport("Failed: failed to connect to port: %s" % port)
		return

	m8_connected = true
	%LabelPort.text = m8_ports[0]
	m8_client.keystate_changed.connect(on_m8_keystate_changed)
	m8_client.system_info.connect(on_m8_system_info)
	m8_client.font_changed.connect(on_m8_font_changed)
	m8_client.device_disconnected.connect(on_m8_device_disconnect)

	print_blink("connected to M8 at %s!" % m8_ports[0])
	menu.set_status_serialport("Connected to: %s" % m8_ports[0])

## Automatically detect and connect to any M8 device.
func m8_device_connect_auto() -> void:

	menu.set_status_serialport("Scanning for M8 devices...")

	var m8_ports: Array = M8GD.list_devices()
	if m8_ports.size():
		m8_device_connect(m8_ports[0])
	else:
		menu.set_status_serialport("Not connected: No M8 devices found")

func m8_audio_connect(device: String) -> void:
	if !device in AudioServer.get_input_device_list():
		menu.set_status_audiodevice("Failed: audio device not found: %s" % device)
		return

	if is_audio_connecting: return
	is_audio_connecting = true

	if audio_monitor and is_instance_valid(audio_monitor):
		audio_monitor.stream = null
		audio_monitor.queue_free()
		remove_child(audio_monitor)
		audio_monitor = null

	menu.set_status_audiodevice("Not connected")
	await get_tree().create_timer(0.1).timeout

	AudioServer.input_device = device

	audio_monitor = AudioStreamPlayer.new()
	audio_monitor.stream = AudioStreamMicrophone.new()
	audio_monitor.bus = "Analyzer"
	add_child(audio_monitor)
	audio_monitor.playing = false

	menu.set_status_audiodevice("Starting...")
	await get_tree().create_timer(0.1).timeout

	audio_monitor.playing = true
	m8_audio_connected = true
	is_audio_connecting = false

	print("monitoring audio with device %s" % device)
	menu.set_status_audiodevice("Connected to: %s" % device)

## Automatically detect and monitor an M8 audio device.
func m8_audio_connect_auto() -> void:

	# If the M8 device is plugged in and detected, use it as a microphone and
	# playback to the default audio output device.
	for device in AudioServer.get_input_device_list():
		if device.contains("M8"):
			m8_audio_connect(device)
			return
	
	menu.set_status_audiodevice("Not connected: No M8 audio device found")

## Disconnect the M8 audio device from the monitor.
func m8_audio_disconnect() -> void:
	m8_audio_connected = false
	AudioServer.input_device = "Default"
	audio_monitor.playing = false
	print("no longer monitoring audio")
	menu.set_status_audiodevice("Not connected (Disconnected)")

## Check if the M8 audio device still exists. If not, disconnect.
func m8_audio_check() -> void:
	for device in AudioServer.get_input_device_list():
		if device.contains("M8"):
			return
	m8_audio_disconnect()

func on_m8_keystate_changed(keystate: int) -> void:
	update_keystate(keystate, false)
	m8_locally_controlled = true

func on_m8_system_info(hardware, firmware) -> void:
	%LabelVersion.text = "%s %s" % [hardware, firmware]

func on_m8_font_changed(model: String, font: int) -> void:
	# switch between small/big fonts (Model_01)
	match model:
		"model_02":
			if font == 0:
				m8_client.load_font(FONT_02_SMALL)
			elif font == 1:
				m8_client.load_font(FONT_02_BOLD)
			else:
				m8_client.load_font(FONT_02_HUGE)
		_:
			if font == 0:
				m8_client.load_font(FONT_01_SMALL)
			else:
				m8_client.load_font(FONT_01_BIG)

## Called when the M8 has been disconnected.
func on_m8_device_disconnect() -> void:

	m8_connected = false
	%LabelPort.text = ""

	m8_client.keystate_changed.disconnect(on_m8_keystate_changed)
	m8_client.system_info.disconnect(on_m8_system_info)
	m8_client.font_changed.disconnect(on_m8_font_changed)
	m8_client.device_disconnected.disconnect(on_m8_device_disconnect)

	if m8_audio_connected:
		m8_audio_disconnect()

	print_blink("disconnected")
	menu.set_status_serialport("Not connected (Disconnected)")

func _physics_process(delta: float) -> void:

	# calculate peaks for visualizations

	var peak = db_to_linear((AudioServer.get_bus_peak_volume_left_db(1, 0) + AudioServer.get_bus_peak_volume_right_db(1, 0)) / 2.0)
	var avg_peak = (peak + last_peak) / 2.0
	last_peak = avg_peak
	
	# do shader parameter responses to audio

	var material_crt_filter: ShaderMaterial = $CRTShader.material
	material_crt_filter.set_shader_parameter("aberration", avg_peak * visualizer_ca_amount)
	# if scene is CRT_Scene:
	#     scene.crt_glow_amount = 1.0 + (avg_peak * visualizer_glow_amount)
	#     scene.brightness = 1.0 + (avg_peak * visualizer_brightness_amount)
	current_scene.audio_peak = avg_peak

	# fade out status message

	if %LabelStatus.modulate.a > 0:
		%LabelStatus.modulate.a = lerp( %LabelStatus.modulate.a, %LabelStatus.modulate.a - delta * 2.0, 0.2)

func _process(_delta: float) -> void:

	# read and update m8 display texture every frame
	if m8_connected and m8_client.read_serial_data():
		m8_client.update_texture()

	# auto connect to m8s
	if !m8_connected:
		m8_device_connect_auto()

	# auto monitor audio if m8 is connected
	if m8_connected and !m8_audio_connected:
		m8_audio_connect_auto()

	if m8_connected and m8_audio_connected:
		m8_audio_check()

	%LabelFPS.text = "%d" % Engine.get_frames_per_second()

	var is_anything_pressed := false

	for key in ["key_up", "key_down", "key_left", "key_right", "key_shift", "key_play", "key_option", "key_edit"]:
		if Input.is_action_pressed(key):
			is_anything_pressed = true
			break

	# godot action to m8 controller
	if !m8_locally_controlled or m8_locally_controlled and is_anything_pressed:

		var keystate = 0

		if Input.is_action_pressed("key_up"): keystate += M8K_UP
		if Input.is_action_pressed("key_down"): keystate += M8K_DOWN
		if Input.is_action_pressed("key_left"): keystate += M8K_LEFT
		if Input.is_action_pressed("key_right"): keystate += M8K_RIGHT
		if Input.is_action_pressed("key_shift"): keystate += M8K_SHIFT
		if Input.is_action_pressed("key_play"): keystate += M8K_PLAY
		if Input.is_action_pressed("key_option"): keystate += M8K_OPTION
		if Input.is_action_pressed("key_edit"): keystate += M8K_EDIT

		update_keystate(keystate, true)

		m8_locally_controlled = false

	if Input.is_action_just_pressed("force_read"): m8_client.update_texture()

func update_keystate(keystate: int, write: bool=false):

	if keystate != m8_keystate_last:

		m8_keystate = keystate

		if write: m8_client.send_input(m8_keystate)
		# m8.send_input(m8_keystate)

		if m8_keystate&M8K_UP and !m8_keystate_last&M8K_UP: m8_key_changed.emit("up", true)
		if !m8_keystate&M8K_UP and m8_keystate_last&M8K_UP: m8_key_changed.emit("up", false)
		if m8_keystate&M8K_DOWN and !m8_keystate_last&M8K_DOWN: m8_key_changed.emit("down", true)
		if !m8_keystate&M8K_DOWN and m8_keystate_last&M8K_DOWN: m8_key_changed.emit("down", false)
		if m8_keystate&M8K_LEFT and !m8_keystate_last&M8K_LEFT: m8_key_changed.emit("left", true)
		if !m8_keystate&M8K_LEFT and m8_keystate_last&M8K_LEFT: m8_key_changed.emit("left", false)
		if m8_keystate&M8K_RIGHT and !m8_keystate_last&M8K_RIGHT: m8_key_changed.emit("right", true)
		if !m8_keystate&M8K_RIGHT and m8_keystate_last&M8K_RIGHT: m8_key_changed.emit("right", false)
		if m8_keystate&M8K_SHIFT and !m8_keystate_last&M8K_SHIFT: m8_key_changed.emit("shift", true)
		if !m8_keystate&M8K_SHIFT and m8_keystate_last&M8K_SHIFT: m8_key_changed.emit("shift", false)
		if m8_keystate&M8K_PLAY and !m8_keystate_last&M8K_PLAY: m8_key_changed.emit("play", true)
		if !m8_keystate&M8K_PLAY and m8_keystate_last&M8K_PLAY: m8_key_changed.emit("play", false)
		if m8_keystate&M8K_OPTION and !m8_keystate_last&M8K_OPTION: m8_key_changed.emit("option", true)
		if !m8_keystate&M8K_OPTION and m8_keystate_last&M8K_OPTION: m8_key_changed.emit("option", false)
		if m8_keystate&M8K_EDIT and !m8_keystate_last&M8K_EDIT: m8_key_changed.emit("edit", true)
		if !m8_keystate&M8K_EDIT and m8_keystate_last&M8K_EDIT: m8_key_changed.emit("edit", false)

		m8_keystate_last = m8_keystate

func _input(event):

	if event is InputEventKey:
		# fullscreen ALT+ENTER toggle
		if event.pressed and event.keycode == KEY_ENTER and event.alt_pressed:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
