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

  static const Color kAccentColor = Colors.white;

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

    final hasName = name != '<sin nombre>';

    return Card(
      color: Colors.black,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasName ? kAccentColor.withOpacity(0.3) : Colors.white10,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          name,
          style: TextStyle(
            color: Colors.white,
            fontWeight: hasName ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('id: $id', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            Text('rssi: $rssi  services: $services', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            if (manuInfo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('manu: $manuInfo', style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.copy, color: Colors.white38),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Diagnóstico Bluetooth (BLE)', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isScanning
                        ? null
                        : () async {
                            final ok = await widget.bleService.startScan();
                            setState(() => _isScanning = ok);
                          },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Escaneo', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: Colors.white10,
                      disabledForegroundColor: Colors.white24,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: !_isScanning
                        ? null
                        : () async {
                            await widget.bleService.stopScan();
                            setState(() => _isScanning = false);
                          },
                    icon: const Icon(Icons.stop),
                    label: const Text('Detener', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.transparent,
                      disabledForegroundColor: Colors.white10,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(kAccentColor),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text('Escaneando dispositivos...', style: TextStyle(color: kAccentColor, fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<List<ScanResult>>(
              stream: widget.bleService.scanResults,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: Text('Esperando resultados...', style: TextStyle(color: Colors.white54)),
                  );
                }
                final list = snapshot.data!;
                if (list.isEmpty) {
                  return const Center(
                    child: Text('Sin resultados', style: TextStyle(color: Colors.white54)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
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
