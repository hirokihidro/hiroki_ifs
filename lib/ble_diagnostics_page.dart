import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/services.dart';
import 'ble_service.dart';

class BleDiagnosticsPage extends StatefulWidget {
  final BleService bleService;
  const BleDiagnosticsPage({super.key, required this.bleService});

  @override
  State<BleDiagnosticsPage> createState() => _BleDiagnosticsPageState();
}

class _BleDiagnosticsPageState extends State<BleDiagnosticsPage> {
  bool _isScanning = false;

  String _deviceName(ScanResult r) {
    final ln = r.advertisementData.localName;
    if (ln.isNotEmpty) return ln;
    if (r.device.name.isNotEmpty) return r.device.name;
    if (r.device.platformName.isNotEmpty) return r.device.platformName;
    return '<sin nombre>';
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    if (_isScanning) widget.bleService.stopScan();
    super.dispose();
  }

  Widget _buildRow(ScanResult r) {
    final name = _deviceName(r);
    final id = r.device.remoteId.toString();
    final rssi = r.rssi;
    final services = r.advertisementData.serviceUuids.join(',');

    // Build manufacturer info with ascii and hex representation
    String manuInfo = '';
    r.advertisementData.manufacturerData.forEach((k, v) {
      final hex = v.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      String ascii = '';
      try { ascii = utf8.decode(v, allowMalformed: true).trim(); } catch (_) { ascii = ''; }
      manuInfo += '$k:${v.length}b';
      if (ascii.isNotEmpty) manuInfo += ' ascii:"$ascii"';
      manuInfo += ' hex:$hex; ';
    });

    return ListTile(
      title: Text(name, style: const TextStyle(color: Colors.white)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('id: $id', style: const TextStyle(color: Colors.white54)),
        Text('rssi: $rssi  services: $services', style: const TextStyle(color: Colors.white54)),
        if (manuInfo.isNotEmpty) Text('manu: $manuInfo', style: const TextStyle(color: Colors.white54)),
      ]),
      trailing: IconButton(
        icon: const Icon(Icons.copy, color: Colors.white24),
        onPressed: () {
          final text = 'name:$name id:$id rssi:$rssi services:$services';
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Info copiada')));
        },
      ),
      onTap: () {
        // When tapping a device we return its serial if the name matches "hiroki<serial>"
        final lower = name.toLowerCase();
        if (lower.startsWith('hiroki') && name.length > 6) {
          final serial = name.substring(6);
          Navigator.pop(context, serial);
        } else {
          Navigator.pop(context, null);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnóstico Bluetooth (BLE)'), backgroundColor: const Color(0xFF1E1E1E)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isScanning
                      ? null
                      : () async {
                          final ok = await widget.bleService.startScan();
                          setState(() => _isScanning = ok);
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar escaneo'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: !_isScanning
                      ? null
                      : () async {
                          await widget.bleService.stopScan();
                          setState(() => _isScanning = false);
                        },
                  icon: const Icon(Icons.stop),
                  label: const Text('Detener'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                ),
                const SizedBox(width: 12),
                if (_isScanning) const Text('Escaneando...', style: TextStyle(color: Colors.cyanAccent))
                else const SizedBox.shrink(),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ScanResult>>(
              stream: widget.bleService.scanResults,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: Text('Esperando resultados...', style: TextStyle(color: Colors.white54)));
                final list = snapshot.data!;
                if (list.isEmpty) return const Center(child: Text('Sin resultados', style: TextStyle(color: Colors.white54)));
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (c, i) => _buildRow(list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
