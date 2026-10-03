class CallSignal {
  final int fromUserId;
  final dynamic signalData;
  final bool isVideo;
  final String type;

  const CallSignal({
    required this.fromUserId,
    required this.signalData,
    this.isVideo = false,
    required this.type,
  });

  factory CallSignal.fromJson(Map<String, dynamic> json, String type) {
    return CallSignal(
      fromUserId: json['from_user_id'] as int? ?? 0,
      signalData: json['signal_data'],
      isVideo: json['is_video'] as bool? ?? false,
      type: type,
    );
  }

  Map<String, dynamic> toJson(int targetUserId) {
    return {
      'target_user_id': targetUserId,
      'signal_data': signalData,
      'is_video': isVideo,
    };
  }
}
