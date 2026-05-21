import 'dart:convert';
import 'package:crypto/crypto.dart'; // Necesario para validar la Clave Maestra
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:io' show Platform, exit;
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_flutter/lucide_flutter.dart'; // Add this import
import 'mqtt_service.dart';
import 'local_discovery_service.dart';
import 'ble_service.dart';
import 'models/device.dart';
import 'devices_page.dart';
import 'ui_pages.dart';
import 'devices_page.dart';

// SharedPreferences keys (public)
const String kDevicesKey = 'known_devices';
const String kDefaultDeviceKey = 'default_device_serial';
const String kMaxTempKey = 'max_temp';
const String kHysteresisKey = 'hysteresis';

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final upperText = newValue.text.toUpperCase();
    return TextEditingValue(
      text: upperText,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

const Color kAccentColor = Colors.white;

void main() {
  runApp(Phoenix(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control de Hiroki',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark, // Configura el tema oscuro por defecto
        primaryColor: Colors.white, // Color primario monocromático
        scaffoldBackgroundColor: Colors.black, // Fondo principal full black
        textTheme: GoogleFonts.montserratTextTheme( // Aplica Montserrat a todo el TextTheme
          Theme.of(context).textTheme.apply(
            bodyColor: Colors.white, // Color del texto principal
            displayColor: Colors.white, // Color de los títulos
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black, // Color de fondo del AppBar full black
          foregroundColor: Colors.white, // Color del texto y los iconos en el AppBar
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF1E1E1E),
          contentTextStyle: TextStyle(color: Colors.white),
        ),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: kAccentColor,
          surface: Colors.black, // Color de las superficies en negro
          background: Colors.black,
          error: Colors.redAccent,
          onPrimary: Colors.black,
          onSecondary: Colors.black,
          onSurface: Colors.white,
          onBackground: Colors.white,
          onError: Colors.black,
        ),
        iconTheme: const IconThemeData(color: Colors.white70),
        sliderTheme: SliderThemeData(
          activeTrackColor: Colors.white,
          inactiveTrackColor: Colors.white30,
          thumbColor: Colors.white,
          overlayColor: Colors.white.withOpacity(0.2),
          valueIndicatorColor: kAccentColor,
          valueIndicatorTextStyle: const TextStyle(color: Colors.black),
        ),
      ),
      home: HomePage(
        bleService: BleService(), // Asegúrate de inicializar BleService aquí
        initialBleConnected: false,
        initialConnected: false,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final BleService? bleService;
  final bool initialBleConnected;
  final bool initialConnected;
  const HomePage({super.key, this.bleService, this.initialBleConnected = false, this.initialConnected = false});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  void _showSavedDevicesDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder( // Para actualizar nombres dentro del modal
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white24, width: 1)),
          title: const Text('Equipos Guardados', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: _devices.isEmpty 
              ? const Text('No hay equipos guardados aún.', style: TextStyle(color: Colors.white54))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(device.nickname ?? device.serial, 
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(device.nickname != null ? device.serial : 'Sin nombre',
                              style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          if (device.chipId != null && device.chipId!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('ChipID: ' + device.chipId!, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                          ]
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20, color: Colors.white70),
                            onPressed: () async {
                              String? newName = await _showEditNicknameDialog(device);
                              if (newName != null) {
                                await _addOrUpdateDevice(device.serial, nickname: newName);
                                setModalState(() {}); // Actualiza el modal
                                setState(() {}); // Actualiza el dropdown del inicio
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 20, color: Colors.redAccent),
                            onPressed: () async {
                              await _deleteDevice(device.serial);
                              setModalState(() {});
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                      onTap: () {
                        _serialController.text = device.serial;
                        Navigator.pop(context);
                        _connect();
                      },
                    );
                  },
                ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text('CERRAR', style: TextStyle(color: Colors.white70))
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showEditNicknameDialog(DeviceInfo device) async {
    final ctrl = TextEditingController(text: device.nickname);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white24, width: 1)),
        title: Text('Nombre para ${device.serial}', style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Ej: Terraza, Quincho...',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c), 
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white70))
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()), 
            child: const Text('GUARDAR', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
  }
  
  final _serialController = TextEditingController();
  final _mqtt = MqttService();
  final _httpClient = http.Client();
  late final BleService _bleService;
  final _discoveryService = LocalDiscoveryService();

  // Lista de dispositivos conocidos (serial + nickname)
  List<DeviceInfo> _devices = [];
  String? _defaultDeviceSerial;

  /// Ordena `_devices` de modo que el más recientemente visto aparece primero.
  /// Si `lastSeen` está ausente, se considera como muy antiguo.
  void _sortDevices() {
    _devices.sort((a, b) {
      final da = a.lastSeen != null ? DateTime.tryParse(a.lastSeen!) : null;
      final db = b.lastSeen != null ? DateTime.tryParse(b.lastSeen!) : null;
      if (da == null && db == null) return 0;
      if (da == null) return 1; // a es más antiguo
      if (db == null) return -1;
      return db.compareTo(da); // descendente
    });
  }




  String _status = 'Desconectado';
  bool _isConnected = false;
  bool _isDeviceResponding = false;
  StreamSubscription? _subscription;
  StreamSubscription? _bleSubscription;
  Timer? _localStatusTimer;
  Timer? _connectionWatchdogTimer;
  static const int _watchdogSeconds = 8;

  String? _localBaseUrl;
  bool _isBleConnected = false;
  bool get _isLocalAvailable => _localBaseUrl != null;

  final Map<String, String> _mqttToLocalKeyMap = {
    'SetTemp': 'SetTemp',
    'Calefa': 'Calefa',
    'OnOff': 'OnOff',
    'Luces': 'Luces',
  };

  double? _currentTemp;
  double? _setTemp;
  double _maxTemp = 45;
  bool _calefa = false;
  bool _jet = false;
  bool _luces = false;

  // Lock states (true = locked)
  bool _lockSetTemp = false;
  bool _lockCalefa = false;
  bool _lockJets = false;
  bool _lockLuces = false;
  bool _hasPin = false; // Indica si el dispositivo tiene PIN configurado
  String? _sessionPin; // PIN ingresado por el usuario en esta sesión
  double? _tempBeforeChange; // Para revertir el slider si el PIN es incorrecto

  // Debug getters for tests
  double? get debugCurrentTemp => _currentTemp;
  double? get debugSetTemp => _setTemp;
  double get debugMaxTemp => _maxTemp;
  bool get debugJet => _jet;
  bool get debugLuces => _luces;
  bool get debugCalefa => _calefa;
  double? _tHys;
  double? get debugTHys => _tHys;
  bool _isWaitingForData = false;
  String? _lastBleDeviceId;
  String? _lastBleDeviceName;
  bool _wasBleConnectedOnPause = false;
  String? _mqttUserPrefix;
  String? _sessionCode;

  final String _logoUrl = "https://res.cloudinary.com/dhmxtqdsb/image/upload/v1764783911/Hrioki_Blanco_yjpn3z.png";

  bool get _isEcoActive => _setTemp != null && _setTemp == 18.0 && _calefa == true;

  double get _effectiveMaxTemp => _maxTemp > 0 ? _maxTemp : 45;

  void _resetDeviceState() {
    _currentTemp = null;
    _maxTemp = 40;
    _setTemp = null;
    _calefa = false;
    _jet = false;
    _luces = false;
    _tHys = null;
    _lockSetTemp = false;
    _lockCalefa = false;
    _lockJets = false;
    _lockLuces = false;
    _hasPin = false;
    _sessionPin = null;
    _sessionCode = null;
    _isDeviceResponding = false;
  }

  // --- Shared helper for parsing boolean values from incoming data ---
  bool _parseIncomingBool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    final s = value.toString().trim().toLowerCase();
    // Consider 'true', '1', '1.0', 'on' as true
    return s == 'true' || s == '1' || s == '1.0' || s == 'on';
  }

  // --- DEBOUNCE LOGIC ---
  final Map<String, DateTime> _lastInteraction = {};
  bool _shouldIgnoreUpdate(String key) {
    final last = _lastInteraction[key];
    if (last == null) return false;
    return DateTime.now().difference(last).inSeconds < 4;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bleService = widget.bleService ?? BleService();
    _isBleConnected = widget.initialBleConnected;
    _isConnected = widget.initialConnected;
    // If we start with BLE already connected (testing), subscribe to incoming data
    if (_isBleConnected) {
      _bleSubscription = _bleService.dataStream.listen((data) => _handleIncomingData(data));
    }
    _loadSerial();
    _loadLastBleDevice();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _bleSubscription?.cancel();
    _localStatusTimer?.cancel();
    _connectionWatchdogTimer?.cancel();
    _serialController.dispose();
    _mqtt.disconnect();
    _bleService.disconnect();
    _httpClient.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasBleConnectedOnPause = _isBleConnected;
    } else if (state == AppLifecycleState.resumed) {
      // Al volver de reposo: Si BLE estaba conectado, reconectar
      if (_wasBleConnectedOnPause) {
        _quickConnectBle();
        _wasBleConnectedOnPause = false;
      }
      // Si hay un serial cargado, intentar reconectar (la conexión puede haberse perdido en segundo plano)
      if (_serialController.text.isNotEmpty) {
        _autoReconnectOnResume();
      }
    }
  }

  /// Intenta reconectar automáticamente al volver de reposo sin pedir permiso
