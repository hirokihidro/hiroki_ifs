import 'package:flutter_test/flutter_test.dart';
import 'package:HirokiIFS/temp_sync.dart';

void main() {
  group('TempSync', () {
    test('does not use setTemp immediately when no actual temp has been received yet', () {
      final resolved = TempSync.resolveCurrentTemp(
        currentTemp: 20,
        incomingActualTemp: null,
        incomingSetTemp: 24,
        hasActualTemp: false,
        calefa: true,
      );

      expect(resolved, 20);
    });

    test('uses setTemp as current temp after the fallback delay when heater is on', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      final resolved = TempSync.resolveCurrentTemp(
        currentTemp: 20,
        incomingActualTemp: null,
        incomingSetTemp: 24,
        hasActualTemp: false,
        calefa: true,
        lastActualTempAt: now.subtract(const Duration(seconds: 4)),
        now: now,
        fallbackDelay: const Duration(seconds: 3),
      );

      expect(resolved, 24);
    });

    test('keeps current temp when actual temp is received', () {
      final resolved = TempSync.resolveCurrentTemp(
        currentTemp: 20,
        incomingActualTemp: 21,
        incomingSetTemp: 24,
        hasActualTemp: true,
        calefa: true,
      );

      expect(resolved, 21);
    });

    test('does not use setTemp when heater is off', () {
      final resolved = TempSync.resolveCurrentTemp(
        currentTemp: 20,
        incomingActualTemp: null,
        incomingSetTemp: 24,
        hasActualTemp: false,
        calefa: false,
      );

      expect(resolved, 20);
    });

    test('delays setTemp fallback until the grace period has passed', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      final resolved = TempSync.resolveCurrentTemp(
        currentTemp: 20,
        incomingActualTemp: null,
        incomingSetTemp: 24,
        hasActualTemp: false,
        calefa: true,
        lastActualTempAt: now.subtract(const Duration(seconds: 3)),
        now: now,
        fallbackDelay: const Duration(seconds: 5),
      );

      expect(resolved, 20);
    });

    test('uses setTemp after the grace period expires', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      final resolved = TempSync.resolveCurrentTemp(
        currentTemp: 20,
        incomingActualTemp: null,
        incomingSetTemp: 24,
        hasActualTemp: false,
        calefa: true,
        lastActualTempAt: now.subtract(const Duration(seconds: 6)),
        now: now,
        fallbackDelay: const Duration(seconds: 5),
      );

      expect(resolved, 24);
    });
  });
}
