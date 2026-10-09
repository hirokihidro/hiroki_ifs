class TempSync {
  static bool shouldUseSetTempAsCurrentTemp({
    required bool hasActualTemp,
    required bool calefa,
    required double? setTemp,
    DateTime? lastActualTempAt,
    DateTime? now,
    Duration fallbackDelay = const Duration(seconds: 3),
  }) {
    if (hasActualTemp || setTemp == null || !calefa) {
      return false;
    }

    if (lastActualTempAt == null) {
      return false;
    }

    final referenceNow = now ?? DateTime.now();
    return referenceNow.difference(lastActualTempAt) >= fallbackDelay;
  }

  static double? resolveCurrentTemp({
    required double? currentTemp,
    required double? incomingActualTemp,
    required double? incomingSetTemp,
    required bool hasActualTemp,
    required bool calefa,
    DateTime? lastActualTempAt,
    DateTime? now,
    Duration fallbackDelay = const Duration(seconds: 5),
  }) {
    if (incomingActualTemp != null) {
      return incomingActualTemp;
    }

    if (shouldUseSetTempAsCurrentTemp(
      hasActualTemp: hasActualTemp,
      calefa: calefa,
      setTemp: incomingSetTemp,
      lastActualTempAt: lastActualTempAt,
      now: now,
      fallbackDelay: fallbackDelay,
    )) {
      return incomingSetTemp;
    }

    return currentTemp;
  }
}
