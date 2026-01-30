class DeviceInfo {
  final String serial;
  String? nickname;
  String? lastSeen; // ISO timestamp
  String? chipId; // ChipID del dispositivo (número de serie único)

  DeviceInfo({required this.serial, this.nickname, this.lastSeen, this.chipId});

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
        serial: json['serial'] as String,
        nickname: json['nickname'] as String?,
        lastSeen: json['lastSeen'] as String?,
        chipId: json['chipId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'serial': serial,
        'nickname': nickname,
        'lastSeen': lastSeen,
        'chipId': chipId,
      };

  String displayName() => (nickname != null && nickname!.isNotEmpty) ? nickname! : serial;
}
