import 'dart:async';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  MqttServerClient? _client;
  String? _serial;
  String? _sessionCode;
  
  // Outgoing events notify about publishes done by the service (topic, payload)
  final StreamController<Map<String, String>> _outgoingController = StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get outgoing => _outgoingController.stream;

  // Usamos broadcast para que múltiples widgets puedan escuchar si fuera necesario
  // MqttMessage? permite manejar mensajes que la librería entregue como nulos sin crashear
  final StreamController<MqttReceivedMessage<MqttMessage?>> _messagesController = 
      StreamController<MqttReceivedMessage<MqttMessage?>>.broadcast();

  Stream<MqttReceivedMessage<MqttMessage?>> get messages => _messagesController.stream;

  bool get isConnected => _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<bool> connect(String serial, {MqttServerClient? client, bool autoReconnect = false, int reconnectPeriodMillis = 3000}) async {
    final username = 'Hiroki$serial';
    final password = 'HHJP$serial';
    // Generar ID una sola vez para asegurar coincidencia
    final clientIdentifier = 'HirokiApp-$serial-${DateTime.now().millisecondsSinceEpoch}';
    _serial = serial;
    
    _client = client ?? MqttServerClient('hiroki.servidoraweb.net', clientIdentifier);
    
    try {
      _client!.port = 8883; // Puerto 8883
      _client!.logging(on: true);
      _client!.keepAlivePeriod = 20;
      _client!.secure = false; // Sin TLS
    } catch (e) {
      print('MQTT SERVICE: Error configuring client: $e');
      return false;
    }

    _client!.onConnected = () => print('MQTT SERVICE: Conectado al Broker');

    Timer? _reconnectTimer;
    _client!.onDisconnected = () {
      print('MQTT SERVICE: Desconectado del Broker');
      if (autoReconnect) {
        _reconnectTimer?.cancel();
        _reconnectTimer = Timer.periodic(Duration(milliseconds: reconnectPeriodMillis), (timer) async {
          print('MQTT SERVICE: Intentando reconectar...');
          try {
            await _client!.connect(username, password);
            if (_client!.connectionStatus?.state == MqttConnectionState.connected) {
              print('MQTT SERVICE: Reconectado con éxito.');
              final presenceTopic = 'Hiroki$serial/appConectada';
              final builder = MqttClientPayloadBuilder();
              builder.addString('true');
              _client!.publishMessage(presenceTopic, MqttQos.atLeastOnce, builder.payload!, retain: false);
              _outgoingController.add({'topic': presenceTopic, 'payload': 'true'});

              timer.cancel();
            }
          } catch (e) {
            print('MQTT SERVICE: Reconexión fallida: $e');
          }
        });
      }
    };

    _client!.onSubscribed = (topic) => print('MQTT SERVICE: Suscrito a $topic');

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientIdentifier)
        .startClean();
    _client!.connectionMessage = connMess;

    try {
      print('MQTT SERVICE: Conectando a hiroki.servidoraweb.net como $username...');
      await _client!.connect(username, password);
    } catch (e) {
      print('MQTT SERVICE: Error de conexión - $e');
      try { _client!.disconnect(); } catch (_) {}
      return false;
    }

    if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
      print('MQTT SERVICE: Conexión Exitosa.');

      final presenceTopic = 'Hiroki$serial/appConectada';
      final builder = MqttClientPayloadBuilder();
      builder.addString('true');
      _client!.publishMessage(presenceTopic, MqttQos.atLeastOnce, builder.payload!, retain: false);
      print('MQTT SERVICE: Publicado $presenceTopic = true');

      _outgoingController.add({'topic': presenceTopic, 'payload': 'true'});
      
      _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
        if (c != null && c.isNotEmpty) {
          for (final msg in c) {
            print('MQTT SERVICE: Mensaje recibido en tópico: ${msg.topic}');
            if (msg.topic == 'Hiroki$_serial/sessionCode') {
              _sessionCode = msg.payload?.toString();
              print('MQTT SERVICE: Almacenado SESSION_CODE: $_sessionCode');
            }
            _messagesController.add(msg);
          }
        }
      });
      
      return true;
    } else {
      final errorMessage = 'Falló la conexión. Estado: ${_client!.connectionStatus!.state}';
      print('MQTT SERVICE: $errorMessage');
      try { _client!.disconnect(); } catch (_) {}
      return false;
    }
  }

  void disconnect() {
    _client?.disconnect();
    // No cerramos el controller aquí para permitir reconexiones sin recrear el objeto service completo
  }

  void subscribe(String topic) {
    if (isConnected) {
      print('MQTT SERVICE: Suscribiendo a -> $topic');
      _client?.subscribe(topic, MqttQos.atLeastOnce);
    } else {
      print('MQTT SERVICE: Error al suscribir (No conectado) -> $topic');
    }
  }

  void publish(String topic, String payload, {bool retain = false}) {
    if (isConnected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(payload);
      _client?.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!, retain: retain);
      // notify outgoing listeners
      try { _outgoingController.add({'topic': topic, 'payload': payload}); } catch (_) {}
    } else {
      print('MQTT SERVICE: Error al publicar (No conectado) -> $topic');
    }
  }
  String? getSessionCode() => _sessionCode;
}