void _autoReconnectOnResume() async {
  // Si estamos en modo MQTT, verificar activamente si el cliente sigue conectado
  if (!_isBleConnected && !_isLocalAvailable) {
    if (!_mqtt.isConnected) {
      _isConnected = false; 
    }
  }

  if (_isConnected) {
    // Si crees que estás conectado, envía un ping o mensaje de "estoy aquí"
    if (_mqttUserPrefix != null) {
      _mqtt.publish('$_mqttUserPrefix/appConectada', 'true');
    }
    // ... resto de tu lógica
    return;
  }
  
  // Si se detectó desconexión real, reconectar
  await Future.delayed(const Duration(milliseconds: 500));
  if (mounted && !_isConnected) {
    _connect();
  }
}



  Future<void> _loadSerial() async {
    final prefs = await SharedPreferences.getInstance();
    // No cargamos el serial guardado en prefs: la app espera datos nuevos del equipo.

    // Cargar dispositivos conocidos y device por defecto
    final devicesJson = prefs.getString(kDevicesKey) ?? '[]';
    try {
      final list = (jsonDecode(devicesJson) as List).cast<Map<String, dynamic>>();
      _devices = list.map((m) => DeviceInfo.fromJson(m)).toList();
    } catch (_) { _devices = []; }

    // ordenar para que el último visto esté al principio
    _sortDevices();

    _defaultDeviceSerial = prefs.getString(kDefaultDeviceKey);

    // No preseleccionamos el serial por defecto aquí; siempre esperamos datos nuevos del equipo.

    // Leer maxTemp almacenado y usarlo como valor inicial si existe
    final savedMaxTemp = prefs.getDouble(kMaxTempKey);
    if (savedMaxTemp != null && savedMaxTemp > 0) {
      _maxTemp = savedMaxTemp;
    }

    // Leer histeresis almacenada y usarla de inicio si existe
    final savedHysteresis = prefs.getDouble(kHysteresisKey);
    if (savedHysteresis != null && savedHysteresis > 0) {
      _tHys = savedHysteresis;
    }

    // Cargar dispositivo BLE guardado para conexión rápida
    _lastBleDeviceId = prefs.getString('last_ble_device_id');
    _lastBleDeviceName = prefs.getString('last_ble_device_name');

    // Pre-llenar el campo de serial con el último dispositivo usado
    if (_defaultDeviceSerial != null && _defaultDeviceSerial!.isNotEmpty) {
      _serialController.text = _defaultDeviceSerial!;
    }
  }

  Future<void> _loadLastBleDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('last_ble_device_id');
    final name = prefs.getString('last_ble_device_name');
    if (mounted) setState(() { _lastBleDeviceId = id; _lastBleDeviceName = name; });
  }

  void _stopLocalMode() {
    _localStatusTimer?.cancel();
    if (mounted) setState(() => _localBaseUrl = null);
    _bleService.disconnect();
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _devices.map((d) => d.toJson()).toList();
    await prefs.setString(kDevicesKey, jsonEncode(jsonList));
    if (_defaultDeviceSerial != null) await prefs.setString(kDefaultDeviceKey, _defaultDeviceSerial!);
  }

  Future<void> _saveMaxTemp(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(kMaxTempKey, value);
  }

  Future<void> _saveHysteresis(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(kHysteresisKey, value);
  }

  // ignore: unused_element
  // ignore: unused_element
  Future<void> _addOrUpdateDevice(String serial, {String? nickname, String? chipId}) async {
    final idx = _devices.indexWhere((d) => d.serial == serial);
    final now = DateTime.now().toIso8601String();
    if (idx >= 0) {
      final existing = _devices[idx];
      existing.nickname = nickname ?? existing.nickname;
      existing.lastSeen = now;
      if (chipId != null) existing.chipId = chipId;
      _devices[idx] = existing;
    } else {
      _devices.add(DeviceInfo(serial: serial, nickname: nickname, lastSeen: now, chipId: chipId));
    }
    // después de modificar la lista, reordenar para que el más reciente quede al frente
    _sortDevices();

    _defaultDeviceSerial = serial;
    await _saveDevices();
    if (mounted) setState(() {});
  }

  /// Obtiene el ChipID del dispositivo desde 192.168.4.1/settings (cuando está en modo HIROKI_CONFIG)
  Future<String?> _fetchChipId() async {
    try {
      final uri = Uri.http('192.168.4.1', '/settings');
      final response = await _httpClient.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        // Intentar parsear como JSON
        try {
          final data = jsonDecode(response.body);
          if (data is Map && data.containsKey('chipid')) {
            final found = data['chipid'] as String?;
            if (found != null && found.isNotEmpty) {
              try {
                final prefs = await SharedPreferences.getInstance();
                final devicesJson = prefs.getString(kDevicesKey) ?? '[]';
                List<DeviceInfo> devices;
                try {
                  final list = (jsonDecode(devicesJson) as List).cast<Map<String, dynamic>>();
                  devices = list.map((m) => DeviceInfo.fromJson(m)).toList();
                } catch (_) {
                  devices = [];
                }
                final idx = devices.indexWhere((d) => d.serial == found);
                final now = DateTime.now().toIso8601String();
                if (idx >= 0) {
                  devices[idx].lastSeen = now;
                  devices[idx].chipId = found;
                } else {
                  devices.add(DeviceInfo(serial: found, lastSeen: now, chipId: found));
                }
                await prefs.setString(kDevicesKey, jsonEncode(devices.map((d) => d.toJson()).toList()));
                // Auto-select and attempt connection
                if (mounted) {
                  try {
                    setState(() { _serialController.text = found; });
                    await _connect();
                  } catch (_) {}
                }
              } catch (_) {}
            }
            return found;
          }
        } catch (_) {
          // Si no es JSON, intentar extraer de texto plano
          debugPrint('DEBUG: Respuesta HTML recibida (primeros 500 chars): ${response.body.substring(0, math.min(500, response.body.length))}');
          
          // Primero buscar la línea "Nro de serie: <valor>" en la página
          final serialRegex = RegExp(r'Nro de serie[:\s]*([^<\r\n]+)', caseSensitive: false);
          final serialMatch = serialRegex.firstMatch(response.body);
          debugPrint('DEBUG: Búsqueda regex "Nro de serie". Coincidencia: ${serialMatch != null}');
          
          if (serialMatch != null && serialMatch.groupCount > 0) {
            final found = serialMatch.group(1)?.trim();
            debugPrint('DEBUG: ChipID encontrado: $found');
            if (found != null && found.isNotEmpty) {
              try {
                final prefs = await SharedPreferences.getInstance();
                final devicesJson = prefs.getString(kDevicesKey) ?? '[]';
                List<DeviceInfo> devices;
                try {
                  final list = (jsonDecode(devicesJson) as List).cast<Map<String, dynamic>>();
                  devices = list.map((m) => DeviceInfo.fromJson(m)).toList();
                } catch (_) {
                  devices = [];
                }
                final idx = devices.indexWhere((d) => d.serial == found);
                final now = DateTime.now().toIso8601String();
                if (idx >= 0) {
                  devices[idx].lastSeen = now;
                  devices[idx].chipId = found;
                } else {
                  devices.add(DeviceInfo(serial: found, lastSeen: now, chipId: found));
                }
                await prefs.setString(kDevicesKey, jsonEncode(devices.map((d) => d.toJson()).toList()));
                // Auto-select and attempt connection
                if (mounted) {
                  try {
                    setState(() { _serialController.text = found; });
                    await _connect();
                  } catch (_) {}
                }
              } catch (_) {}
            }
            return found;
          }

          // Si no se encontró, caer de nuevo a buscar 'chipid'
          if (response.body.contains('chipid')) {
            final regex = RegExp(r'chipid\\s*[:=]\\s*([A-F0-9a-f]+)', caseSensitive: false);
            final match = regex.firstMatch(response.body);
            if (match != null && match.groupCount > 0) {
              return match.group(1);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error obteniendo ChipID: $e');
    }
    return null;
  }

  // ignore: unused_element
  Future<void> _deleteDevice(String serial) async {
    _devices.removeWhere((d) => d.serial == serial);
    // resort in case order is needed elsewhere
    _sortDevices();
    if (_defaultDeviceSerial == serial) _defaultDeviceSerial = _devices.isNotEmpty ? _devices.first.serial : null;
    await _saveDevices();
    if (mounted) setState(() {});
  }

  // ignore: unused_element
  Future<void> _setDefaultDevice(String serial) async {
    _defaultDeviceSerial = serial;
    await _saveDevices();
    if (mounted) setState(() {});
  }
  
  Future<void> _fetchLocalStatus() async {
    if (!_isLocalAvailable) return;
    try {
      final response = await _httpClient.get(Uri.parse('$_localBaseUrl/status')).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          _isDeviceResponding = true;
          _cancelConnectionWatchdog();

          // Helpers seguros para evitar errores de tipo (String vs Num vs Bool)
          double? parseDouble(dynamic v) => double.tryParse(v?.toString() ?? '');
          bool parseBool(dynamic v, bool current) {
             if (v == null) return current;
             final s = v.toString().toLowerCase();
             return s == 'true' || s == '1';
          }

          _currentTemp = parseDouble(data['TempActual'] ?? data['TA']) ?? _currentTemp;
          
          // Handle maxTemp first
          final localMaxTemp = parseDouble(data['maxTemp'] ?? data['MT']);
          if (localMaxTemp != null) {
            _maxTemp = localMaxTemp;
            _saveMaxTemp(localMaxTemp);
          }
          
          if (!_shouldIgnoreUpdate('SetTemp')) _setTemp = parseDouble(data['SetTemp'] ?? data['TS']) ?? _setTemp;
          final localHys = parseDouble(data['HYS'] ?? data['tHys'] ?? data['THYS']);
          if (localHys != null) {
            _tHys = localHys;
            _saveHysteresis(localHys);
          }
          if (!_shouldIgnoreUpdate('Calefa')) _calefa = _parseIncomingBool(data['Calefa'] ?? data['AC'], defaultValue: _calefa);
          if (!_shouldIgnoreUpdate('OnOff')) _jet = _parseIncomingBool(data['OnOff'] ?? data['EJ'], defaultValue: _jet);
          if (!_shouldIgnoreUpdate('Luces')) _luces = _parseIncomingBool(data['Luces'] ?? data['EL'], defaultValue: _luces);
        });
      } else {
         if (mounted) setState(() => _isDeviceResponding = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isDeviceResponding = false);
    }
  }

Future<void> _connect() async {
  final serial = _serialController.text.trim();
  if (serial.isEmpty) return;
  
  _resetDeviceState();
  setState(() => _status = 'Buscando dispositivo...');
  _isWaitingForData = true;

  // Intentar conexión local o MQTT
  final localUrl = await _discoveryService.discover(serial);
  bool isConnectedNow = false;

  if (localUrl != null) {
    setState(() {
      _status = 'Modo Local';
      _localBaseUrl = localUrl;
      isConnectedNow = true;
    });
    _localStatusTimer?.cancel();
    _localStatusTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchLocalStatus());
    _connectMqtt(serial, isFallback: true);
  } 

  if (isConnectedNow) {
    // Agregamos o actualizamos el dispositivo conocido, pero no guardamos el serial actual en prefs.
    await _addOrUpdateDevice(serial); 
  }
} 

  Future<void> _connectMqtt(String serial, {bool isFallback = false}) async {
    _resetDeviceState();
    if (!isFallback) setState(() => _status = 'Conectando Nube...');
    final ok = await _mqtt.connect(serial);
    if (ok) {
      // reset device responding flag and start watchdog
      _isDeviceResponding = false;
      _connectionWatchdogTimer?.cancel();

      _mqttUserPrefix = 'Hiroki${serial.toLowerCase()}';
      // IMPORTANTE: Primero configurar el listener para no perder mensajes retenidos que llegan inmediatamente
      _setupMqttListener();
      // Luego suscribirse a los tópicos
      _subscribeAll();
      // Notificar al dispositivo que la app está conectada para que envíe el estado completo
      _mqtt.publish('$_mqttUserPrefix/appConectada', 'true');
      if (mounted) {
        setState(() {
          if (!isFallback) _status = 'Conectado';
          _isConnected = true;
        });
      }

      // ADD THIS LINE: Save device when MQTT connection succeeds
      await _addOrUpdateDevice(serial);

      // start watchdog waiting for device to send status/messages
      _startConnectionWatchdog();
    } else if (mounted && !_isLocalAvailable && !isFallback) {
      _showConnectionHelpDialog(serial);
    }
  }

  Future<void> _connectFromDropdown() async {
    final serial = _serialController.text.trim();
    if (serial.isEmpty) return;


    // Si Bluetooth está disponible, intentamos encontrar el dispositivo por nombre (hiroki<serial>)
    final btOn = await _bleService.isBluetoothOn();
    if (btOn) {
      // Mostrar diálogo de búsqueda
      if (!mounted) return;
      showDialog(
        context: context, 
        barrierDismissible: false, 
        builder: (c) => AlertDialog(
          backgroundColor: Colors.black, 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white24, width: 1)),
          title: const Text('Buscando dispositivo...', style: TextStyle(color: Colors.white)), 
          content: SizedBox(
            height: 90, 
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min, 
                children: const [
                  CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(kAccentColor)), 
                  SizedBox(height: 16), 
                  Text('Escaneando Bluetooth...', style: TextStyle(color: Colors.white70))
                ]
              )
            )
          )
        )
      );

      final found = Completer<BluetoothDevice?>();
      StreamSubscription? sub;
      sub = _bleService.scanResults.listen((lists) {
        for (var r in lists) {
          try {
            final dev = r.device;
            final nameStr = dev.platformName.isNotEmpty ? dev.platformName : dev.name;
            if (nameStr != null && nameStr.toLowerCase().contains(('hiroki' + serial).toLowerCase())) {
              found.complete(dev);
              return;
            }
          } catch (_) {}
        }
      });

      try {
        await _bleService.startScan();
      } catch (_) {}

      try {
        final dev = await found.future.timeout(const Duration(seconds: 8));
        await _bleService.stopScan();
        Navigator.pop(context); // close dialog
        if (sub != null) await sub.cancel();
        if (dev != null) {
          _connectBle(dev);
          return;
        }
      } catch (_) {
        if (sub != null) await sub.cancel();
        await _bleService.stopScan();
        if (!mounted) return;
        Navigator.pop(context); // close dialog
        // No encontrado por BLE -> conectar por MQTT según requerimiento
        await _connectMqtt(serial);
        return;
      }
    } else {
      // Bluetooth no disponible -> conectar por MQTT
      await _connectMqtt(serial);
      return;
    }
  }

  void _showConnectionHelpDialog(String serial, {String title = 'Sin Conexión'}) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white24, width: 1)),
        title: Text(title),
        content: Text('No se pudo conectar a la nube. ¿Desea buscar el equipo Hiroki$serial por Bluetooth?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR', style: TextStyle(color: Colors.white70))),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _startBleDiscovery();
            },
            child: const Text('BUSCAR BLUETOOTH', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _startBleDiscovery() async {
    // Antes de pedir permisos, verificamos que el Bluetooth esté encendido
    final btOn = await _bleService.isBluetoothOn();
    if (!btOn) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white24, width: 1)),
          title: const Text('Bluetooth desactivado', style: TextStyle(color: Colors.white)),
          content: const Text('Bluetooth parece estar apagado. Por favor habilítelo en configuración del sistema y presione Reintentar.', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('CANCELAR', style: TextStyle(color: Colors.white70))),
            TextButton(
              onPressed: () async {
                Navigator.pop(c);
                if (Platform.isAndroid) {
                  try {
                    const channel = MethodChannel('com.hiroki.intent');
                    await channel.invokeMethod('openBluetoothSettings');
                  } catch (e) {
                    await openAppSettings();
                  }
                } else {
                  await openAppSettings();
                }
              },
              child: const Text('ABRIR AJUSTES BT', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                _startBleDiscovery();
              },
              child: const Text('REINTENTAR', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    // Solicitamos permisos necesarios para Bluetooth (Android 12+: BLUETOOTH_SCAN, BLUETOOTH_CONNECT)
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    final scanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    final connectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? false;

    // Si permisos permanentes denegados, sugerir abrir configuración con acción directa
    if (statuses[Permission.bluetoothScan]?.isPermanentlyDenied == true || statuses[Permission.bluetoothConnect]?.isPermanentlyDenied == true) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white24, width: 1)),
          title: const Text('Permisos', style: TextStyle(color: Colors.white)),
          content: const Text('Permisos de Bluetooth denegados permanentemente. Abre la configuración de la app y habilítalos.', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('CANCELAR', style: TextStyle(color: Colors.white70))),
            TextButton(
              onPressed: () async {
                Navigator.pop(c);
                await openAppSettings();
              },
              child: const Text('ABRIR AJUSTES', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    // Requerir permisos de escaneo y conexión (ubicación puede ser necesaria en dispositivos antiguos)
    if (!scanGranted || !connectGranted) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white24, width: 1)),
          title: const Text('Permisos', style: TextStyle(color: Colors.white)),
          content: const Text('Se requieren permisos BLUETOOTH_SCAN y BLUETOOTH_CONNECT para escanear y conectar. Puedes abrir los ajustes de la app o intentar solicitarlos nuevamente.', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('CANCELAR', style: TextStyle(color: Colors.white70))),
            TextButton(
              onPressed: () async {
                Navigator.pop(c);
                // Intentar solicitar permisos de nuevo
                await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
                // Reintentar descubrir si permisos fueron concedidos
                _startBleDiscovery();
              },
              child: const Text('SOLICITAR PERMISOS', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(c);
                await openAppSettings();
              },
              child: const Text('ABRIR AJUSTES', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => BleScanScreen(bleService: _bleService)),
      ).then((device) {
        if (device != null && device is BluetoothDevice) {
          _connectBle(device);
        }
      });
    }
  }

  Future<void> _connectBle(BluetoothDevice device) async {
    _resetDeviceState();
    setState(() => _status = 'Conectando Bluetooth...');
    _isWaitingForData = true;
    final success = await _bleService.connect(device);
    
    if (success) {
      // Extraer serial del nombre si es posible "hiroki<serial>"
      String name = device.platformName; // o device.name
      if (name.length > 6 && name.toLowerCase().startsWith('hiroki')) {
        String serial = name.substring(6);
        if (serial.isNotEmpty) {
          await _addOrUpdateDevice(serial);
        }
      }

      setState(() {
        _isConnected = true;
        _isBleConnected = true;
        _status = 'Conectado por Bluetooth';
        _isDeviceResponding = true;
      });

      // Guardar dispositivo BLE para reconexiones rápidas
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_ble_device_id', device.id.id);
        final _deviceName = device.platformName.isNotEmpty ? device.platformName : device.name;
        await prefs.setString('last_ble_device_name', _deviceName);
        if (mounted) setState(() { _lastBleDeviceId = device.id.id; _lastBleDeviceName = _deviceName; });
      } catch (_) {}

      // Cancel watchdog since BLE connected and device is responding
      _cancelConnectionWatchdog();

      // Escuchar datos que vienen del BLE (Notificaciones)
      _bleSubscription?.cancel();
      _bleSubscription = _bleService.dataStream.listen((data) {
        // data es un Map<String, dynamic> decodificado del JSON o STATUS
        _handleIncomingData(data);
      });

      // Pedir explícitamente el estado al dispositivo vía BLE. Esp32 debe responder con
      // "STATUS:TA,TS,Jets,Luces,Calefa,MT,HYS" donde Jets/Luces/Calefa = 1 o 0 y HYS es tHys (hysteresis)
      try {
        final sent = await _bleService.sendCommand('STATUS', '?');
        if (!sent) {
          print('WARN: STATUS command not sent (BLE write failed). Reintentando en 1s');
          Timer(const Duration(seconds: 1), () async {
            final retry = await _bleService.sendCommand('STATUS', '?');
            if (!retry) print('WARN: Reintento de STATUS falló');
          });
        }
      } catch (e) {
        print('Error enviando STATUS: $e');
      }

    } else {
      setState(() => _status = 'Error de conexión BLE');
      _showSimpleDialog('Error', 'No se pudo conectar al dispositivo Bluetooth.');
    }
  }

  Future<void> _quickConnectBle() async {
    if (_lastBleDeviceId == null && _lastBleDeviceName == null) {
      _showSimpleDialog('No hay dispositivo guardado', 'No se encontró un dispositivo BLE guardado para reconectar.');
      return;
    }

    if (!await _bleService.startScan()) {
      _showSimpleDialog('Bluetooth', 'No se pudo iniciar el escaneo BLE. Verifique que Bluetooth esté activo.');
      return;
    }

    // Mostrar dialog de búsqueda
    if (!mounted) return;
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (c) => AlertDialog(
        backgroundColor: Colors.black, 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white24, width: 1)),
        title: const Text('Buscando dispositivo guardado...', style: TextStyle(color: Colors.white)), 
        content: SizedBox(
          height: 90, 
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min, 
              children: const [
                CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(kAccentColor)), 
                SizedBox(height: 16), 
                Text('Escaneando...', style: TextStyle(color: Colors.white70))
              ]
            )
          )
        )
      )
    );

    final found = Completer<BluetoothDevice?>();
    StreamSubscription? sub;
    sub = _bleService.scanResults.listen((lists) {
      for (var r in lists) {
        try {
          final dev = r.device;
          final idStr = dev.id.id;
          final nameStr = dev.platformName.isNotEmpty ? dev.platformName : dev.name;
          if ((_lastBleDeviceId != null && _lastBleDeviceId == idStr) || (_lastBleDeviceName != null && _lastBleDeviceName == nameStr)) {
            found.complete(dev);
            return;
          }
        } catch (_) {}
      }
    });

    try {
      final dev = await found.future.timeout(const Duration(seconds: 8));
      await _bleService.stopScan();
      Navigator.pop(context); // close scanning dialog
      await sub.cancel();
      if (dev != null) {
        _connectBle(dev);
        return;
      }
    } catch (_) {
      await sub.cancel();
      await _bleService.stopScan();
      if (!mounted) return;
      Navigator.pop(context); // close scanning dialog
      _showSimpleDialog('No encontrado', 'No se pudo encontrar el dispositivo guardado durante el escaneo.');
      return;
    }
  }

  void _handleIncomingData(Map<String, dynamic> data) {
    if (!mounted) return;

    // If this is a STATUS map from BLE: it will contain 'TA','TS','MT','Jets','Luces','Calefa'
    if (data.containsKey('TA') || (data['topic'] == 'STATUS')) {
      if (!mounted) return;
      setState(() {
        double? tryDouble(dynamic v) => double.tryParse(v?.toString() ?? '');
        // REMOVED: bool fromOne(String? s) { ... } // This was causing the error
        
        _currentTemp = tryDouble(data['TA']) ?? _currentTemp;
        
        // FIX: Ensure maxTemp is updated first, then setTemp is clamped to it
        final double newMaxTemp = tryDouble(data['MT']) ?? _maxTemp;
        _maxTemp = newMaxTemp;
        
        if (!_shouldIgnoreUpdate('SetTemp')) _setTemp = tryDouble(data['TS']) ?? _setTemp;
        
        // Using the new _parseIncomingBool method
        if (!_shouldIgnoreUpdate('Calefa')) _calefa = _parseIncomingBool(data['Calefa'] ?? data['AC'], defaultValue: _calefa);
        if (!_shouldIgnoreUpdate('OnOff')) _jet = _parseIncomingBool(data['OnOff'] ?? data['EJ'], defaultValue: _jet);
        if (!_shouldIgnoreUpdate('Luces')) _luces = _parseIncomingBool(data['Luces'] ?? data['EL'], defaultValue: _luces);
        // tHys (hysteresis) optional last field
        final double? newHys = tryDouble(data['HYS'] ?? data['tHys'] ?? data['THYS']);
        if (newHys != null) {
          _tHys = newHys;
          _saveHysteresis(newHys);
        }
        
        // Locks (using default false for locks if value is null)
        if (data.containsKey('L_Temp')) _lockSetTemp = _parseIncomingBool(data['L_Temp']?.toString());
        if (data.containsKey('L_Cal')) _lockCalefa = _parseIncomingBool(data['L_Cal']?.toString());
        if (data.containsKey('L_Jets')) _lockJets = _parseIncomingBool(data['L_Jets']?.toString());
        if (data.containsKey('L_Luces')) _lockLuces = _parseIncomingBool(data['L_Luces']?.toString());
        if (data.containsKey('HasPin')) _hasPin = _parseIncomingBool(data['HasPin']?.toString());

        // mark device as responding
        _isDeviceResponding = true;
        _cancelConnectionWatchdog();
        _isWaitingForData = false;
      });
      return;
    }

    // Otherwise we expect messages with {"topic":"X","payload":"Y"}
    final topic = data['topic'] as String? ?? '';
    final payload = data['payload'].toString(); // Corrección: Evita crash si llega un número

    // Special case: the device may send a 'serial' key via BLE when Wi-Fi is configured
    if (topic.toLowerCase() == 'serial' && payload.isNotEmpty) {
      (() async {
        final prefs = await SharedPreferences.getInstance();

        // Añadir a la lista de dispositivos conocidos
        final devicesJson = prefs.getString(kDevicesKey) ?? '[]';
        List<DeviceInfo> devices;
        try {
          final list = (jsonDecode(devicesJson) as List).cast<Map<String, dynamic>>();
          devices = list.map((m) => DeviceInfo.fromJson(m)).toList();
        } catch (_) { devices = []; }
        final idx = devices.indexWhere((d) => d.serial == payload);
        final now = DateTime.now().toIso8601String();
        if (idx >= 0) {
          devices[idx].lastSeen = now;
        } else {
          devices.add(DeviceInfo(serial: payload, lastSeen: now));
        }
        await prefs.setString(kDevicesKey, jsonEncode(devices.map((d) => d.toJson()).toList()));

        if (mounted) setState(() => _status = 'Serial detectado vía BLE: $payload');

        // Iniciar un timer para intentar conexión MQTT con este serial
        _connectionWatchdogTimer?.cancel(); // Cancelar cualquier watchdog existente
        _connectionWatchdogTimer = Timer(const Duration(seconds: 20), () {
          _connectMqtt(payload); // Intentar conectar por MQTT
        });

      })();

      // mark responding and exit
      if (mounted) setState(() { _isDeviceResponding = true; _cancelConnectionWatchdog(); });
      return;
    }

    if (topic == 'SESSION_CODE') {
      _sessionCode = payload;
      _isDeviceResponding = true;
      _cancelConnectionWatchdog();
      return;
    }

    setState(() {
      if (topic.contains('TempActual')) _currentTemp = double.tryParse(payload);
      
      // FIX: Ensure maxTemp is updated and setTemp is clamped to it
      if (topic.contains('maxTemp')) {
        final double newMaxTemp = double.tryParse(payload) ?? _maxTemp;
        _maxTemp = newMaxTemp;
        // Removed clamp to allow setTemp to exceed maxTemp for display
        _saveMaxTemp(newMaxTemp);
      }
      
      if (topic.contains('SetTemp') && !_shouldIgnoreUpdate('SetTemp')) {
        final val = double.tryParse(payload);
        if (val != null && val > 0) _setTemp = val;  // Don't clamp here, clamp when maxTemp is known
      }
      
      // REMOVED: bool isTrue(String val) { ... }
      
      if (topic.contains('Calefa') && !_shouldIgnoreUpdate('Calefa')) _calefa = _parseIncomingBool(payload);
      if (topic.contains('OnOff') && !_shouldIgnoreUpdate('OnOff')) _jet = _parseIncomingBool(payload);
      if (topic.contains('Luces') && !_shouldIgnoreUpdate('Luces')) _luces = _parseIncomingBool(payload);

      if (topic.contains('locks/SetTemp')) _lockSetTemp = _parseIncomingBool(payload);
      if (topic.contains('locks/Calefa')) _lockCalefa = _parseIncomingBool(payload);
      if (topic.contains('locks/OnOff')) _lockJets = _parseIncomingBool(payload);
      if (topic.contains('locks/Luces')) _lockLuces = _parseIncomingBool(payload);
      if (topic.contains('HasPin')) _hasPin = _parseIncomingBool(payload);
      if (topic.contains('SESSION_CODE')) _sessionCode = payload;
    });
  }

  Future<List<String>> _getWifiList() async {
    final List<String> results = [];

    // If BLE connected, ask the device first
    if (_isBleConnected && _bleService.isConnected) {
      final comp = Completer<List<String>>();
      StreamSubscription? sub;
      sub = _bleService.dataStream.listen((data) {
        try {
          final topic = (data['topic'] ?? '').toString();
          if (topic == 'WIFI_LIST' || topic == 'WIFI_SCAN') {
            dynamic payload = data['payload'];
            List<String> ssids = [];
            if (payload is String) {
              final s = payload.trim();
              if (s.startsWith('[')) {
                try {
                  final parsed = jsonDecode(s);
                  if (parsed is List) ssids = parsed.map((e) => e.toString()).toList();
                } catch (_) {}
              } else {
                ssids = s.split(RegExp(r'[,:]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
              }
            } else if (payload is List) {
              ssids = payload.map((e) => e.toString()).toList();
            }

            sub?.cancel();
            comp.complete(ssids);
          }
        } catch (_) {}
      });

      try {
        await _bleService.sendCommand('WIFI_SCAN', '?');
      } catch (_) {}

      try {
        final got = await comp.future.timeout(const Duration(seconds: 8));
        results.addAll(got);
      } catch (_) {
        await sub.cancel();
      }

      if (results.isNotEmpty) return results.toSet().toList()..sort();
    }

    // Fallback: local scan (requires location permission)
    try {
      if (await Permission.location.request().isDenied) return [];
      final list = await WiFiForIoTPlugin.loadWifiList();
      for (final item in list) {
        try {
          final ss = item.ssid;
          if (ss != null && ss.toString().isNotEmpty) results.add(ss.toString());
        } catch (_) {}
      }
      return results.toSet().toList()..sort();
    } catch (_) {
      return [];
    }
  }

  Future<void> _showSendCredentialsDialog(String ssid) async {
    final passCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white24, width: 1)),
        title: Text('Enviar credenciales a "$ssid"', style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('SSID seleccionado:\n$ssid', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl, 
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
              ), 
              obscureText: true
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false), 
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white70))
          ),
          TextButton(
            onPressed: () async {
              final pass = passCtrl.text; // Capturamos el texto antes de cerrar
              Navigator.pop(c, true); // Cierra el diálogo de contraseña
              if (!mounted) return;
              final ok = await _bleService.sendCommand('setup/wifi|${ssid}|${pass}', '');
              _onWifiCredentialsSent(ok);
            }, 
            child: const Text('ENVIAR', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
    passCtrl.dispose();
    return ok == true ? Future.value() : Future.value();
  }

  Future<void> _onWifiCredentialsSent(bool success) async {
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Credenciales enviadas. El equipo se reiniciará. Intentando nueva conexión en 15 segundos...'),
        duration: Duration(seconds: 14),
      ));

      await Future.delayed(const Duration(seconds: 15));
      if (!mounted) return;

      // Disconnect from current BLE session
      _bleService.disconnect();
      _bleSubscription?.cancel();
      
      // Reset state to show login screen and trigger a new connection attempt
      setState(() {
        _isConnected = false;
        _isBleConnected = false;
        _localBaseUrl = null;
        _status = 'Desconectado';
      });

      // Give UI a moment to switch to login screen
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;

      // Trigger a full connection cycle (mDNS -> MQTT)
      await _connect();
    } else {
      _showSimpleDialog('Error', 'No se pudieron enviar las credenciales al equipo.');
    }
  }

  Future<void> _showBleWifiConfigDialog() async {
    // Show a scanning dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white24, width: 1)),
        title: const Text('Buscando redes Wi‑Fi...', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          height: 90, 
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min, 
              children: const [
                CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(kAccentColor)), 
                SizedBox(height: 16), 
                Text('Escaneando...', style: TextStyle(color: Colors.white70))
              ]
            )
          )
        ),
      ),
    );

    final ssids = await _getWifiList();
    if (!mounted) return;
    Navigator.pop(context); // close scanning dialog

    if (ssids.isEmpty) {
      // Offer manual entry if nothing found
      final manual = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white24, width: 1)),
          title: const Text('No se encontraron redes', style: TextStyle(color: Colors.white)),
          content: const Text('No se detectaron redes vía BLE ni localmente. ¿Desea ingresar el SSID manualmente?', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('CANCELAR', style: TextStyle(color: Colors.white70))),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('MANUAL', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold))),
          ],
        ),
      );

      if (manual == true) {
        // Show manual SSID dialog
        final ssidCtrl = TextEditingController();
        final passCtrl = TextEditingController();
        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white24, width: 1)),
            title: const Text('Configurar Wi‑Fi del Equipo', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min, 
              children: [
                TextField(
                  controller: ssidCtrl, 
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'SSID (Nombre Red)',
                    labelStyle: TextStyle(color: Colors.white60),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
                  )
                ), 
                TextField(
                  controller: passCtrl, 
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    labelStyle: TextStyle(color: Colors.white60),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
                  ), 
                  obscureText: true
                )
              ]
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c), 
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white70))
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(c);
                  if (!mounted) return;
                  final ok = await _bleService.sendCommand('setup/wifi|${ssidCtrl.text}|${passCtrl.text}', '');
                  _onWifiCredentialsSent(ok);
                }, 
                child: const Text('ENVIAR', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold))
              ),
            ],
          ),
        );
        ssidCtrl.dispose();
        passCtrl.dispose();
      }

      return;
    }

    // Show list of networks to choose from
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white24, width: 1)),
        title: const Text('Redes disponibles', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: ssids.length + 1,
            itemBuilder: (context, index) {
              if (index == ssids.length) {
                return ListTile(
                  leading: const Icon(Icons.edit, color: Colors.white60),
                  title: const Text('Ingresar SSID manualmente', style: TextStyle(color: Colors.white)),
                  onTap: () { Navigator.pop(context); _showBleWifiConfigDialog(); },
                );
              }
              final ss = ssids[index];
              return ListTile(
                leading: const Icon(Icons.wifi, color: kAccentColor),
                title: Text(ss, style: const TextStyle(color: Colors.white)),
                onTap: () { Navigator.pop(context); _showSendCredentialsDialog(ss); },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    _stopLocalMode();
    _mqtt.disconnect();
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isBleConnected = false;
        _status = 'Desconectado';
        _isWaitingForData = false;
      });
    }
  }

  Future<void> _launchUrl(String url) async {
    final browser = ChromeSafariBrowser();
    await browser.open(url: WebUri(url));
  }

  // --- UI HELPER ---
  void _showSimpleDialog(String title, String content, {bool showSpinner = false}) {
    showDialog(
      context: context,
      barrierDismissible: !showSpinner,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white24, width: 1)),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Row(
          children: [
            if (showSpinner) ...[
              const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(kAccentColor)), 
              const SizedBox(width: 20)
            ],
            Expanded(child: Text(content, style: const TextStyle(color: Colors.white70))),
          ],
        ),
        actions: showSpinner ? [] : [
          TextButton(
            onPressed: () => Navigator.pop(c), 
            child: const Text('OK', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold))
          )
        ],
      ),
    );
  }

  // --- LÓGICA DE CONTROL (MQTT / LOCAL) ---
  Future<void> _publishSetTemp(double value) async {
    // FIX: Clamp value to valid range before sending
    final clampedValue = value.clamp(10, _effectiveMaxTemp);
    
    // If value was clamped, update UI and show message
    if (clampedValue != value) {
      setState(() => _setTemp = clampedValue.toDouble()); // Convert to double
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('La temperatura no puede exceder ${_effectiveMaxTemp.toInt()}°C'))
      );
      return;
    }

    // Verificar bloqueo
    if (_lockSetTemp) {
      bool auth = await _checkOrRequestPin();
      if (!auth) {
        // Revertir slider visualmente si no se autorizó
        setState(() {
          _setTemp = _tempBeforeChange;
          if (_tempBeforeChange != null) {
            _setTemp = _tempBeforeChange;
          }
        }); 
        return;
      }
    }

    _lastInteraction['SetTemp'] = DateTime.now();
    String payload = value.toInt().toString();
    if (_lockSetTemp && _sessionPin != null) {
      payload += '|$_sessionPin'; // Adjuntar PIN
    }

    if (_isBleConnected) {
      // Enviar por BLE
      _bleService.sendCommand('SetTemp', payload);
    } else if (_isLocalAvailable) {
      _sendLocalCommand(_mqttToLocalKeyMap['SetTemp']!, payload);
    } else if (_mqtt.isConnected) {
      // Publicar solo en el canal estándar 'app/SetTemp/value/set'
            final topic = _mqttTopicForCommand('SetTemp');
      if (topic.isNotEmpty) {
        debugPrint('MQTT publish -> $topic : $payload (session ${_sessionCode == null ? "missing" : "present"})');
        _mqtt.publish(topic, payload);
      }
    }
  }

  Future<void> _toggleAndPublish(String key, bool val) async {
    // Verificar bloqueo antes de actuar
    bool isLocked = false;
    if (key == 'Calefa') isLocked = _lockCalefa;
    if (key == 'OnOff') isLocked = _lockJets;
    if (key == 'Luces') isLocked = _lockLuces;

    if (isLocked) {
      bool auth = await _checkOrRequestPin();
      if (!auth) {
        setState(() {}); // Forzar actualización para revertir el switch visualmente
        return; 
      }
    }

    _lastInteraction[key] = DateTime.now();
    // MQTT uses true/false strings, but over BLE we send 1/0 per device expectation
    final mqttPayload = val ? 'true' : 'false';
    final blePayload = val ? '1' : '0';
    
    String finalBle = blePayload;
    String finalMqtt = mqttPayload;

    if (isLocked && _sessionPin != null) {
      finalBle += '|$_sessionPin';
      finalMqtt += '|$_sessionPin';
    }

    if (_isBleConnected) {
      // Enviar por BLE con 1/0
      _bleService.sendCommand(key, finalBle);
    } else if (_isLocalAvailable) {
      // Local endpoint expects values similar to MQTT (true/false or value)
      _sendLocalCommand(_mqttToLocalKeyMap[key]!, finalMqtt);
    } else if (_mqtt.isConnected) {
      // Publicar solo en el canal estándar 'app/.../value/set'
            final topic = _mqttTopicForCommand(key);
      if (topic.isNotEmpty) {
        debugPrint('MQTT publish -> $topic : $finalMqtt (session ${_sessionCode == null ? "missing" : "present"})');
        _mqtt.publish(topic, finalMqtt);
      }
    }
    
    // Actualizar UI optimista
    setState(() {
      if (key == 'Calefa') _calefa = val;
      if (key == 'OnOff') _jet = val;
      if (key == 'Luces') _luces = val;
    });
  }

  void _handleButtonPress(String key, bool value) {
    if (!_isConnected && !_isBleConnected && !_isLocalAvailable) {
      // Si no hay ninguna conexión activa, intentamos reconectar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reconectando...'), duration: Duration(seconds: 1)),
      );

      _connect().then((_) {
        if (_isConnected || _isBleConnected || _isLocalAvailable) {
          _toggleAndPublish(key, value);
        }
      });
      return;
    }

    // Si ya estamos conectados por cualquier medio, enviamos la acción
    _toggleAndPublish(key, value);
  }

  Future<bool> _checkOrRequestPin() async {
    if (_sessionPin != null && _sessionPin!.isNotEmpty) return true;
    
    final pinController = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Función Bloqueada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingrese su PIN para usar esta función en este dispositivo.'),
            const SizedBox(height: 10),
            TextField(
              controller: pinController,
              decoration: const InputDecoration(labelText: 'PIN (6 dígitos)', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('CANCELAR')),
          TextButton(onPressed: () => Navigator.pop(c, pinController.text), child: const Text('DESBLOQUEAR')),
        ],
      ),
    );

    if (pin != null && pin.isNotEmpty) {
      _sessionPin = pin;
      return true;
    }
    return false;
  }

  Future<void> _sendLocalCommand(String varName, String value) async {
    try {
      await _httpClient.get(Uri.parse('$_localBaseUrl/control_local?var=$varName&val=$value'))
          .timeout(const Duration(seconds: 4));
      _fetchLocalStatus();
    } catch (e) {
      debugPrint('Error enviando comando local: $e');
    }
  }

  void _subscribeAll() {
    if (_mqttUserPrefix == null) return;
    for (var t in ['TempActual', 'maxTemp', 'SetTemp', 'HYS', 'Calefa', 'OnOff', 'Luces', 'SESSION_CODE']) {
      _mqtt.subscribe('$_mqttUserPrefix/app/$t/value/set');
      // Suscribirse también al estado (value) para recibir actualizaciones del dispositivo (ej: Temperatura)
      _mqtt.subscribe('$_mqttUserPrefix/app/$t/value');
      _mqtt.subscribe('$_mqttUserPrefix/app/locks/$t'); // Suscribirse a bloqueos
    }
    _mqtt.subscribe('$_mqttUserPrefix/app/HasPin');
  }

  void _setupMqttListener() {
    _subscription?.cancel();
    _subscription = _mqtt.messages.listen((msg) {
      if (_isLocalAvailable || _isBleConnected) return; // Prioridad a local/BLE
      final topic = msg.topic;
      final m = msg.payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(m.payload.message).trim();
      if (!mounted) return;
      setState(() {
        // Mark device as responding when we get any MQTT message
        _isDeviceResponding = true;
        _cancelConnectionWatchdog();

        if (topic.contains('TempActual')) _currentTemp = double.tryParse(payload);
        if (topic.contains('maxTemp')) {
          final value = double.tryParse(payload);
          if (value != null) {
            _maxTemp = value;
            // Clamp setTemp to 40
            if (_setTemp != null) {
              _setTemp = _setTemp!.clamp(10, 45);
            }
            _saveMaxTemp(value);
          }
        }
        if (topic.contains('HYS') || topic.contains('hysteresis')) {
          final value = double.tryParse(payload);
          if (value != null) {
            _tHys = value;
            _saveHysteresis(value);
          }
        }
        if (topic.contains('SetTemp') && !topic.contains('locks') && !_shouldIgnoreUpdate('SetTemp')) {
          final val = double.tryParse(payload);
          if (val != null && val > 0) _setTemp = val.clamp(10, 45);
        }
        if (topic.contains('Calefa') && !topic.contains('locks') && !_shouldIgnoreUpdate('Calefa')) _calefa = _parseIncomingBool(payload);
        if (topic.contains('OnOff') && !topic.contains('locks') && !_shouldIgnoreUpdate('OnOff')) _jet = _parseIncomingBool(payload);
        if (topic.contains('Luces') && !topic.contains('locks') && !_shouldIgnoreUpdate('Luces')) _luces = _parseIncomingBool(payload);

        if (topic.contains('locks/SetTemp')) _lockSetTemp = _parseIncomingBool(payload);
        if (topic.contains('locks/Calefa')) _lockCalefa = _parseIncomingBool(payload);
        if (topic.contains('locks/OnOff')) _lockJets = _parseIncomingBool(payload);
        if (topic.contains('locks/Luces')) _lockLuces = _parseIncomingBool(payload);
        if (topic.contains('HasPin')) _hasPin = _parseIncomingBool(payload);
        if (topic.contains('SESSION_CODE')) _sessionCode = payload;
      });
      if (_isWaitingForData) _isWaitingForData = false;
    });
  }

  void _startConnectionWatchdog() {
    _connectionWatchdogTimer?.cancel();
    _connectionWatchdogTimer = Timer(Duration(seconds: _watchdogSeconds), () {
      _onConnectionTimeout();
    });
  }

  void _cancelConnectionWatchdog() {
    _connectionWatchdogTimer?.cancel();
    _connectionWatchdogTimer = null;
  }

  void _onConnectionTimeout() {
    // If device hasn't responded via any channel, inform user and logout
    if (_isDeviceResponding || _isBleConnected || _isLocalAvailable) return;
    _logout();
    if (mounted) {
      _showSimpleDialog('Sin respuesta', 'No se recibió respuesta del equipo. Volviendo al inicio.');
    }
  }

  // Debug helper used by tests to directly invoke toggles without UI interaction
  void debugSendToggle(String key, bool val) {
    // Update local visible state for convenience
    if (key == 'Luces') _luces = val;
    if (key == 'Calefa') _calefa = val;
    if (key == 'OnOff') _jet = val;
    _toggleAndPublish(key, val);
    if (mounted) setState(() {});
  }

  // --- RECONSTRUCCIÓN DE UI (Mantenida de tu versión) ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Asegura un fondo negro al inicio de la aplicación
      body: SafeArea(child: _isConnected ? _buildControlPanel() : _buildLoginScreen()),
    );
  }

  Widget _buildLoginScreen() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.network(
              _logoUrl, 
              height: 100,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.broken_image, size: 50, color: Colors.white24);
              },
            ),
            const SizedBox(height: 60),

            // Dropdown con los dispositivos conocidos
            if (_devices.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: _devices.any((d) => d.serial == _serialController.text) ? _serialController.text : null,
                items: _devices.map((d) => DropdownMenuItem(value: d.serial, child: Text(d.displayName()))).toList(),
                onChanged: (v) => setState(() { if (v != null) _serialController.text = v; }),
                decoration: const InputDecoration(labelText: 'Dispositivo conocido'),
              ),
              const SizedBox(height: 14),
            ],

            TextField(
              controller: _serialController,
              decoration: const InputDecoration(
                labelText: 'Número de Serie',
                hintText: 'Ingrese ID del equipo',
                prefixIcon: Icon(Icons.vpn_key),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            // Botones principales: Conectar | Buscar equipos
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _connectFromDropdown,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white, 
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('CONECTAR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                ),
                const SizedBox(width: 10),
                // Botón de Escaneo BLE existente
                OutlinedButton(
                  onPressed: _startBleDiscovery, 
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(14),
                  ),
                  child: const Icon(Icons.bluetooth_searching, size: 20)
                ),
                const SizedBox(width: 10),
                // NUEVO BOTÓN: Guardados
                OutlinedButton(
                  onPressed: _showSavedDevicesDialog, 
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(14),
                  ),
                  child: const Icon(Icons.history, color: Colors.white)
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Botón para configurar por Wi-Fi sin Bluetooth
            SizedBox(
              width: double.infinity,
              child: Center(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const HirokiConfigPage()));
                  },
                  icon: const Icon(Icons.wifi_tethering, color: Colors.white60, size: 18),
                  label: const Text('Hiroki sin Bluetooth', style: TextStyle(color: Colors.white60)),
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    Widget content;
    if (isLandscape) {
      content = Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 60% Izquierda: Temperatura + SetTemp + Footer
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 10, 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                _buildTemperatureCard(),
                                const SizedBox(height: 20),
                                _buildFooterLinks(),
                                const SizedBox(height: 20),
                                if (_isBleConnected) ...[
                                  _buildWifiConfigButton(),
                                  const SizedBox(height: 20),
                                ],
                                _buildExitButton(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        _buildVerticalTargetTempCard(),
                      ],
                    ),
                  ),
                ),
                // 40% Derecha: Botones 2x2
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(10, 0, 20, 20),
                    child: _buildActionGrid(isLandscape: true),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
  } else {
    content = Column(
      children: [
        _buildHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _buildTemperatureCard(),
                const SizedBox(height: 16),
                _buildTargetTempCard(),
                const SizedBox(height: 16),
                _buildActionGrid(),
                const SizedBox(height: 30),
                _buildFooterLinks(),
                const SizedBox(height: 40),
                if (_isBleConnected) ...[
                  _buildWifiConfigButton(),
                  const SizedBox(height: 20),
                ],
                _buildExitButton(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  return Stack(
    children: [
      AbsorbPointer(
        absorbing: _isWaitingForData,
        child: content,
      ),
      if (_isWaitingForData)
        Container(
          color: Colors.black.withOpacity(0.5),
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
    ],
  );
}

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Image.network(
                _logoUrl, 
                height: 45,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.broken_image, size: 30, color: Colors.white24);
                },
              ),
              const SizedBox(width: 10), // Espacio entre el logo y el nuevo botón
              IconButton(
                icon: const Icon(Icons.history, color: Colors.white70, size: 28),
                onPressed: () {
                  // Cerrar la conexión actual antes de mostrar el diálogo para elegir otro dispositivo
                  if (_isConnected) {
                    _logout();
                  }
                  _showSavedDevicesDialog();
                },
                tooltip: 'Equipos Guardados',
              ),
              // Añadido: Mostrar el nombre del dispositivo actual
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Text(
                  _devices.firstWhere(
                    (d) => d.serial == _serialController.text,
                    orElse: () => DeviceInfo(serial: 'NO_DEVICE', nickname: 'Seleccionar Equipo')
                  ).displayName(),
                  style: const TextStyle(color: Colors.white60, fontSize: 16),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  if (_isLocalAvailable || _isBleConnected) ...[
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: _isDeviceResponding ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _isDeviceResponding ? Colors.greenAccent.withOpacity(0.6) : Colors.redAccent.withOpacity(0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          )
                        ]
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  const Text("🇦🇷", style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 4),
                  const Text("🇯🇵", style: TextStyle(fontSize: 18)),
                ],
              ),
              const Text("Tradición japonesa", style: TextStyle(fontSize: 10, color: Colors.white70)),
              const Text("Fabricación nacional", style: TextStyle(fontSize: 10, color: Colors.white70)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTemperatureCard() {
    final bool hasSensorError = _currentTemp == -99.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 35),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 140, height: 140,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const CircularProgressIndicator(
                      value: 1.0,
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white10),
                    ),
                    CircularProgressIndicator(
                      value: (_currentTemp ?? 0) / 50,
                      strokeWidth: 2,
                      backgroundColor: Colors.transparent,
                      valueColor: const AlwaysStoppedAnimation<Color>(kAccentColor),
                    ),
                  ],
                ),
              ),
              // El punto indicador del progreso (opcional para estética)
              Text(
                _currentTemp == null
                    ? '--'
                    : (hasSensorError ? '' : '${_currentTemp!.toInt()}°'),
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w200,
                  color: hasSensorError ? Colors.redAccent : Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          hasSensorError
              ? const Text('error en el sensor de temperatura', style: TextStyle(color: Colors.redAccent, fontSize: 16))
              : const Text('Temperatura actual', style: TextStyle(color: Colors.white60, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildTargetTempCard() {
    final bool isLocked = _lockSetTemp;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(isLocked ? Icons.lock : Icons.thermostat_outlined, color: isLocked ? Colors.redAccent : Colors.white),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white10,
                  thumbColor: isLocked ? Colors.grey : kAccentColor,
                ),
                child: Slider( // SE AGREGÓ EL PARÁMETRO 'child' OBLIGATORIO
                  value: (_setTemp ?? 25.0).clamp(10, 45), // Valor actual
                  min: 10,
                  max: _effectiveMaxTemp,
                  divisions: 50,
                  // Corrección del error en línea 1679: agregamos '=>' o llaves {}
                  onChangeStart: (v) => _tempBeforeChange = _setTemp, 
                  onChanged: (v) => setState(() => _setTemp = v),
                  onChangeEnd: (v) => _publishSetTemp(v),
                ),
              ),
            ),
              Text('${_setTemp?.toInt() ?? "--"}°', 
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w400)),
            ],
          ),
          const Text('Temperatura deseada', style: TextStyle(color: Colors.white60)),
        ],
      ));
  }

  Widget _buildVerticalTargetTempCard() {
    final bool isLocked = _lockSetTemp;
    return Container(
      width: 80,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20),

      child: Column(
        children: [
          Icon(isLocked ? Icons.lock : Icons.thermostat_outlined, color: isLocked ? Colors.redAccent : Colors.white),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white10,
                  thumbColor: isLocked ? Colors.grey : kAccentColor,
                ),
                child: Slider(
                  value: (_setTemp ?? 10).clamp(10, _effectiveMaxTemp),
                  min: 10, max: _effectiveMaxTemp,
                  onChangeStart: (v) {
                    _tempBeforeChange = _setTemp;
                  },
                  onChanged: (v) => setState(() => _setTemp = v),
                  onChangeEnd: (v) => _publishSetTemp(v),
                ),
              ),
            ),
          ),
          Text('${_setTemp?.toInt() ?? "--"}°', 
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w400)),
        ],
      ),
    );
  }

  Widget _buildActionGrid({bool isLandscape = false}) {
    final bool _hasSensorError = _currentTemp == -99.0; // Determinar si hay error en el sensor

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculamos el ancho de cada item dinámicamente
        int columns = isLandscape ? 2 : 4;
        double spacing = 10.0;
        double totalSpacing = spacing * (columns - 1);
        double itemWidth = (constraints.maxWidth - totalSpacing) / columns;
        if (isLandscape) {
          itemWidth *= 0.85;
        }

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          alignment: WrapAlignment.center,
          children: [
            _buildActionItem('Jets', LucideIcons.waves, _jet, _lockJets, (v) { // Changed Icon to LucideIcons.waves
               _handleButtonPress('OnOff', v);
            }, itemWidth),
            // Modificación para el botón de Calefacción: bloqueado si hay error en el sensor
            _buildActionItem('Calefacción', LucideIcons.thermometer, _calefa, _lockCalefa || _hasSensorError, (v) { // Changed Icon to LucideIcons.thermometer
               if (!_hasSensorError) { // Solo permitir si no hay error de sensor
                 _handleButtonPress('Calefa', v);
               } else {
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text('No se puede controlar la calefacción con sensor de temperatura erróneo.'))
                 );
               }
            }, itemWidth),
            _buildActionItem('Luces', LucideIcons.lightbulb, _luces, _lockLuces, (v) { // Changed Icon to LucideIcons.lightbulb
               _handleButtonPress('Luces', v);
            }, itemWidth),
            // Modificación para Modo Eco: No permitir si hay error en el sensor
            _buildActionItem('Modo Eco', LucideIcons.leaf, _isEcoActive, false, (v) { // Changed Icon to LucideIcons.leaf
              if(v) {
                if (!_hasSensorError) { // Solo permitir si no hay error de sensor
                  setState(() { _setTemp = 18.0; _calefa = true; });
                  _publishSetTemp(18.0); _toggleAndPublish('Calefa', true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No se puede activar Modo Eco con sensor de temperatura erróneo.'))
                  );
                }
              }
            }, itemWidth),
          ],
        );
      },
    );
  }

  Widget _buildActionItem(String label, IconData icon, bool active, bool isLocked, Function(bool)? onChanged, double width) {
    // Definimos colores según el estado
    final Color cardBackground = active ? Colors.white : Colors.black;
    final Color borderColor = active ? Colors.white : Colors.white12;
    final Color iconColor = active ? Colors.black : (isLocked ? Colors.white30 : Colors.white);
    final Color textColor = active ? Colors.black : Colors.white70;

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.topRight,
            children: [
              Icon(icon, color: iconColor, size: 30),
              if (isLocked) const Padding(padding: EdgeInsets.only(left: 10), child: Icon(Icons.lock, color: Colors.redAccent, size: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 11, color: textColor, fontWeight: active ? FontWeight.bold : FontWeight.normal), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: active,
              onChanged: onChanged,
              activeColor: Colors.black,
              activeTrackColor: Colors.black.withOpacity(0.3),
              inactiveThumbColor: isLocked ? Colors.white10 : Colors.white30,
              inactiveTrackColor: Colors.white10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWifiConfigButton() {
    return TextButton.icon(
      onPressed: _showBleWifiConfigDialog,
      icon: const Icon(Icons.wifi, color: kAccentColor),
      label: const Text('CONFIGURAR WI-FI (BLE)', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold, letterSpacing: 1)),
    );
  }

  Widget _buildFooterLinks() {
    //final hasSessionCode = _sessionCode != null && _sessionCode!.isNotEmpty;
    final isBleConnected = _bleService.isConnected; // O la variable que uses para rastrear el estado BLE
    final hasSessionCode = (_sessionCode != null && _sessionCode!.isNotEmpty) || isBleConnected;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        TextButton.icon(
          onPressed: () => _launchUrl('https://instagram.com/hiroki_original'),
          icon: const Icon(Icons.camera_alt_outlined, color: Colors.white60, size: 20),
          label: const Text('@hiroki_oficial', style: TextStyle(color: Colors.white60)),
        ),
        TextButton.icon(
          onPressed: () => _launchUrl('https://www.hiroki.com.ar'),
          icon: const Icon(Icons.language, color: Colors.white60, size: 20),
          label: const Text('Hiroki', style: TextStyle(color: Colors.white60)),
        ),
        TextButton.icon(
          onPressed: hasSessionCode ? () async {
            // Pasamos los servicios y la capacidad de enviar MQTT a la pantalla de ajustes
            final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => SecurityPage(
             
              bleService: _bleService,
              hasPin: _hasPin,
              localBaseUrl: _localBaseUrl,
              onMqttSend: (topic, payload) {
                if (_mqttUserPrefix != null) {
                  _mqtt.publish('$_mqttUserPrefix/$topic', payload);
                  return true;
                }
                return false;
              },
              serial: _serialController.text,
              sessionCode: _sessionCode,
              mqttService: _mqtt,
            )));

            // Al volver de ajustes, limpiamos el PIN de sesión por seguridad (por si se cambió la clave)
            _sessionPin = null;

            if (result == 'RECONNECT') {
              _handleConfigChangeAndReconnect();
              return;
            }

            // Si se seleccionó un nuevo dispositivo (serial) en Ajustes, desconectamos y actualizamos
            if (result != null && result is String && result != _serialController.text) {
              await _logout();
              if (mounted) setState(() => _serialController.text = result);
            }
          } : null,
          icon: Icon(Icons.settings, color: hasSessionCode ? Colors.white60 : const Color(0xFF2A2A2A), size: 20),
          label: Text('Ajustes', style: TextStyle(color: hasSessionCode ? Colors.white60 : const Color(0xFF2A2A2A))),
        ),
      ],
    );
  }
