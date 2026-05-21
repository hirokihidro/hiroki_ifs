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

  static const Color kAccentColor = Colors.white;

  Future<void> _editNickname(DeviceInfo d) async {
    final controller = TextEditingController(text: d.nickname);
    final res = await showDialog<String?>(context: context, builder: (c) => AlertDialog(
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white24, width: 1),
      ),
      title: const Text(
        'Editar apodo',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Apodo (opcional)',
          hintStyle: TextStyle(color: Colors.white38),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kAccentColor)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('CANCELAR', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, controller.text.trim()),
          child: const Text('OK', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold)),
        ),
      ],
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Dispositivos guardados', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _devices.isEmpty
          ? const Center(
              child: Text(
                'No hay dispositivos guardados',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: _devices.length,
              itemBuilder: (c, i) {
                final d = _devices[i];
                final isDefault = _defaultSerial == d.serial;
                return Card(
                  color: Colors.black,
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isDefault ? kAccentColor.withOpacity(0.6) : Colors.white12,
                      width: 1,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: Text(
                      d.displayName(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    subtitle: d.lastSeen != null && d.lastSeen!.isNotEmpty
                        ? Text(
                            'Visto por última vez: ${d.lastSeen}',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          )
                        : null,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDefault ? kAccentColor.withOpacity(0.1) : Colors.white10,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.memory,
                        color: isDefault ? kAccentColor : Colors.white54,
                        size: 20,
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      color: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.white24, width: 1),
                      ),
                      iconColor: Colors.white70,
                      onSelected: (op) async {
                        if (op == 'edit') await _editNickname(d);
                        if (op == 'default') await _setDefault(d.serial);
                        if (op == 'delete') await _delete(d.serial);
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Editar apodo', style: TextStyle(color: Colors.white)),
                        ),
                        const PopupMenuItem(
                          value: 'default',
                          child: Text('Usar por defecto', style: TextStyle(color: Colors.white)),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                    onTap: () async {
                      Navigator.pop(context, d.serial);
                    },
                  ),
                );
              },
            ),
    );
  }
}
