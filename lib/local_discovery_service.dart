import 'dart:async';
import 'package:multicast_dns/multicast_dns.dart';

class LocalDiscoveryService {
  final MDnsClient _mdnsClient;
  bool _isDiscovering = false;

  LocalDiscoveryService({MDnsClient? mdnsClient})
      : _mdnsClient = mdnsClient ?? MDnsClient();

  /// Busca un dispositivo en la red local que coincida con un nombre de servicio específico.
  ///
  /// Escanea por servicios "_http._tcp" y busca uno cuyo nombre termine en ".local"
  /// y comience con el prefijo "hiroki<serial>".
  ///
  /// Devuelve la dirección IP y el puerto como una URL base (ej: "http://192.168.1.10:80").
  /// Retorna `null` si no se encuentra en el tiempo especificado.
  Future<String?> discover(String serial, {Duration timeout = const Duration(seconds: 4)}) async {
    if (_isDiscovering) return null; // Evita búsquedas simultáneas
    _isDiscovering = true;

    final serviceName = 'hiroki$serial';
    const serviceType = '_http._tcp.local';
    String? result;

    try {
      await _mdnsClient.start();

      // Buscamos el servicio específico
      await for (final PtrResourceRecord ptr in _mdnsClient.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(serviceType),
      )) {
        // Para cada puntero, buscamos los registros SRV y A correspondientes
        await for (final SrvResourceRecord srv in _mdnsClient.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          // Comprobamos si el nombre del servicio es el que buscamos
          if (!srv.target.toLowerCase().startsWith(serviceName.toLowerCase())) continue;

          // Encontramos el servicio, ahora buscamos su dirección IP (registro A)
          await for (final IPAddressResourceRecord ip
              in _mdnsClient.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          )) {
            result = 'http://${ip.address.address}:${srv.port}';
            // Detenemos la búsqueda tan pronto como encontramos el primer resultado válido
            break;
          }
        }
        if (result != null) break;
      }
    } catch (e) {
      print('Error durante el descubrimiento mDNS: $e');
    } finally {
      _mdnsClient.stop();
      _isDiscovering = false;
    }

    return result;
  }
}