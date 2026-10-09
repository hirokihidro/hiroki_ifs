import 'dart:convert'; // Necesario para validar la Clave Maestra
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:io' show Platform;
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_flutter/lucide_flutter.dart'; // Add this import
import 'package:crypto/crypto.dart';
import 'mqtt_service.dart';
import 'local_discovery_service.dart';
import 'models/device.dart';
import 'temp_sync.dart';

// SharedPreferences keys (public)
const String kDevicesKey = 'known_devices';
const String kDefaultDeviceKey = 'default_device_serial';
const String kMaxTempKey = 'max_temp';
const String kHysteresisKey = 'hysteresis';

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
        textTheme: GoogleFonts.montserratTextTheme(
          // Aplica Montserrat a todo el TextTheme
          Theme.of(context).textTheme.apply(
                bodyColor: Colors.white, // Color del texto principal
                displayColor: Colors.white, // Color de los títulos
              ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black, // Color de fondo del AppBar full black
          foregroundColor:
              Colors.white, // Color del texto y los iconos en el AppBar
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
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        }),
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
        initialConnected: false,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.initialConnected = false,
  });

  final bool initialConnected;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  void _showSavedDevicesDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        // Para actualizar nombres dentro del modal
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Colors.white24, width: 1)),
          title: const Text('Equipos Guardados',
              style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: _devices.isEmpty
                ? const Text('No hay equipos guardados aún.',
                    style: TextStyle(color: Colors.white54))
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
                            Text(
                                device.nickname != null
                                    ? device.serial
                                    : 'Sin nombre',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                            if (device.chipId != null &&
                                device.chipId!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('ChipID: ' + device.chipId!,
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 11)),
                            ]
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                device.serial == _defaultDeviceSerial
                                    ? Icons.star
                                    : Icons.star_border,
                                size: 20,
                                color: device.serial == _defaultDeviceSerial
                                    ? kAccentColor
                                    : Colors.white70,
                              ),
                              tooltip: device.serial == _defaultDeviceSerial
                                  ? 'Predeterminado'
                                  : 'Establecer como predeterminado',
                              onPressed: () async {
                                if (device.serial != _defaultDeviceSerial) {
                                  await _setDefaultDevice(device.serial);
                                  setModalState(() {});
                                  setState(() {});
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit,
                                  size: 20, color: Colors.white70),
                              onPressed: () async {
                                String? newName =
                                    await _showEditNicknameDialog(device);
                                if (newName != null) {
                                  await _addOrUpdateDevice(device.serial,
                                      nickname: newName);
                                  setModalState(() {}); // Actualiza el modal
                                  setState(
                                      () {}); // Actualiza el dropdown del inicio
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete,
                                  size: 20, color: Colors.redAccent),
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
                child: const Text('CERRAR',
                    style: TextStyle(color: Colors.white70))),
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white24, width: 1)),
        title: Text('Nombre para ${device.serial}',
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Ej: Terraza, Quincho...',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: kAccentColor)),
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('CANCELAR',
                  style: TextStyle(color: Colors.white70))),
          TextButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: const Text('GUARDAR',
                  style: TextStyle(
                      color: kAccentColor, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  final _serialController = TextEditingController();
  final _mqtt = MqttService();
  final _httpClient = http.Client();
  final _discoveryService = LocalDiscoveryService();

  // Lista de dispositivos conocidos (serial + nickname)
  List<DeviceInfo> _devices = [];
  String? _defaultDeviceSerial;
  bool _hasAutoStartedScan = false;

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
  Timer? _localStatusTimer;
  Timer? _connectionWatchdogTimer;
  static const int _watchdogSeconds = 8;

  String? _localBaseUrl;
  bool get _isLocalAvailable => _localBaseUrl != null;

  final Map<String, String> _mqttToLocalKeyMap = {
    'SetTemp': 'SetTemp',
    'Calefa': 'Calefa',
    'OnOff': 'OnOff',
    'Luces': 'Luces',
    'eco': 'eco',
  };

  double? _currentTemp;
  double? _setTemp;
  double _maxTemp = 40;
  bool _calefa = false;
  bool _jet = false;
  bool _luces = false;
  double _delayMinutes = 60.0;

  // Lock states (true = locked)
  bool _lockSetTemp = false;
  bool _lockCalefa = false;
  bool _lockJets = false;
  bool _lockLuces = false;
  bool _hasPin = false; // Indica si el dispositivo tiene PIN configurado
  String? _sessionPin; // PIN ingresado por el usuario en esta sesión
  double? _tempBeforeChange; // Para revertir el slider si el PIN es incorrecto
  DateTime? _lastActualTempAt;

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
  String? _mqttUserPrefix;
  String? _sessionCode;

  final String _logoUrl =
      "https://res.cloudinary.com/dhmxtqdsb/image/upload/v1764783911/Hrioki_Blanco_yjpn3z.png";

  bool _ecoActive = false;
  double? _tempBeforeEco; // Temperatura seleccionada antes de activar el Modo Eco
  bool get _isSettingsActive =>
      _sessionCode != null && _sessionCode!.isNotEmpty;

  double get _effectiveMaxTemp {
    return _maxTemp > 0 ? _maxTemp : 45;
  }

  void _resetDeviceState() {
    _currentTemp = null;
    _maxTemp = 40;
    _setTemp = null;
    _calefa = false;
    _jet = false;
    _luces = false;
    _ecoActive = false;
    _tempBeforeEco = null;
    _tHys = null;
    _lockSetTemp = false;
    _lockCalefa = false;
    _lockJets = false;
    _lockLuces = false;
    _hasPin = false;
    _sessionPin = null;
    _sessionCode = null;
    _lastActualTempAt = null;
    _isDeviceResponding = false;
  }

  // --- Shared helper for parsing boolean values from incoming data ---
  bool _parseIncomingBool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    final s = value.toString().trim().toLowerCase();
    // Consider 'true', '1', '1.0', 'on' as true
    return s == 'true' || s == '1' || s == '1.0' || s == 'on';
  }

  double? _parseIncomingTemp(dynamic value) {
    final parsed = double.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed <= 0) return null;
    return parsed.clamp(10.0, _effectiveMaxTemp);
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
    _isConnected = widget.initialConnected;
    _loadSerial();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _localStatusTimer?.cancel();
    _connectionWatchdogTimer?.cancel();
    _serialController.dispose();
    _mqtt.disconnect();
    _httpClient.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Si hay un serial cargado, intentar reconectar (la conexión puede haberse perdido en segundo plano)
      if (_serialController.text.isNotEmpty) {
        _autoReconnectOnResume();
      }
    }
  }

  /// Intenta reconectar automáticamente al volver de reposo sin pedir permiso
  void _autoReconnectOnResume() async {
    if (_isLocalAvailable) {
      if (_isConnected) {
        if (_mqttUserPrefix != null) {
          _mqtt.publish('$_mqttUserPrefix/appConectada', 'true');
        }
        return;
      }
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
      final list =
          (jsonDecode(devicesJson) as List).cast<Map<String, dynamic>>();
      _devices = list.map((m) => DeviceInfo.fromJson(m)).toList();
    } catch (_) {
      _devices = [];
    }

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

    // Pre-llenar el campo de serial con el último dispositivo usado
    if (_defaultDeviceSerial != null && _defaultDeviceSerial!.isNotEmpty) {
      _serialController.text = _defaultDeviceSerial!;
    }

    // Si hay dispositivos guardados, manejar auto-conexión/selección
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Si existe un dispositivo predeterminado, intentar conectar usando su último tipo de conexión
      if (_defaultDeviceSerial != null && _defaultDeviceSerial!.isNotEmpty) {
        final defIndex =
            _devices.indexWhere((d) => d.serial == _defaultDeviceSerial);
        if (defIndex != -1) {
          final def = _devices[defIndex];
          final serial = def.serial.trim();
          if (serial.isNotEmpty) {
            await _connectMqtt(serial);
            return;
          }
        }
      }

      if (_devices.length == 1) {
        await _autoConnectSingleDevice();
      } else if (_devices.isNotEmpty) {
        // Si hay varios, preguntar cuál conectar
        final choice = await showDialog<String?>(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: Colors.black,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.white24)),
            title: const Text('Seleccionar dispositivo',
                style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _devices
                    .map((d) => ListTile(
                          title: Text(d.displayName(),
                              style: const TextStyle(color: Colors.white)),
                          subtitle: Text(d.serial,
                              style: const TextStyle(color: Colors.white54)),
                          onTap: () => Navigator.pop(c, d.serial),
                        ))
                    .toList(),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('CANCELAR',
                      style: TextStyle(color: Colors.white70))),
            ],
          ),
        );

        if (choice != null && choice.isNotEmpty) {
          setState(() => _serialController.text = choice);
          await Future.delayed(const Duration(milliseconds: 200));
          if (mounted) await _connect();

          // Preguntar si el usuario quiere usar este dispositivo como predeterminado
          final makeDefault = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              backgroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Colors.white24)),
              title: const Text('Usar como predeterminado?',
                  style: TextStyle(color: Colors.white)),
              content: const Text(
                  '¿Desea usar este dispositivo como predeterminado al iniciar la app?',
                  style: TextStyle(color: Colors.white70)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('NO',
                        style: TextStyle(color: Colors.white70))),
                TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('SÍ',
                        style: TextStyle(
                            color: kAccentColor, fontWeight: FontWeight.bold))),
              ],
            ),
          );
          if (makeDefault == true) {
            await _setDefaultDevice(choice);
          }
        }
      } else {
        // Sin dispositivos guardados: pedir el número de serie
        if (_serialController.text.isEmpty && !_hasAutoStartedScan) {
          _hasAutoStartedScan = true;
          if (mounted) _showConfiguredSerialPrompt();
        }
      }
    });
  }

  void _stopLocalMode() {
    _localStatusTimer?.cancel();
    if (mounted) setState(() => _localBaseUrl = null);
  }

  Future<void> _autoConnectSingleDevice() async {
    final serial = _devices.first.serial.trim();
    if (serial.isEmpty) return;

    setState(() => _serialController.text = serial);
    // Pequeña espera para que la UI termine de estabilizarse
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) await _connect();
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _devices.map((d) => d.toJson()).toList();
    await prefs.setString(kDevicesKey, jsonEncode(jsonList));
    if (_defaultDeviceSerial != null) {
      await prefs.setString(kDefaultDeviceKey, _defaultDeviceSerial!);
    } else {
      await prefs.remove(kDefaultDeviceKey);
    }
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
  Future<void> _addOrUpdateDevice(String serial,
      {String? nickname, String? chipId, String? lastConnection}) async {
    final idx = _devices.indexWhere((d) => d.serial == serial);
    final now = DateTime.now().toIso8601String();
    if (idx >= 0) {
      final existing = _devices[idx];
      existing.nickname = nickname ?? existing.nickname;
      existing.lastSeen = now;
      if (chipId != null) existing.chipId = chipId;
      if (lastConnection != null) existing.lastConnection = lastConnection;
      _devices[idx] = existing;
    } else {
      _devices.add(DeviceInfo(
          serial: serial,
          nickname: nickname,
          lastSeen: now,
          chipId: chipId,
          lastConnection: lastConnection));
    }
    // después de modificar la lista, reordenar para que el más reciente quede al frente
    _sortDevices();
    await _saveDevices();
    if (mounted) setState(() {});
  }

  /// Obtiene el ChipID del dispositivo desde 192.168.4.1/settings (cuando está en modo HIROKI_CONFIG)
  Future<String?> _fetchChipId() async {
    try {
      final uri = Uri.http('192.168.4.1', '/settings');
      final response =
          await _httpClient.get(uri).timeout(const Duration(seconds: 5));
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
                  final list = (jsonDecode(devicesJson) as List)
                      .cast<Map<String, dynamic>>();
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
                  devices.add(
                      DeviceInfo(serial: found, lastSeen: now, chipId: found));
                }
                await prefs.setString(kDevicesKey,
                    jsonEncode(devices.map((d) => d.toJson()).toList()));
                // Auto-select and attempt connection
                if (mounted) {
                  try {
                    setState(() {
                      _serialController.text = found;
                    });
                    await _connect();
                  } catch (_) {}
                }
              } catch (_) {}
            }
            return found;
          }
        } catch (_) {
          // Si no es JSON, intentar extraer de texto plano
          debugPrint(
              'DEBUG: Respuesta HTML recibida (primeros 500 chars): ${response.body.substring(0, math.min(500, response.body.length))}');

          // Primero buscar la línea "Nro de serie: <valor>" en la página
          final serialRegex =
              RegExp(r'Nro de serie[:\s]*([^<\r\n]+)', caseSensitive: false);
          final serialMatch = serialRegex.firstMatch(response.body);
          debugPrint(
              'DEBUG: Búsqueda regex "Nro de serie". Coincidencia: ${serialMatch != null}');

          if (serialMatch != null && serialMatch.groupCount > 0) {
            final found = serialMatch.group(1)?.trim();
            debugPrint('DEBUG: ChipID encontrado: $found');
            if (found != null && found.isNotEmpty) {
              try {
                final prefs = await SharedPreferences.getInstance();
                final devicesJson = prefs.getString(kDevicesKey) ?? '[]';
                List<DeviceInfo> devices;
                try {
                  final list = (jsonDecode(devicesJson) as List)
                      .cast<Map<String, dynamic>>();
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
                  devices.add(
                      DeviceInfo(serial: found, lastSeen: now, chipId: found));
                }
                await prefs.setString(kDevicesKey,
                    jsonEncode(devices.map((d) => d.toJson()).toList()));
                // Auto-select and attempt connection
                if (mounted) {
                  try {
                    setState(() {
                      _serialController.text = found;
                    });
                    await _connect();
                  } catch (_) {}
                }
              } catch (_) {}
            }
            return found;
          }

          // Si no se encontró, caer de nuevo a buscar 'chipid'
          if (response.body.contains('chipid')) {
            final regex = RegExp(r'chipid\\s*[:=]\\s*([A-F0-9a-f]+)',
                caseSensitive: false);
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
    if (_defaultDeviceSerial == serial)
      _defaultDeviceSerial = _devices.isNotEmpty ? _devices.first.serial : null;
    await _saveDevices();
    if (mounted) setState(() {});
  }

  // ignore: unused_element
  Future<void> _setDefaultDevice(String serial) async {
    _defaultDeviceSerial = serial;
    await _saveDevices();
    if (mounted) setState(() {});
  }

  void _applyTemperatureUpdate({
    required double? incomingActualTemp,
    required double? incomingSetTemp,
    required bool hasActualTemp,
  }) {
    final now = DateTime.now();
    if (incomingActualTemp != null) {
      _lastActualTempAt = now;
    } else if (_lastActualTempAt == null) {
      _lastActualTempAt = now;
    }

    _currentTemp = TempSync.resolveCurrentTemp(
      currentTemp: _currentTemp,
      incomingActualTemp: incomingActualTemp,
      incomingSetTemp: incomingSetTemp,
      hasActualTemp: hasActualTemp,
      calefa: _calefa,
      lastActualTempAt: _lastActualTempAt,
      now: now,
      fallbackDelay: const Duration(seconds: 3),
    );
  }

  Future<void> _fetchLocalStatus() async {
    if (!_isLocalAvailable) return;
    try {
      final response = await _httpClient
          .get(Uri.parse('$_localBaseUrl/status'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          _isDeviceResponding = true;
          _cancelConnectionWatchdog();

          // Helpers seguros para evitar errores de tipo (String vs Num vs Bool)
          double? parseDouble(dynamic v) =>
              double.tryParse(v?.toString() ?? '');
          bool parseBool(dynamic v, bool current) {
            if (v == null) return current;
            final s = v.toString().toLowerCase();
            return s == 'true' || s == '1';
          }

          final bool hasActualTemp =
              data.containsKey('TempActual') || data.containsKey('TA');
          final double? parsedSetTemp =
              _parseIncomingTemp(data['SetTemp'] ?? data['TS']);

          final incomingActualTemp =
              parseDouble(data['TempActual'] ?? data['TA']);
          final localCalefa = _parseIncomingBool(
            data['Calefa'] ?? data['AC'],
            defaultValue: _calefa,
          );
          if (!_shouldIgnoreUpdate('Calefa')) {
            _calefa = localCalefa;
          }
          _applyTemperatureUpdate(
            incomingActualTemp: incomingActualTemp,
            incomingSetTemp: parsedSetTemp,
            hasActualTemp: hasActualTemp,
          );

          // Handle maxTemp first
          final localMaxTemp = parseDouble(data['maxTemp'] ?? data['MT']);
          if (localMaxTemp != null) {
            _maxTemp = localMaxTemp;
            _saveMaxTemp(localMaxTemp);
          }

          final localDelay = parseDouble(data['delayCheck'] ?? data['delaycheck'] ?? data['DelayCheck']);
          if (localDelay != null) {
            _delayMinutes = _normalizeDelayMinutes(localDelay);
          }

          final localEco = data['eco'] ?? data['ecoMode'] ?? data['eco_mode'];
          if (localEco != null) {
            _ecoActive = _parseIncomingBool(localEco);
          }

          if (!_shouldIgnoreUpdate('SetTemp')) {
            if (parsedSetTemp != null) _setTemp = parsedSetTemp;
          }

          final localHys =
              parseDouble(data['HYS'] ?? data['tHys'] ?? data['THYS']);
          if (localHys != null) {
            _tHys = localHys;
            _saveHysteresis(localHys);
          }
          if (!_shouldIgnoreUpdate('Calefa'))
            _calefa = _parseIncomingBool(data['Calefa'] ?? data['AC'],
                defaultValue: _calefa);
          if (!_shouldIgnoreUpdate('OnOff'))
            _jet = _parseIncomingBool(data['OnOff'] ?? data['EJ'],
                defaultValue: _jet);
          if (!_shouldIgnoreUpdate('Luces'))
            _luces = _parseIncomingBool(data['Luces'] ?? data['EL'],
                defaultValue: _luces);
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

    // Intentar conexión local y, si no se encuentra, conectar por MQTT directamente
    final localUrl = await _discoveryService.discover(serial);
    bool isConnectedNow = false;

    if (localUrl != null) {
      setState(() {
        _status = 'Modo Local';
        _localBaseUrl = localUrl;
        isConnectedNow = true;
      });
      _localStatusTimer?.cancel();
      _localStatusTimer = Timer.periodic(
          const Duration(seconds: 3), (_) => _fetchLocalStatus());
      await _connectMqtt(serial, isFallback: true);
    } else {
      await _connectMqtt(serial);
    }

    // Cuando entramos en modo local, el _connectMqtt ya registra el dispositivo.
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

      await _addOrUpdateDevice(serial, lastConnection: 'mqtt');

      // start watchdog waiting for device to send status/messages
      _startConnectionWatchdog();
    } else {
      if (mounted) {
        setState(() {
          if (!isFallback) _status = 'Error de conexión MQTT';
        });
      }
      if (mounted && !_isLocalAvailable && !isFallback) {
        _showSimpleDialog('Sin conexión',
            'No se pudo conectar a la nube. Verifique su conexión a Internet.');
      }
    }
  }

  Future<void> _showConfiguredSerialPrompt() async {
    if (!mounted) return;
    final configured = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white24, width: 1)),
        title: const Text('Equipo no encontrado',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'No se encontró ningún equipo Hiroki. ¿El equipo ya fue configurado?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('NO', style: TextStyle(color: Colors.white70))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('SÍ',
                  style: TextStyle(
                      color: kAccentColor, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (configured == true) {
      final serial = await _promptForSerialInput();
      if (serial != null && serial.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _serialController.text = serial;
        });
        await _connectMqtt(serial);
      }
    }
  }

  Future<String?> _promptForSerialInput() async {
    final serialController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white24, width: 1)),
        title: const Text('Ingresar número de serie',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: serialController,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Número de serie',
            hintText: 'Ej. ABC123456',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: kAccentColor)),
          ),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR',
                  style: TextStyle(color: Colors.white70))),
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, serialController.text.trim()),
              child: const Text('ACEPTAR',
                  style: TextStyle(
                      color: kAccentColor, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    serialController.dispose();
    return result?.trim();
  }

  Future<List<String>> _getWifiList() async {
    final List<String> results = [];

    // Local scan (requires location permission)
    try {
      if (await Permission.location.request().isDenied) return [];
      final list = await WiFiForIoTPlugin.loadWifiList();
      for (final item in list) {
        try {
          final ss = item.ssid;
          if (ss != null && ss.toString().isNotEmpty)
            results.add(ss.toString());
        } catch (_) {}
      }
      return results.toSet().toList()..sort();
    } catch (_) {
      return [];
    }
  }

  Future<void> _showSendCredentialsDialog(String ssid) async {
    final passCtrl = TextEditingController();
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white24, width: 1)),
        title: Text('Enviar credenciales a "$ssid"',
            style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('SSID seleccionado:\n$ssid',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            TextField(
                controller: passCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  labelStyle: TextStyle(color: Colors.white60),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: kAccentColor)),
                ),
                obscureText: true),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('CANCELAR',
                  style: TextStyle(color: Colors.white70))),
          TextButton(
              onPressed: () async {
                final pass =
                    passCtrl.text; // Capturamos el texto antes de cerrar
                Navigator.pop(c, true); // Cierra el diálogo de contraseña
                if (!mounted) return;
                _onWifiCredentialsSent(true);
              },
              child: const Text('ENVIAR',
                  style: TextStyle(
                      color: kAccentColor, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    passCtrl.dispose();
  }

  Future<void> _onWifiCredentialsSent(bool success) async {
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Credenciales enviadas. El equipo se reiniciará. Intentando nueva conexión en 15 segundos...'),
        duration: Duration(seconds: 14),
      ));

      await Future.delayed(const Duration(seconds: 15));
      if (!mounted) return;

      // Reset state to show login screen and trigger a new connection attempt
      setState(() {
        _isConnected = false;
        _localBaseUrl = null;
        _status = 'Desconectado';
      });

      // Give UI a moment to switch to login screen
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;

      // Trigger a full connection cycle (mDNS -> MQTT)
      await _connect();
    } else {
      _showSimpleDialog(
          'Error', 'No se pudieron enviar las credenciales al equipo.');
    }
  }

  Future<void> _showWifiConfigDialog() async {
    // Show a scanning dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white24, width: 1)),
        title: const Text('Buscando redes Wi‑Fi...',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
            height: 90,
            child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: const [
              CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(kAccentColor)),
              SizedBox(height: 16),
              Text('Escaneando...', style: TextStyle(color: Colors.white70))
            ]))),
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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Colors.white24, width: 1)),
          title: const Text('No se encontraron redes',
              style: TextStyle(color: Colors.white)),
          content: const Text(
              'No se detectaron redes localmente. ¿Desea ingresar el SSID manualmente?',
              style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('CANCELAR',
                    style: TextStyle(color: Colors.white70))),
            TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('MANUAL',
                    style: TextStyle(
                        color: kAccentColor, fontWeight: FontWeight.bold))),
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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.white24, width: 1)),
            title: const Text('Configurar Wi‑Fi del Equipo',
                style: TextStyle(color: Colors.white)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: ssidCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'SSID (Nombre Red)',
                    labelStyle: TextStyle(color: Colors.white60),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: kAccentColor)),
                  )),
              TextField(
                  controller: passCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    labelStyle: TextStyle(color: Colors.white60),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: kAccentColor)),
                  ),
                  obscureText: true)
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('CANCELAR',
                      style: TextStyle(color: Colors.white70))),
              TextButton(
                  onPressed: () async {
                    Navigator.pop(c);
                    if (!mounted) return;
                    _onWifiCredentialsSent(true);
                  },
                  child: const Text('ENVIAR',
                      style: TextStyle(
                          color: kAccentColor, fontWeight: FontWeight.bold))),
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white24, width: 1)),
        title: const Text('Redes disponibles',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: ssids.length + 1,
            itemBuilder: (context, index) {
              if (index == ssids.length) {
                return ListTile(
                  leading: const Icon(Icons.edit, color: Colors.white60),
                  title: const Text('Ingresar SSID manualmente',
                      style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _showWifiConfigDialog();
                  },
                );
              }
              final ss = ssids[index];
              return ListTile(
                leading: const Icon(Icons.wifi, color: kAccentColor),
                title: Text(ss, style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showSendCredentialsDialog(ss);
                },
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
  void _showSimpleDialog(String title, String content,
      {bool showSpinner = false}) {
    showDialog(
      context: context,
      barrierDismissible: !showSpinner,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white24, width: 1)),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Row(
          children: [
            if (showSpinner) ...[
              const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(kAccentColor)),
              const SizedBox(width: 20)
            ],
            Expanded(
                child: Text(content,
                    style: const TextStyle(color: Colors.white70))),
          ],
        ),
        actions: showSpinner
            ? []
            : [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('OK',
                        style: TextStyle(
                            color: kAccentColor, fontWeight: FontWeight.bold)))
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'La temperatura no puede exceder ${_effectiveMaxTemp.toInt()}°C')));
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

    if (_isLocalAvailable) {
      _sendLocalCommand(_mqttToLocalKeyMap['SetTemp']!, payload);
    } else if (_mqtt.isConnected) {
      // Publicar solo en el canal estándar 'app/SetTemp/value/set'
      final topic = _mqttTopicForCommand('SetTemp');
      if (topic.isNotEmpty) {
        debugPrint(
            'MQTT publish -> $topic : $payload (session ${_sessionCode == null ? "missing" : "present"})');
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
        setState(
            () {}); // Forzar actualización para revertir el switch visualmente
        return;
      }
    }

    _lastInteraction[key] = DateTime.now();
    final mqttPayload = val ? 'true' : 'false';

    String finalMqtt = mqttPayload;

    if (isLocked && _sessionPin != null) {
      finalMqtt += '|$_sessionPin';
    }

    if (_isLocalAvailable) {
      // Local endpoint expects values similar to MQTT (true/false or value)
      _sendLocalCommand(_mqttToLocalKeyMap[key]!, finalMqtt);
    } else if (_mqtt.isConnected) {
      // Publicar solo en el canal estándar 'app/.../value/set'
      final topic = _mqttTopicForCommand(key);
      if (topic.isNotEmpty) {
        debugPrint(
            'MQTT publish -> $topic : $finalMqtt (session ${_sessionCode == null ? "missing" : "present"})');
        _mqtt.publish(topic, finalMqtt);
      }
    }

    // Actualizar UI optimista
    setState(() {
      if (key == 'Calefa') _calefa = val;
      if (key == 'OnOff') _jet = val;
      if (key == 'Luces') _luces = val;
      if (key == 'eco') _ecoActive = val;
    });
  }