String _mqttTopicForCommand(String key) {
  if (_mqttUserPrefix == null || _mqttUserPrefix!.isEmpty) return '';
  if (_sessionCode == null || _sessionCode!.isEmpty) {
    return '$_mqttUserPrefix/devices/$key/set';
  }
  return '$_mqttUserPrefix/app/$key/value/set';
}
  Future<void> _handleConfigChangeAndReconnect() async {
    if (!mounted) return;
    
    // Usamos un diálogo para informar al usuario que no puede interactuar.
    _showSimpleDialog('Aplicando Cambios', 'El equipo se está reiniciando. Se intentará reconectar en 10 segundos...', showSpinner: true);

    // Esperamos que el equipo se reinicie
    await Future.delayed(const Duration(seconds: 10));
    if (!mounted) return;

    // Cerramos el diálogo
    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {}

    // Desconectamos todo
    _bleService.disconnect();
    _bleSubscription?.cancel();
    _mqtt.disconnect();
    _subscription?.cancel();
    _localStatusTimer?.cancel();

    // Reseteamos el estado para volver a la pantalla de login
    setState(() {
        _isConnected = false;
        _isBleConnected = false;
        _localBaseUrl = null;
        _status = 'Desconectado';
        _sessionPin = null; // Limpiamos el PIN de sesión
    });

    // Esperamos un momento para que la UI se actualice y luego intentamos reconectar
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) await _connect();
  }

  Widget _buildExitButton() {
    return InkWell(
      onTap: _logout,
      child: Column(
        children: const [
          Icon(Icons.logout, color: Colors.white, size: 28),
          SizedBox(height: 4),
          Text("SALIR", style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }
}



class SecurityPage extends StatefulWidget {
  final BleService? bleService;
  final String? localBaseUrl;
  final bool Function(String topic, String payload)? onMqttSend;
  final bool hasPin;
  final String serial;
  final String? sessionCode;
  final MqttService? mqttService;

  const SecurityPage({super.key, this.bleService, this.localBaseUrl, this.onMqttSend, this.hasPin = false, required this.serial, this.sessionCode, this.mqttService});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  final _oldPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _masterKeyController = TextEditingController();
  
  // Estado de los bloqueos (true = bloqueado/requiere pin)
  bool _lockSetTemp = false;
  bool _lockCalefa = false;
  bool _lockJets = false;
  bool _lockLuces = false;

  bool _isSaving = false;

  @override
  void dispose() {
    _oldPinController.dispose();
    _newPinController.dispose();
    _masterKeyController.dispose();
    super.dispose();
  }

  Future<void> _saveSecurityConfig() async {
    final oldPin = _oldPinController.text.trim().toUpperCase();
    final newPin = _newPinController.text.trim().toUpperCase();

    if (widget.hasPin && oldPin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debe ingresar la clave actual o maestra para autorizar cambios.')));
      return;
    }

    if (newPin.isNotEmpty && newPin.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La nueva clave debe tener exactamente 6 caracteres.')));
      return;
    }

    setState(() => _isSaving = true);

    // Construir Payload JSON
    // El chip debe recibir esto, verificar "auth" (oldPin) contra su PIN guardado o la MasterKey.
    // Si es correcto, actualiza el PIN (si new_pin no es vacío) y actualiza los locks.
    final config = {
      "auth": oldPin,
      "new_pin": newPin.isEmpty ? oldPin : newPin, // Si no cambia, enviamos el mismo o vacío según lógica del chip
      "locks": {
        "SetTemp": _lockSetTemp ? 1 : 0,
        "Calefa": _lockCalefa ? 1 : 0,
        "Jets": _lockJets ? 1 : 0,
        "Luces": _lockLuces ? 1 : 0,
      }
    };

    final jsonPayload = jsonEncode(config);
    bool sent = false;

    // 1. Intentar BLE
    if (widget.bleService != null && widget.bleService!.isConnected) {
      sent = await widget.bleService!.sendCommand('SECURITY_CONFIG', jsonPayload);
    } 
    // 2. Intentar MQTT
    else if (widget.onMqttSend != null) {
      try {
        // Publicamos en .../app/security/config/set
        sent = widget.onMqttSend!('app/security/config/set', jsonPayload);
      } catch (_) {}
    }
    // 3. Intentar Local (HTTP)
    else if (widget.localBaseUrl != null) {
       try {
         // Codificar payload para URL
         final url = '${widget.localBaseUrl}/security_config?data=${Uri.encodeComponent(jsonPayload)}';
         // quitamos el timeout para no fallar temprano en conexiones lentas
         await http.get(Uri.parse(url));
         sent = true;
       } catch (_) {}
    }

    setState(() => _isSaving = false);

    if (sent) {
      Navigator.pop(context, 'RECONNECT'); // Changed from true to 'RECONNECT'
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: No hay conexión con el equipo para guardar.')));
    }
  }



  Future<void> _openMasterConfig() async {
    String? sessionCode = widget.sessionCode;
    if (sessionCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se encontró session code.')));
      return;
    }

    final masterKey = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white24, width: 1),
        ),
        title: const Text('Acceso Configuración Técnica', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Session Code del chip: $sessionCode', style: const TextStyle(fontWeight: FontWeight.bold, color: kAccentColor)),
            const SizedBox(height: 10),
            const Text('Ingrese la clave maestra para acceder a configuración técnica.', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            TextField(
              controller: _masterKeyController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Clave Maestra (6 dígitos)',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [UpperCaseTextFormatter()],
              obscureText: true,
              maxLength: 6,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              final key = _masterKeyController.text.trim().toUpperCase();
              _masterKeyController.clear();
              Navigator.pop(c, key);
            },
            child: const Text('ACCEDER', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (sessionCode != null && masterKey != null && masterKey == generateMasterKey(sessionCode)) {
      final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => MasterConfigPage(
        bleService: widget.bleService,
        hasPin: widget.hasPin,
        localBaseUrl: widget.localBaseUrl,
        onMqttSend: widget.onMqttSend,
      )));

      if (result == 'RECONNECT') {
        if (mounted) Navigator.pop(context, 'RECONNECT');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clave maestra incorrecta.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seguridad del Equipo'), backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Gestión de Claves', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kAccentColor)),
            const SizedBox(height: 10),
            if (widget.hasPin) ...[
              const Text('Ingrese la clave actual (o Maestra) para autorizar cambios.', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 10),
              TextField(
                controller: _oldPinController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Clave Actual / Maestra',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
                  border: OutlineInputBorder(),
                ),
                maxLength: 6,
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 20),
            ],
            const Text('Para cambiar la clave, ingrese una nueva (6 dígitos). Déjelo en blanco para mantener la actual.', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: _newPinController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Nueva Clave (Opcional)',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
                border: OutlineInputBorder(),
              ),
              maxLength: 6,
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 30),
            const Divider(color: Colors.white24),
            const SizedBox(height: 10),
            const Text('Bloqueo de Funciones', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kAccentColor)),
            const SizedBox(height: 5),
            const Text('Seleccione qué funciones requerirán la clave para ser activadas.', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 15),
            SwitchListTile(
              title: const Text('Bloquear Temperatura (SetTemp)', style: TextStyle(color: Colors.white)),
              value: _lockSetTemp,
              activeColor: kAccentColor,
              onChanged: (v) => setState(() => _lockSetTemp = v),
            ),
            SwitchListTile(
              title: const Text('Bloquear Calefacción', style: TextStyle(color: Colors.white)),
              value: _lockCalefa,
              activeColor: kAccentColor,
              onChanged: (v) => setState(() => _lockCalefa = v),
            ),
            SwitchListTile(
              title: const Text('Bloquear Jets / Motor', style: TextStyle(color: Colors.white)),
              value: _lockJets,
              activeColor: kAccentColor,
              onChanged: (v) => setState(() => _lockJets = v),
            ),
            SwitchListTile(
              title: const Text('Bloquear Luces', style: TextStyle(color: Colors.white)),
              value: _lockLuces,
              activeColor: kAccentColor,
              onChanged: (v) => setState(() => _lockLuces = v),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveSecurityConfig,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.black))
                    : const Text('GUARDAR CONFIGURACIÓN EN CHIP', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
            const SizedBox(height: 30),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _openMasterConfig,
                child: const Text(
                  'CONFIGURACIÓN TÉCNICA',
                  style: TextStyle(
                    color: kAccentColor,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MasterConfigPage extends StatefulWidget {
  final BleService? bleService;
  final String? localBaseUrl;
  final bool Function(String topic, String payload)? onMqttSend;
  final bool hasPin;

  const MasterConfigPage({super.key, this.bleService, this.localBaseUrl, this.onMqttSend, this.hasPin = false});

  @override
  State<MasterConfigPage> createState() => _MasterConfigPageState();
}

class _MasterConfigPageState extends State<MasterConfigPage> {
  final _brokerCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  // el controlador de retraso ya no es necesario
  final _oldPinController = TextEditingController();

  double _maxTemp = 42;
  double _histeresis = 3;
  bool _isSaving = false;
  bool _resetPin = false;

  @override
  void initState() {
    super.initState();
    // Valores por defecto (idealmente se cargarían del dispositivo si hubiera un comando GET)
    _brokerCtrl.text = "hiroki.servidoraweb.net";
    _portCtrl.text = "8883";
    // _delayCtrl removed, default delay no longer editable
    _loadSavedHysteresis();
  }

  Future<void> _loadSavedHysteresis() async {
    final prefs = await SharedPreferences.getInstance();
    final savedHys = prefs.getDouble(kHysteresisKey);
    if (savedHys != null && mounted) {
      setState(() => _histeresis = savedHys);
    }
  }

  @override
  void dispose() {
    _brokerCtrl.dispose();
    _portCtrl.dispose();
    // _delayCtrl removed
    _oldPinController.dispose();
    super.dispose();
  }

  Future<void> _saveMasterConfig() async {
    if (widget.hasPin) {
      final oldPin = _oldPinController.text.trim().toUpperCase();
      if (oldPin.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debe ingresar la clave actual o maestra.')));
        return;
      }
    }

    setState(() => _isSaving = true);

    final config = {
      "maxTemp": _maxTemp.toInt(), // Convert to integer
      "histeresis": _histeresis.toInt(), // Convert to integer
      // delayCheck removed, firmware will use default or previous value
      "broker": _brokerCtrl.text.trim(),
      "port": int.tryParse(_portCtrl.text) ?? 8883,
      "resetPin": _resetPin,
    };

    if (widget.hasPin) {
      config["auth"] = _oldPinController.text.trim().toUpperCase();
    }

    final jsonPayload = jsonEncode(config);
    bool sent = false;

    // 1. Intentar BLE
    if (widget.bleService != null && widget.bleService!.isConnected) {
      // Usamos un tópico específico para config maestra
      sent = await widget.bleService!.sendCommand('MASTER_CONFIG_SET', jsonPayload);
    } 
    // 2. Intentar MQTT
    else if (widget.onMqttSend != null) {
      try {
        sent = widget.onMqttSend!('app/master/config/set', jsonPayload);
      } catch (_) {}
    }
    // 3. Intentar Local (HTTP) - Opcional si el firmware lo soporta
    else if (widget.localBaseUrl != null) {
       try {
         final url = '${widget.localBaseUrl}/master_config?data=${Uri.encodeComponent(jsonPayload)}';
         await http.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
         sent = true;
       } catch (_) {}
    }

    if (sent) {
      // Guardamos localmente el valor aplicado también en preferencias
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(kHysteresisKey, _histeresis);
    }

    setState(() => _isSaving = false);

    if (sent) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configuración Maestra enviada. El equipo se reiniciará.')));
      // Espera de sincronización antes de volver al panel principal.
      await Future.delayed(const Duration(seconds: 10));
      if (!mounted) return;
      Navigator.pop(context, 'RECONNECT'); // Added 'RECONNECT' as return value
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: No hay conexión para guardar.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración Maestra'), backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Parámetros de Servicio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kAccentColor)),
            const SizedBox(height: 20),

            if (widget.hasPin) ...[
              const Text('Autenticación', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kAccentColor)),
              const SizedBox(height: 10),
              const Text('Ingrese la clave actual o maestra para autorizar cambios.', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 10),
              TextField(
                controller: _oldPinController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Clave Actual / Maestra',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
                  border: OutlineInputBorder(),
                  counterText: "",
                ),
                maxLength: 6,
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 20),
            ],
            
            Text('Temperatura Máxima: ${_maxTemp.toInt()}°C', style: const TextStyle(color: Colors.white70)),
            Slider(
              value: _maxTemp,
              min: 20, max: 45, 
              divisions: 25,
              label: _maxTemp.toInt().toString(),
              activeColor: kAccentColor,
              inactiveColor: Colors.white24,
              onChanged: (v) => setState(() => _maxTemp = v),
            ),

            Text('Histéresis: ${_histeresis.toInt()}°C', style: const TextStyle(color: Colors.white70)),
            Slider(
              value: _histeresis,
              min: 1, max: 6, 
              divisions: 5,
              label: _histeresis.toInt().toString(),
              activeColor: kAccentColor,
              inactiveColor: Colors.white24,
              onChanged: (v) => setState(() => _histeresis = v),
            ),

            // campo de tiempo de espera eliminado
            
            
            const Text('Restaurar Seguridad', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kAccentColor)),
            CheckboxListTile(
              title: const Text('Restaurar PIN a fábrica (Sin PIN)', style: TextStyle(color: Colors.white)),
              value: _resetPin,
              onChanged: (v) => setState(() => _resetPin = v ?? false),
              activeColor: kAccentColor,
              checkColor: Colors.black,
            ),
            const SizedBox(height: 20),

            const Text('Configuración MQTT', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kAccentColor)),
            const SizedBox(height: 10),
            TextField(
              controller: _brokerCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Broker MQTT',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _portCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Puerto MQTT',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveMasterConfig,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.black))
                    : const Text('GUARDAR CAMBIOS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BleScanScreen extends StatefulWidget {
  final BleService bleService;
  const BleScanScreen({super.key, required this.bleService});

  @override
  State<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends State<BleScanScreen> {
  @override
  void initState() {
    super.initState();
    // Intentamos iniciar el escaneo y mostramos mensaje si falla (Bluetooth apagado o permisos)
    widget.bleService.startScan().then((ok) {
      if (!ok && mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Colors.white24, width: 1),
            ),
            title: const Text('Escaneo fallido', style: TextStyle(color: Colors.white)),
            content: const Text('No se pudo iniciar el escaneo. Verifique que Bluetooth esté activado y que los permisos estén concedidos.', style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('OK', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(c);
                  if (Platform.isAndroid) {
                    try {
                      const channel = MethodChannel('com.hiroki.intent');
                      await channel.invokeMethod('openBluetoothSettings');
                    } catch (e) {
                      openAppSettings();
                    }
                  } else {
                    openAppSettings();
                  }
                },
                child: const Text('Abrir Ajustes BT', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    widget.bleService.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar Hiroki'), backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      body: StreamBuilder<List<ScanResult>>(
        stream: widget.bleService.scanResults,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(kAccentColor)));
          
          // Filtramos dispositivos por nombre (advertisement/localName o device.name)
          final devices = snapshot.data!.where((r) {
            String nameRaw = '';
            final ln = r.advertisementData.localName;
            if (ln.isNotEmpty) nameRaw = ln;
            else if (r.device.name.isNotEmpty) nameRaw = r.device.name;
            else if (r.device.platformName.isNotEmpty) nameRaw = r.device.platformName;
            final nameLower = nameRaw.toLowerCase().trim();

            // Revisar manufacturer data (decodificando ASCII) y service UUIDs por si el nombre no está en localName
            bool manMatches = false;
            try {
              for (var entry in r.advertisementData.manufacturerData.entries) {
                final bytes = entry.value;
                final s = utf8.decode(bytes, allowMalformed: true).toLowerCase();
                if (s.contains('hiroki')) { manMatches = true; break; }
              }
            } catch (_) {}

            final svcs = r.advertisementData.serviceUuids.join(',').toLowerCase();

            return nameLower.contains('hiroki') || manMatches || svcs.contains('4fafc201');
          }).toList();

          if (devices.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Buscando dispositivos Hiroki...", style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () { widget.bleService.startScan(); },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    child: const Text("REINTENTAR"),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () async { if (Platform.isAndroid) { try { const channel = MethodChannel('com.hiroki.intent'); await channel.invokeMethod('openBluetoothSettings'); } catch (e) { openAppSettings(); } } else { openAppSettings(); } },
                    child: const Text("Abrir ajustes Bluetooth", style: TextStyle(color: kAccentColor)),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
              itemCount: devices.length,
              itemBuilder: (c, i) {
                final device = devices[i].device;
                String nameRaw = '';
                final ln = devices[i].advertisementData.localName;
                if (ln.isNotEmpty) nameRaw = ln;
                else if (device.name.isNotEmpty) nameRaw = device.name;
                else if (device.platformName.isNotEmpty) nameRaw = device.platformName;
                final name = nameRaw;
                final displayName = name.isEmpty ? 'Dispositivo Desconocido' : name;
                return ListTile(
                  title: Text(displayName, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(device.remoteId.toString(), style: const TextStyle(color: Colors.white54)),
                  leading: const Icon(Icons.bluetooth, color: kAccentColor),
                  onTap: () {
                    widget.bleService.stopScan();
                    Navigator.pop(context, device);
                  },
                );
                            },
                          );
                      },
                    ),
                  );
                }
              }
              
              class HirokiConfigPage extends StatefulWidget {
                const HirokiConfigPage({super.key});
              
                @override
                State<HirokiConfigPage> createState() => _HirokiConfigPageState();
              }
              
              class _HirokiConfigPageState extends State<HirokiConfigPage> {
                bool _isScanning = false;
                List<String> _wifiList = [];
                String? _selectedSsid;
                final TextEditingController _ssidController = TextEditingController();
                final TextEditingController _passController = TextEditingController();
                bool _obscurePass = true;
                String? _connectedSsid;
                String? _detectedChipId;
                String _statusMsg = '';
              
                final NetworkInfo _networkInfo = NetworkInfo();
              
                @override
                void initState() {
                  super.initState();
                  _refreshConnected();
                }
              
                @override
                void dispose() {
                  _ssidController.dispose();
                  _passController.dispose();
                  super.dispose();
                }
              
                Future<void> _refreshConnected() async {
                  try {
                    final ssid = await _networkInfo.getWifiName();
                    if (!mounted) return;
                    setState(() => _connectedSsid = ssid?.replaceAll('"', ''));
                    
                    // Si se conectó a HIROKI_CONFIG, intentar obtener el ChipID
                    if (_connectedSsid?.toLowerCase() == 'hiroki_config') {
                      setState(() => _statusMsg = 'Conectado a HIROKI_CONFIG. Obteniendo ChipID...');
                      final chipId = await _fetchChipIdForConfig();
                      if (chipId != null && chipId.isNotEmpty) {
                        if (!mounted) return;
                        setState(() {
                          _detectedChipId = chipId;
                          _statusMsg = 'ChipID detectado: $chipId';
                        });
                      }
                    } else {
                      setState(() => _detectedChipId = null);
                    }
                  } catch (e) {
                    if (!mounted) return;
                    setState(() {
                      _connectedSsid = null;
                      _detectedChipId = null;
                    });
                  }
                }
              
                Future<void> _scanWifi() async {
                  setState(() {
                    _isScanning = true;
                    _wifiList = [];
                    _statusMsg = 'Escaneando redes locales...';
                  });
              
                  if (await Permission.location.request().isDenied) {
                    setState(() {
                      _statusMsg = 'Permiso de ubicación requerido para escanear redes.';
                      _isScanning = false;
                    });
                    return;
                  }
              
                  try {
                    final list = await WiFiForIoTPlugin.loadWifiList();
                    final ssids = <String>[];
                    for (final item in list) {
                      try {
                        final ss = item.ssid;
                        if (ss != null && ss.toString().isNotEmpty) ssids.add(ss.toString());
                      } catch (_) {}
                    }
                    if (!mounted) return;
                    setState(() {
                      _wifiList = ssids.toSet().toList()..sort();
                      _isScanning = false;
                      if (_wifiList.isNotEmpty) _selectedSsid = _wifiList.first;
                      _statusMsg = 'Escaneo completado.';
                    });
                  } catch (e) {
                    if (!mounted) return;
                    setState(() {
                      _statusMsg = 'Error escaneando redes: $e';
                      _isScanning = false;
                    });
                  }
                }
              
                Future<void> _sendCredentials() async {
                  final targetSsid = _selectedSsid ?? _ssidController.text.trim();
                  final pass = _passController.text;
                  if (targetSsid.isEmpty) {
                    setState(() => _statusMsg = 'Seleccione o ingrese el SSID objetivo.');
                    return;
                  }
              
                  await _refreshConnected();
                  if ((_connectedSsid ?? '').toLowerCase() != 'hiroki_config') {
                    setState(() => _statusMsg = 'Conéctese primero a la red HIROKI_CONFIG y reintente.');
                    return;
                  }
              
                  setState(() => _statusMsg = 'Enviando credenciales al dispositivo...');
              
                  final uri = Uri.http('192.168.4.1', '/setap', {'ssid': targetSsid, 'pass': pass});
                  try {
                    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
                    final body = resp.body;
                    if (resp.statusCode == 200 && body.contains('Configuracion WiFi completa')) {
                      setState(() => _statusMsg = 'Configuración enviada. Esperando reinicio...');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Credenciales enviadas correctamente.'),
                          duration: Duration(seconds: 2),
                        ));
                      }
                      
                      // Esperar 2 segundos
                      await Future.delayed(const Duration(seconds: 2));
                      
                      // Reiniciar la app
                      if (mounted) {
                        setState(() => _statusMsg = 'Reiniciando la aplicación...');
                        await Future.delayed(const Duration(milliseconds: 500));
                        Phoenix.rebirth(context);
                      }
                    } else {
                      setState(() => _statusMsg = 'Respuesta inesperada del dispositivo (código ${resp.statusCode}). Intente abrir el portal manualmente.');
                    }
                  } catch (e) {
                    // En vez de mostrar una alerta, reiniciamos la app.
                    if (mounted) {
                      setState(() => _statusMsg = 'Error enviando credenciales. Reiniciando la aplicación...');
                      // Esperar 2 segundos para que el mensaje sea visible
                      await Future.delayed(const Duration(seconds: 2));
                      // Reiniciar la app correctamente
                      Phoenix.rebirth(context);
                    }
                  }
                }
              
                /// Obtiene el ChipID del dispositivo desde 192.168.4.1/settings (cuando está en modo HIROKI_CONFIG)
                Future<String?> _fetchChipIdForConfig() async {
                  try {
                    final uri = Uri.http('192.168.4.1', '/settings');
                    final response = await http.get(uri).timeout(const Duration(seconds: 5));
                    if (response.statusCode == 200) {
                      // Intentar parsear como JSON
                      try {
                        final data = jsonDecode(response.body);
                        if (data is Map && data.containsKey('chipid')) {
                          final found = data['chipid'] as String?;
                          if (found != null && found.isNotEmpty) {
                            try {
                              final prefs = await SharedPreferences.getInstance();
                              final devicesJson = prefs.getString(kDevicesKey) ?? '[]';
                              List<DeviceInfo> devices;
                              try {
                                final list = (jsonDecode(devicesJson) as List).cast<Map<String, dynamic>>();
                                devices = list.map((m) => DeviceInfo.fromJson(m)).toList();
                              } catch (_) {
                                devices = [];
                              }
                              final idx = devices.indexWhere((d) => d.serial == found);
                              final now = DateTime.now().toIso8601String();
                              if (idx >= 0) {
                                devices[idx].lastSeen = now;
                                devices[idx].chipId = found;
                              } else {
                                devices.add(DeviceInfo(serial: found, lastSeen: now, chipId: found));
                              }
                              await prefs.setString(kDevicesKey, jsonEncode(devices.map((d) => d.toJson()).toList()));
                            } catch (_) {}
                          }
                          return found;
                        }
                      } catch (_) {
                        // Si no es JSON, intentar extraer de texto plano
                        // Buscar primero 'Nro de serie: <valor>' en la página
                        debugPrint('DEBUG Config: Respuesta HTML recibida (primeros 500 chars): ${response.body.substring(0, math.min(500, response.body.length))}');
                        
                        final serialRegex = RegExp(r'Nro de serie[:\s]*([^<\r\n]+)', caseSensitive: false);
                        final serialMatch = serialRegex.firstMatch(response.body);
                        debugPrint('DEBUG Config: Búsqueda regex "Nro de serie". Coincidencia: ${serialMatch != null}');
                        
                        if (serialMatch != null && serialMatch.groupCount > 0) {
                          final found = serialMatch.group(1)?.trim();
                          debugPrint('DEBUG Config: ChipID encontrado: $found');
                          if (found != null && found.isNotEmpty) {
                            try {
                              final prefs = await SharedPreferences.getInstance();
                              final devicesJson = prefs.getString(kDevicesKey) ?? '[]';
                              List<DeviceInfo> devices;
                              try {
                                final list = (jsonDecode(devicesJson) as List).cast<Map<String, dynamic>>();
                                devices = list.map((m) => DeviceInfo.fromJson(m)).toList();
                              } catch (_) {
                                devices = [];
                              }
                              final idx = devices.indexWhere((d) => d.serial == found);
                              final now = DateTime.now().toIso8601String();
                              if (idx >= 0) {
                                devices[idx].lastSeen = now;
                                devices[idx].chipId = found;
                              } else {
                                devices.add(DeviceInfo(serial: found, lastSeen: now, chipId: found));
                              }
                              await prefs.setString(kDevicesKey, jsonEncode(devices.map((d) => d.toJson()).toList()));
                            } catch (_) {}
                          }
                          return found;
                        }

                        if (response.body.contains('chipid')) {
                          final regex = RegExp(r'chipid\\s*[:=]\\s*([A-F0-9a-f]+)', caseSensitive: false);
                          final match = regex.firstMatch(response.body);
                          if (match != null && match.groupCount > 0) {
                            return match.group(1);
                          }
                        }
                      }
                    }
                  } catch (e) {
                    debugPrint('Error obteniendo ChipID en config: $e');
                  }
                  return null;
                }
              
                Future<void> _openPortalManual() async {
                  final browser = ChromeSafariBrowser();
                  await browser.open(url: WebUri('http://192.168.4.1/'));
                }
              
                @override
                Widget build(BuildContext context) {
                  return Scaffold(
                    appBar: AppBar(title: const Text('Configurar Wi-Fi (Sin BT)'), backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
                    body: SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Configurar por Wi-Fi (HIROKI_CONFIG)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kAccentColor)),
                          const SizedBox(height: 8),
                          const Text('Instrucciones: Conecte el teléfono manualmente a la red WI‑FI del equipo (SSID: HIROKI_CONFIG). Luego elija "escanear redes" y seleccione la red de destino y proporcione la clave. Si estado de conexion no esta en verde y debajo no aparece el numero de serie del equipo, quite los datos moviles y presione actualizar, una vez que se ve el nro de serie y cargo los datos de conexion (Red destino y Clave) presione "Enviar credenciales". La app enviará las credenciales automáticamente al equipo sin necesidad de usar el portal.', style: TextStyle(color: Colors.white70)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: Text('Estado de conexión: ' + (_connectedSsid ?? 'No conectado'), style: TextStyle(color: (_connectedSsid ?? '').toLowerCase() == 'hiroki_config' ? kAccentColor : Colors.white))),
                              TextButton(onPressed: _refreshConnected, child: const Text('Actualizar', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold))),
                            ],
                          ),
                          if (_detectedChipId != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                'Nro. de Serie: $_detectedChipId',
                                style: const TextStyle(color: kAccentColor, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                            
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isScanning ? null : _scanWifi,
                                  icon: const Icon(Icons.wifi),
                                  label: Text(_isScanning ? 'Escaneando...' : 'Escanear redes'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white24),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _openPortalManual,
                                  icon: const Icon(Icons.open_in_browser),
                                  label: const Text('Portal manual'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white24),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                            
                          const SizedBox(height: 16),
                          if (_wifiList.isNotEmpty) ...[
                            DropdownButtonFormField<String>(
                              value: _selectedSsid,
                              dropdownColor: Colors.black,
                              style: const TextStyle(color: Colors.white),
                              items: _wifiList.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(color: Colors.white)))).toList(),
                              onChanged: (v) => setState(() => _selectedSsid = v),
                              decoration: const InputDecoration(
                                labelText: 'Red destino (SSID)',
                                labelStyle: TextStyle(color: Colors.white70),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ] else ...[
                            TextField(
                              controller: _ssidController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'Red destino (SSID)',
                                labelStyle: TextStyle(color: Colors.white70),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Clave Wi‑Fi',
                              labelStyle: const TextStyle(color: Colors.white70),
                              enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                                onPressed: () => setState(() => _obscurePass = !_obscurePass),
                              ),
                            ),
                            obscureText: _obscurePass,
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _sendCredentials,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('ENVIAR CREDENCIALES AL EQUIPO', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_statusMsg.isNotEmpty) Text(_statusMsg, style: const TextStyle(color: kAccentColor, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  );
                }
              }

// Pegalo al final de todo en main.dart
String generateMasterKey(String sessionCode) {
  if (sessionCode.isEmpty) return '';
  const secretSalt = "Hiroki_Security_2026_Salt";
  final data = '$sessionCode$secretSalt';
  final hash = sha256.convert(utf8.encode(data));
  final hex = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return hex.substring(0, 6).toUpperCase();
}