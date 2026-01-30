import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;

  // UUIDs: Deben coincidir con los de tu ESP32
  final String serviceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  final String characteristicUuid = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;
  
  final StreamController<Map<String, dynamic>> _dataController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get dataStream => _dataController.stream;

  bool get isConnected => _connectedDevice != null && _connectedDevice!.isConnected;
  

  /// Intenta iniciar un escaneo. Retorna true si el escaneo pudo iniciarse correctamente
  /// (Bluetooth encendido y permisos ok). Si falla, retorna false.
  Future<bool> startScan() async {
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      return true;
    } on Exception catch (e) {
      // Puede fallar si Bluetooth está apagado o permisos no concedidos
      print('startScan failed: $e');
      try { await FlutterBluePlus.stopScan(); } catch (_) {}
      return false;
    }
  }

  Future<void> stopScan() async {
    try { await FlutterBluePlus.stopScan(); } catch (_) {}
  }

  /// Verifica si Bluetooth se puede usar (estimando si está encendido) intentando
  /// iniciar un escaneo corto.
  Future<bool> isBluetoothOn() async {
    try {
      final ok = await startScan();
      if (ok) await stopScan();
      return ok;
    } catch (_) {
      return false;
    }
  }

Future<bool> connect(BluetoothDevice device) async {
    try {
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 10),
        license: License.values.first,
      );
      
      _connectedDevice = device;
      
      // Solicitar MTU más alto para Android (ayuda con JSON largos)
      if (Platform.isAndroid) {
        try { await device.requestMtu(512); } catch (_) {}
      }

      final services = await device.discoverServices();
      for (var s in services) {
        for (var c in s.characteristics) {
          // Buscamos característica con escritura (para comandos)
          if (c.properties.write || c.properties.writeWithoutResponse) {
            _writeCharacteristic = c;
          }
          
          // Buscamos característica con notificaciones (para recibir datos)
          if (c.properties.notify) {
            await c.setNotifyValue(true);
            c.onValueReceived.listen((value) {
              try {
                final str = utf8.decode(value).trim();
                // Intentamos decodificar JSON
                try {
                  final json = jsonDecode(str);
                  _dataController.add(json);
                } catch (_) {
                  // Si no es JSON, soportamos el formato de status plano: "STATUS:TA,TS,Jets,Luces,Calefa,MT,HYS"
                  if (str.startsWith('STATUS:')) {
                    final payload = str.substring(7);
                    final parts = payload.split(':');
                    if (parts.length >= 6) {
                      final map = {
                        'topic': 'STATUS',
                        'TA': parts[0],           // Temp Actual
                        'TS': parts[1],           // Set Temp
                        'Jets': parts[2],         // Jets (1/0)
                        'Luces': parts[3],        // Luces (1/0)
                        'Calefa': parts[4],       // Calefa (1/0)
                        'MT': parts[5],           // Max Temp (last)
                      };
                      // Optional hysteresis field (HYS / tHys)
                      if (parts.length >= 7) map['HYS'] = parts[6];
                      // Optional Lock fields (L_Temp, L_Cal, L_Jets, L_Luces)
                      if (parts.length >= 11) {
                        map['L_Temp'] = parts[7];
                        map['L_Cal'] = parts[8];
                        map['L_Jets'] = parts[9];
                        map['L_Luces'] = parts[10];
                      }
                      _dataController.add(map);
                    }
                  } else if (str.startsWith('WIFI_LIST:')) {
                    // WIFI_LIST may arrive as WIFI_LIST:ssid1,ssid2,... or WIFI_LIST:["s1","s2"]
                    final payload = str.substring('WIFI_LIST:'.length);
                    _dataController.add({'topic': 'WIFI_LIST', 'payload': payload});
                  } else {
                    // Si no es status ni JSON, lo exponemos como texto en 'raw'
                    // Additionally, support 'KEY:VALUE' basic format for interoperability
                    final idx = str.indexOf(':');
                    if (idx > 0) {
                      final k = str.substring(0, idx);
                      final v = str.substring(idx + 1);
                      _dataController.add({'topic': k, 'payload': v});
                    } else {
                      _dataController.add({'topic': 'RAW', 'payload': str});
                    }
                  }
                }
              } catch (e) {
                print("Error decodificando BLE: $e");
              }
            });
          }
        }
      }
      return _writeCharacteristic != null;
    } catch (e) {
      print("Error conexión BLE: $e");
      return false;
    }
  }

  void disconnect() {
    _connectedDevice?.disconnect();
    _connectedDevice = null;
    _writeCharacteristic = null;
  }

  Future<bool> sendCommand(String topic, String payload) async {
    if (_writeCharacteristic == null) return false;
    // Enviamos texto plano: "topic:payload" para compatibilidad con parsers simples / SPP-like
    // Si payload está vacío, enviamos sólo el topic (útil para formatos como "setup/wifi|ssid|pass" sin ':' final)
    final data = (payload.isEmpty) ? topic : '$topic|$payload';
    final bytes = utf8.encode(data);
    try {
      // Use the characteristic's preferred write mode when available
      final withoutResponse = _writeCharacteristic!.properties.writeWithoutResponse;
      await _writeCharacteristic!.write(bytes, withoutResponse: withoutResponse);
      return true;
    } catch (e) {
      print("Error enviando comando BLE (primer intento): $e");
      // Intentar con withoutResponse=true en caso de que la característica solo soporte esa forma
      try {
        await _writeCharacteristic!.write(bytes, withoutResponse: true);
        return true;
      } catch (e2) {
        print("Error enviando comando BLE (reintento): $e2");
        return false;
      }
    }
  }
}