void _handleButtonPress(String key, bool value) async {
  // CORRECCIÓN: Se agrega `!_isConnected` para tomar en cuenta la conexión por MQTT/Nube
  if (!_isLocalAvailable && !_isConnected) {
    // Si realmente NO hay ninguna conexión activa (ni Local, ni MQTT), intentamos reconectar
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Reconectando...'), duration: Duration(seconds: 1)),
    );
    _connect().then((_) async {
      if (_isConnected || _isLocalAvailable) {
        await _validateAndToggleEco(key, value);
      }
    });
    return;
  }

  // Si ya estamos conectados por cualquier medio (incluyendo MQTT), enviamos únicamente el comando
  await _validateAndToggleEco(key, value);
}

/// NUEVO AUXILIAR: Intercepta las acciones y gatilla los diálogos de alerta del Modo Eco
Future<void> _validateAndToggleEco(String key, bool value) async {
  // A. Si el usuario intenta encender el Modo Eco
  if (key == 'eco' && value == true) {
    bool? confirmEco = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white24, width: 1)),
        title: const Text('Activar Modo Eco', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Se cambiará a Modo Eco. Se activará la calefacción a 20°C y el botón de calefacción quedará inhabilitado. ¿Desea continuar?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('ACTIVAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirmEco != true) {
      setState(() {});
      return;
    }

    // Guardar la temperatura actual antes de cambiar a Modo Eco
    _tempBeforeEco = _setTemp;

    // Activar calefacción a 20°C
    await _toggleAndPublish('Calefa', true);
    await _publishSetTemp(20.0);
    await _toggleAndPublish('eco', true);

    if (mounted) setState(() {});
    return;
  }

  // B. Si el usuario desactiva el Modo Eco
  if (key == 'eco' && value == false) {
    // Volver a la temperatura seleccionada antes de activar el Modo Eco
    if (_tempBeforeEco != null) {
      await _publishSetTemp(_tempBeforeEco!);
      _tempBeforeEco = null;
    }

    // Dejar la calefacción desactivada
    await _toggleAndPublish('Calefa', false);
    await _toggleAndPublish('eco', false);

    if (mounted) setState(() {});
    return;
  }

  // Agregamos el 'await' para asegurar la ejecución del comando actual (Calefa, Luces, Jets)
  await _toggleAndPublish(key, value);

  // Actualizamos la interfaz al finalizar todo el flujo
  if (mounted) {
    setState(() {});
  }
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
            const Text(
                'Ingrese su PIN para usar esta función en este dispositivo.'),
            const SizedBox(height: 10),
            TextField(
              controller: pinController,
              decoration: const InputDecoration(
                  labelText: 'PIN (6 dígitos)', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('CANCELAR')),
          TextButton(
              onPressed: () => Navigator.pop(c, pinController.text),
              child: const Text('DESBLOQUEAR')),
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
      await _httpClient
          .get(
              Uri.parse('$_localBaseUrl/control_local?var=$varName&val=$value'))
          .timeout(const Duration(seconds: 4));
      _fetchLocalStatus();
    } catch (e) {
      debugPrint('Error enviando comando local: $e');
    }
  }

  void _subscribeAll() {
    if (_mqttUserPrefix == null) return;
    for (var t in [
      'TempActual',
      'maxTemp',
      'delayCheck',
      'eco',
      'SetTemp',
      'HYS',
      'Calefa',
      'OnOff',
      'Luces',
      'SESSION_CODE'
    ]) {
      _mqtt.subscribe('$_mqttUserPrefix/app/$t/value/set');
      // Suscribirse también al estado (value) para recibir actualizaciones del dispositivo (ej: Temperatura)
      _mqtt.subscribe('$_mqttUserPrefix/app/$t/value');
      _mqtt
          .subscribe('$_mqttUserPrefix/app/locks/$t'); // Suscribirse a bloqueos
    }
    _mqtt.subscribe('$_mqttUserPrefix/app/HasPin');
  }

  double _normalizeDelayMinutes(double rawValue) {
    if (rawValue <= 0) return 60.0;
    return rawValue > 120 ? (rawValue / 60.0).clamp(1.0, 120.0) : rawValue.clamp(1.0, 120.0);
  }

  void _setupMqttListener() {
    _subscription?.cancel();
    _subscription = _mqtt.messages.listen((msg) {
      if (_isLocalAvailable) return; // Prioridad a local
      final topic = msg.topic;
      final m = msg.payload as MqttPublishMessage;
      final payload =
          MqttPublishPayload.bytesToStringAsString(m.payload.message).trim();
      if (!mounted) return;
      setState(() {
        // Mark device as responding when we get any MQTT message
        _isDeviceResponding = true;
        _cancelConnectionWatchdog();

        if (topic.contains('TempActual') || topic.contains('SetTemp')) {
          debugPrint('MQTT debug -> topic=$topic payload=$payload');
        }

        if (topic.contains('TempActual'))
          _currentTemp = double.tryParse(payload);
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
        if (topic.contains('delayCheck') || topic.contains('delaycheck')) {
          final value = double.tryParse(payload);
          if (value != null) {
            _delayMinutes = _normalizeDelayMinutes(value);
          }
        }
        if (topic.contains('eco') && !topic.contains('locks')) {
          _ecoActive = _parseIncomingBool(payload);
        }
        if (topic.contains('SetTemp') &&
            !topic.contains('locks') &&
            !_shouldIgnoreUpdate('SetTemp')) {
          final parsedTemp = _parseIncomingTemp(payload);
          if (parsedTemp != null) {
            _setTemp = parsedTemp;
            _applyTemperatureUpdate(
              incomingActualTemp: null,
              incomingSetTemp: parsedTemp,
              hasActualTemp: false,
            );
          }
        }
        if (topic.contains('Calefa') &&
            !topic.contains('locks') &&
            !_shouldIgnoreUpdate('Calefa')) {
          final newCalefa = _parseIncomingBool(payload);
          _calefa = newCalefa;
          if (_setTemp != null) {
            _applyTemperatureUpdate(
              incomingActualTemp: null,
              incomingSetTemp: _setTemp,
              hasActualTemp: false,
            );
          }
        }
        if (topic.contains('OnOff') &&
            !topic.contains('locks') &&
            !_shouldIgnoreUpdate('OnOff')) _jet = _parseIncomingBool(payload);
        if (topic.contains('Luces') &&
            !topic.contains('locks') &&
            !_shouldIgnoreUpdate('Luces')) _luces = _parseIncomingBool(payload);

        if (topic.contains('locks/SetTemp'))
          _lockSetTemp = _parseIncomingBool(payload);
        if (topic.contains('locks/Calefa'))
          _lockCalefa = _parseIncomingBool(payload);
        if (topic.contains('locks/OnOff'))
          _lockJets = _parseIncomingBool(payload);
        if (topic.contains('locks/Luces'))
          _lockLuces = _parseIncomingBool(payload);
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
    if (_isDeviceResponding || _isLocalAvailable) return;
    _logout();
    if (mounted) {
      _showSimpleDialog('Sin respuesta',
          'No se recibió respuesta del equipo. Volviendo al inicio.');
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
      backgroundColor:
          Colors.black, // Asegura un fondo negro al inicio de la aplicación
      body: SafeArea(
          child: _isConnected ? _buildControlPanel() : _buildLoginScreen()),
    );
  }

  Widget _buildLoginScreen() {
    final hasSavedDevices = _devices.isNotEmpty;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.network(
              _logoUrl,
              height: 140,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.broken_image,
                    size: 60, color: Colors.white24);
              },
            ),
            const SizedBox(height: 24),

            if (hasSavedDevices) ...[
              DropdownButtonFormField<String>(
                value: _devices.any((d) => d.serial == _serialController.text)
                    ? _serialController.text
                    : null,
                items: _devices
                    .map((d) => DropdownMenuItem(
                        value: d.serial, child: Text(d.displayName())))
                    .toList(),
                onChanged: (v) => setState(() {
                  if (v != null) _serialController.text = v;
                }),
                decoration:
                    const InputDecoration(labelText: 'Dispositivo conocido'),
              ),
              const SizedBox(height: 14),
            ],

            if (!hasSavedDevices)
              const Text(
                'Sin equipos guardados. Ingresa el número de serie.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60),
              ),

            if (hasSavedDevices || !hasSavedDevices) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _serialController,
                decoration: const InputDecoration(
                  labelText: 'Número de Serie',
                  hintText: 'Ingrese ID del equipo',
                  prefixIcon: Icon(Icons.vpn_key),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _connect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('CONECTAR',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                ),
                if (hasSavedDevices)
                  OutlinedButton(
                      onPressed: _showSavedDevicesDialog,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.all(14),
                      ),
                      child: const Icon(Icons.history, color: Colors.white)),
              ],
            ),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const HirokiConfigPage()));
                },
                icon: const Icon(Icons.wifi_tethering,
                    color: Colors.white60, size: 18),
                label: const Text('Configurar Wi-Fi, equipo clasico',
                    style: TextStyle(color: Colors.white60)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

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
                  return const Icon(Icons.broken_image,
                      size: 30, color: Colors.white24);
                },
              ),
              const SizedBox(
                  width: 10), // Espacio entre el logo y el nuevo botón
              IconButton(
                icon:
                    const Icon(Icons.history, color: Colors.white70, size: 28),
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
                  _devices
                      .firstWhere((d) => d.serial == _serialController.text,
                          orElse: () => DeviceInfo(
                              serial: 'NO_DEVICE',
                              nickname: 'Seleccionar Equipo'))
                      .displayName(),
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
                  if (_isLocalAvailable) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color:
                              _isDeviceResponding ? Colors.green : Colors.red,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _isDeviceResponding
                                  ? Colors.greenAccent.withOpacity(0.6)
                                  : Colors.redAccent.withOpacity(0.6),
                              blurRadius: 6,
                              spreadRadius: 1,
                            )
                          ]),
                    ),
                    const SizedBox(width: 10),
                  ],
                  const Text("🇦🇷", style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 4),
                  const Text("🇯🇵", style: TextStyle(fontSize: 18)),
                ],
              ),
              const Text("Tradición japonesa",
                  style: TextStyle(fontSize: 10, color: Colors.white70)),
              const Text("Fabricación nacional",
                  style: TextStyle(fontSize: 10, color: Colors.white70)),
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
                width: 140,
                height: 140,
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
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(kAccentColor),
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
              ? const Text('error en el sensor de temperatura',
                  style: TextStyle(color: Colors.redAccent, fontSize: 16))
              : const Text('Temperatura actual',
                  style: TextStyle(color: Colors.white60, fontSize: 16)),
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
                Icon(isLocked ? Icons.lock : Icons.thermostat_outlined,
                    color: isLocked ? Colors.redAccent : Colors.white),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 10),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white10,
                      thumbColor: isLocked ? Colors.grey : kAccentColor,
                    ),
                    child: Slider(
                      // 🟢 CORRECCIÓN: Usar _effectiveMaxTemp en lugar de 45
                      value: (_setTemp ?? 25.0).clamp(10.0, _effectiveMaxTemp),
                      min: 10,
                      max: _effectiveMaxTemp,
                      divisions: 50,
                      
                      // Deshabilitar callbacks si _ecoActive es true
                      onChangeStart: _ecoActive ? null : (v) => _tempBeforeChange = _setTemp,
                      onChanged: _ecoActive ? null : (v) => setState(() => _setTemp = v),
                      onChangeEnd: _ecoActive ? null : (v) => _publishSetTemp(v),
                    ),
                  ),
                ),
                Text('${_setTemp?.toInt() ?? "--"}°',
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w400)),
              ],
            ),
            const Text('Temperatura deseada',
                style: TextStyle(color: Colors.white60)),
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
          Icon(isLocked ? Icons.lock : Icons.thermostat_outlined,
              color: isLocked ? Colors.redAccent : Colors.white),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 10),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white10,
                  thumbColor: isLocked ? Colors.grey : kAccentColor,
                ),
                child: Slider(
                  value: (_setTemp ?? 10).clamp(10, _effectiveMaxTemp),
                  min: 10,
                  max: _effectiveMaxTemp,
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
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.w400)),
        ],
      ),
    );
  }

  Widget _buildActionGrid({bool isLandscape = false}) {
    final bool _hasSensorError =
        _currentTemp == -99.0; // Determinar si hay error en el sensor

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
            _buildActionItem('Jets', LucideIcons.waves, _jet, _lockJets, (v) {
              // Changed Icon to LucideIcons.waves
              _handleButtonPress('OnOff', v);
            }, itemWidth),
            // Modificación para el botón de Calefacción: bloqueado visualmente mientras el modo ECO está activo
            _buildActionItem('Calefacción', LucideIcons.thermometer,
                _calefa,
                _lockCalefa || _hasSensorError || _ecoActive, _ecoActive
                    ? null
                    : (v) {
                        // Changed Icon to LucideIcons.thermometer
                        if (_hasSensorError) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'No se puede controlar la calefacción con sensor de temperatura erróneo.')));
                          return;
                        }
                        _handleButtonPress('Calefa', v);
                      }, itemWidth),
            _buildActionItem('Luces', LucideIcons.lightbulb, _luces, _lockLuces,
                (v) {
              // Changed Icon to LucideIcons.lightbulb
              _handleButtonPress('Luces', v);
            }, itemWidth),
            _buildActionItem('Modo Eco', LucideIcons.leaf, _ecoActive, false,
                (v) {
              _handleButtonPress('eco', v);
            }, itemWidth),
          ],
        );
      },
    );
  }

  Widget _buildActionItem(String label, IconData icon, bool active,
      bool isLocked, Function(bool)? onChanged, double width) {
    // Definimos colores según el estado
    final Color cardBackground = active ? Colors.white : Colors.black;
    final Color borderColor = active ? Colors.white : Colors.white12;
    final Color iconColor =
        active ? Colors.black : (isLocked ? Colors.white30 : Colors.white);
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
              if (isLocked)
                const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: Icon(Icons.lock, color: Colors.redAccent, size: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: textColor,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal),
              textAlign: TextAlign.center),
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

  Widget _buildFooterLinks() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        TextButton.icon(
          onPressed: () => _launchUrl('https://instagram.com/hiroki_original'),
          icon: const Icon(Icons.camera_alt_outlined,
              color: Colors.white60, size: 20),
          label: const Text('@hiroki_oficial',
              style: TextStyle(color: Colors.white60)),
        ),
        TextButton.icon(
          onPressed: () => _launchUrl('https://www.hiroki.com.ar'),
          icon: const Icon(Icons.language, color: Colors.white60, size: 20),
          label: const Text('Hiroki', style: TextStyle(color: Colors.white60)),
        ),
      ],
    );
  }

