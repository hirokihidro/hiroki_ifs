import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'mqtt_service.dart';
import 'local_discovery_service.dart';
import 'ble_service.dart';
import 'models/device.dart';

const Color kAccentColor = Colors.white;

String generateMasterKey(String sessionCode) {
  if (sessionCode.isEmpty) return '';
  const secretSalt = "Hiroki_Security_2026_Salt";
  final data = '$sessionCode$secretSalt';
  final hash = sha256.convert(utf8.encode(data));
  // Convert bytes to hex string properly
  final hex = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return hex.substring(0, 6).toUpperCase();
}

class SecurityPage extends StatefulWidget {
  final BleService? bleService;
  final String? localBaseUrl;
  final bool Function(String topic, String payload)? onMqttSend;
  final bool hasPin;
  final String serial;
  final String? sessionCode;
  // sessionCode is already defined via constructor parameter
  // sessionCode is already defined as constructor parameter
  // sessionCode is now required and managed by parent
  // sessionCode is managed by parent via constructor
  // sessionCode is now managed by parent (HomePage) and passed as immutable prop
  // Removed redundant MQTT subscription handling
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
  // Removed local sessionCode management
  // Removed local sessionCode management

  @override
  void initState() {
    super.initState();
    // Inicializar con el sessionCode si está disponible
    
    // Suscribirse al tópico de SESSION_CODE al inicializar el widget
  }

  @override
  void dispose() {
    _oldPinController.dispose();
    _newPinController.dispose();
    _masterKeyController.dispose();
    super.dispose();
  }

  // Removed redundant MQTT subscription - managed by parent

  Future<void> _openMasterConfig() async {
    String? sessionCode = widget.sessionCode;
    
    // Si no tenemos sessionCode almacenado, intentar obtenerlo
    // Usar sessionCode directamente desde el widget
    // Usar el sessionCode actualizado desde MQTT en lugar del inicial
    sessionCode = widget.sessionCode;
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
          )
        ],
      ),
    );

    if (masterKey != null && masterKey == generateMasterKey(sessionCode!.trim())) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => MasterConfigPage(
        bleService: widget.bleService,
        hasPin: widget.hasPin,
        localBaseUrl: widget.localBaseUrl,
        onMqttSend: widget.onMqttSend,
        mqttService: widget.mqttService, // Pasar el servicio MQTT
      )));
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
                  counterText: "",
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
                counterText: "",
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
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => MasterConfigPage(
                    bleService: widget.bleService,
                    hasPin: widget.hasPin,
                    localBaseUrl: widget.localBaseUrl,
                    onMqttSend: widget.onMqttSend,
                    mqttService: widget.mqttService,
                  )));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('CONFIGURACIÓN TÉCNICA', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
            const SizedBox(height: 10),
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
          ],
        ),
      ),
    );
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
         await http.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
         sent = true;
       } catch (_) {}
    }

    setState(() => _isSaving = false);

    if (sent) {
      Navigator.pop(context, true); // Devolver 'true' para indicar éxito
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: No hay conexión con el equipo para guardar.')));
    }
  }
}

class MasterConfigPage extends StatefulWidget {
  final BleService? bleService;
  final String? localBaseUrl;
  final bool Function(String topic, String payload)? onMqttSend;
  final bool hasPin;
  final MqttService? mqttService; // Nuevo

  const MasterConfigPage({super.key, this.bleService, this.localBaseUrl, this.onMqttSend, this.hasPin = false, this.mqttService});

  @override
  State<MasterConfigPage> createState() => _MasterConfigPageState();
}

class _MasterConfigPageState extends State<MasterConfigPage> {
  final _brokerCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  // delay controller removed
  final _oldPinController = TextEditingController();

  double _maxTemp = 40.0;
  double _histeresis = 2.0;
  bool _isSaving = false;
  bool _resetPin = false;

  @override
  void initState() {
    super.initState();
    // Valores por defecto (idealmente se cargarían del dispositivo si hubiera un comando GET)
    _brokerCtrl.text = "hiroki.servidoraweb.net";
    _portCtrl.text = "8883";
    // delay default no longer editable
  }

  @override
  void dispose() {
    _brokerCtrl.dispose();
    _portCtrl.dispose();
    // delay disposed earlier removed
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
      "maxTemp": _maxTemp,
      "histeresis": _histeresis,
      // delayCheck omitted from config
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
         // quitar el tiempo de espera para que la petición no caduque
         await http.get(Uri.parse(url));
         sent = true;
       } catch (_) {}
    }

    setState(() => _isSaving = false);

    if (sent) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configuración Maestra enviada. El equipo se reiniciará.')));
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: No hay conexión para guardar.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Configuración Maestra', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
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
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: CheckboxListTile(
                title: const Text('Restaurar PIN a fábrica (Sin PIN)', style: TextStyle(color: Colors.white)),
                value: _resetPin,
                onChanged: (v) => setState(() => _resetPin = v ?? false),
                activeColor: kAccentColor,
                checkColor: Colors.black,
                controlAffinity: ListTileControlAffinity.trailing,
              ),
            ),
            const SizedBox(height: 25),

            const Text('Configuración MQTT', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kAccentColor)),
            const SizedBox(height: 15),
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
            const SizedBox(height: 15),
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
            
            const SizedBox(height: 35),
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
