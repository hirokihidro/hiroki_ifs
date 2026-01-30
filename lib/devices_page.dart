import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/device.dart';
import 'constants.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});
  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  List<DeviceInfo> _devices = [];
  String? _defaultSerial;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final devicesJson = prefs.getString(kDevicesKey) ?? '[]';
    try {
      final list = (jsonDecode(devicesJson) as List).cast<Map<String, dynamic>>();
      _devices = list.map((m) => DeviceInfo.fromJson(m)).toList();
    } catch (_) { _devices = []; }
    _defaultSerial = prefs.getString(kDefaultDeviceKey);
    if (mounted) setState(() {});
  }

  Future<void> _setDefault(String serial) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kDefaultDeviceKey, serial);
    _defaultSerial = serial;
    if (mounted) setState(() {});
  }

  Future<void> _delete(String serial) async {
    final prefs = await SharedPreferences.getInstance();
    _devices.removeWhere((d) => d.serial == serial);
    await prefs.setString(kDevicesKey, jsonEncode(_devices.map((d) => d.toJson()).toList()));
    if (_defaultSerial == serial) {
      _defaultSerial = _devices.isNotEmpty ? _devices.first.serial : null;
      if (_defaultSerial != null) await prefs.setString(kDefaultDeviceKey, _defaultSerial!);
      else await prefs.remove(kDefaultDeviceKey);
    }
    if (mounted) setState(() {});
  }

  Future<void> _editNickname(DeviceInfo d) async {
    final controller = TextEditingController(text: d.nickname);
    final res = await showDialog<String?>(context: context, builder: (c) => AlertDialog(
      title: const Text('Editar apodo'),
      content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'Apodo (opcional)')),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('CANCELAR')), TextButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text('OK'))],
    ));
    if (res != null) {
      d.nickname = res.isEmpty ? null : res;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kDevicesKey, jsonEncode(_devices.map((d) => d.toJson()).toList()));
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dispositivos guardados')),
      body: _devices.isEmpty ? Center(child: Text('No hay dispositivos guardados', style: TextStyle(color: Colors.white70))) : ListView.builder(
        itemCount: _devices.length,
        itemBuilder: (c, i) {
          final d = _devices[i];
          return ListTile(
            title: Text(d.displayName(), style: const TextStyle(color: Colors.white)),
            subtitle: Text(d.lastSeen ?? '', style: const TextStyle(color: Colors.white54)),
            leading: Icon(Icons.memory, color: _defaultSerial == d.serial ? Colors.cyanAccent : Colors.white54),
            trailing: PopupMenuButton<String>(onSelected: (op) async {
              if (op == 'edit') await _editNickname(d);
              if (op == 'default') await _setDefault(d.serial);
              if (op == 'delete') await _delete(d.serial);
            }, itemBuilder: (ctx) => [const PopupMenuItem(value: 'edit', child: Text('Editar apodo')), const PopupMenuItem(value: 'default', child: Text('Usar por defecto')), const PopupMenuItem(value: 'delete', child: Text('Eliminar'))]),
            onTap: () async {
              // Seleccionar dispositivo como activo y volver
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('serial', d.serial);
              Navigator.pop(context, d.serial);
            },
          );
        }
      ),
    );
  }
}