String _mqttTopicForCommand(String key) {
  if (_mqttUserPrefix == null || _mqttUserPrefix!.isEmpty) return '';
  
  if (_sessionCode == null || _sessionCode!.isEmpty) {
    return '$_mqttUserPrefix/devices/$key/set';
  }

  // 🟢 Retorno obligatorio cuando ambas variables tienen valor
  return '$_mqttUserPrefix/devices/$key/set';
}

  Widget _buildExitButton() {
    return InkWell(
      onTap: _logout,
      child: Column(
        children: const [
          Icon(Icons.logout, color: Colors.white, size: 28),
          SizedBox(height: 4),
          Text("SALIR",
              style: TextStyle(
                  letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
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
        setState(() =>
            _statusMsg = 'Conectado a HIROKI_CONFIG. Obteniendo ChipID...');
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
      setState(() =>
          _statusMsg = 'Conéctese primero a la red HIROKI_CONFIG y reintente.');
      return;
    }

    setState(() => _statusMsg = 'Enviando credenciales al dispositivo...');

    final uri =
        Uri.http('192.168.4.1', '/setap', {'ssid': targetSsid, 'pass': pass});
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      final body = resp.body;
      if (resp.statusCode == 200 &&
          body.contains('Configuracion WiFi completa')) {
        setState(
            () => _statusMsg = 'Configuración enviada. Esperando reinicio...');
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
        setState(() => _statusMsg =
            'Respuesta inesperada del dispositivo (código ${resp.statusCode}). Intente abrir el portal manualmente.');
      }
    } catch (e) {
      // En vez de mostrar una alerta, reiniciamos la app.
      if (mounted) {
        setState(() => _statusMsg =
            'Error enviando credenciales. Reiniciando la aplicación...');
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
                  final list = (jsonDecode(devicesJson) as List)
                      .cast<Map<String, dynamic>>();
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
                  devices.add(
                      DeviceInfo(serial: found, lastSeen: now, chipId: found));
                }
                await prefs.setString(kDevicesKey,
                    jsonEncode(devices.map((d) => d.toJson()).toList()));
              } catch (_) {}
            }
            return found;
          }
        } catch (_) {
          // Si no es JSON, intentar extraer de texto plano
          // Buscar primero 'Nro de serie: <valor>' en la página
          debugPrint(
              'DEBUG Config: Respuesta HTML recibida (primeros 500 chars): ${response.body.substring(0, math.min(500, response.body.length))}');

          final serialRegex =
              RegExp(r'Nro de serie[:\s]*([^<\r\n]+)', caseSensitive: false);
          final serialMatch = serialRegex.firstMatch(response.body);
          debugPrint(
              'DEBUG Config: Búsqueda regex "Nro de serie". Coincidencia: ${serialMatch != null}');

          if (serialMatch != null && serialMatch.groupCount > 0) {
            final found = serialMatch.group(1)?.trim();
            debugPrint('DEBUG Config: ChipID encontrado: $found');
            if (found != null && found.isNotEmpty) {
              try {
                final prefs = await SharedPreferences.getInstance();
                final devicesJson = prefs.getString(kDevicesKey) ?? '[]';
                List<DeviceInfo> devices;
                try {
                  final list = (jsonDecode(devicesJson) as List)
                      .cast<Map<String, dynamic>>();
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
                  devices.add(
                      DeviceInfo(serial: found, lastSeen: now, chipId: found));
                }
                await prefs.setString(kDevicesKey,
                    jsonEncode(devices.map((d) => d.toJson()).toList()));
              } catch (_) {}
            }
            return found;
          }

          if (response.body.contains('chipid')) {
            final regex = RegExp(r'chipid\\s*[:=]\\s*([A-F0-9a-f]+)',
                caseSensitive: false);
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
      appBar: AppBar(
          title: const Text('Configurar Wi-Fi (Sin BT)'),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Configurar por Wi-Fi (HIROKI_CONFIG)',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: kAccentColor)),
            const SizedBox(height: 8),
            const Text(
                'Instrucciones: Conecte el teléfono manualmente a la red WI‑FI del equipo (SSID: HIROKI_CONFIG). Luego elija "escanear redes" y seleccione la red de destino y proporcione la clave. Si estado de conexion no esta en verde y debajo no aparece el numero de serie del equipo, quite los datos moviles y presione actualizar, una vez que se ve el nro de serie y cargo los datos de conexion (Red destino y Clave) presione "Enviar credenciales". La app enviará las credenciales automáticamente al equipo sin necesidad de usar el portal.',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: Text(
                        'Estado de conexión: ' +
                            (_connectedSsid ?? 'No conectado'),
                        style: TextStyle(
                            color: (_connectedSsid ?? '').toLowerCase() ==
                                    'hiroki_config'
                                ? kAccentColor
                                : Colors.white))),
                TextButton(
                    onPressed: _refreshConnected,
                    child: const Text('Actualizar',
                        style: TextStyle(
                            color: kAccentColor, fontWeight: FontWeight.bold))),
              ],
            ),
            if (_detectedChipId != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Nro. de Serie: $_detectedChipId',
                  style: const TextStyle(
                      color: kAccentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isScanning ? null : _scanWifi,
                    icon: const Icon(Icons.wifi),
                    label:
                        Text(_isScanning ? 'Escaneando...' : 'Escanear redes'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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
                items: _wifiList
                    .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s,
                            style: const TextStyle(color: Colors.white))))
                    .toList(),
                onChanged: (v) => setState(() => _selectedSsid = v),
                decoration: const InputDecoration(
                  labelText: 'Red destino (SSID)',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: kAccentColor)),
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
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: kAccentColor)),
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
                enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: kAccentColor)),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscurePass ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white54),
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
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('ENVIAR CREDENCIALES AL EQUIPO',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
            const SizedBox(height: 12),
            if (_statusMsg.isNotEmpty)
              Text(_statusMsg,
                  style: const TextStyle(
                      color: kAccentColor, fontWeight: FontWeight.bold)),
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
