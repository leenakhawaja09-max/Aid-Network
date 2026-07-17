/// Canonical live-mission request statuses (stored in `requests.status`).
enum MissionStatus {
  created,
  pending,
  pitched,
  helperSelected,
  accepted,
  inProgress,
  arriving,
  completed;

  String get dbValue => switch (this) {
        MissionStatus.created => 'created',
        MissionStatus.pending => 'pending',
        MissionStatus.pitched => 'pitched',
        MissionStatus.helperSelected => 'helper_selected',
        MissionStatus.accepted => 'accepted',
        MissionStatus.inProgress => 'in_progress',
        MissionStatus.arriving => 'arriving',
        MissionStatus.completed => 'completed',
      };

  static MissionStatus? fromDb(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final s = raw.toLowerCase().replaceAll('-', '_');
    return switch (s) {
      'created' => MissionStatus.created,
      'pending' => MissionStatus.pending,
      'pitched' => MissionStatus.pitched,
      'helper_selected' => MissionStatus.helperSelected,
      'accepted' => MissionStatus.accepted,
      'in_progress' => MissionStatus.inProgress,
      'arriving' => MissionStatus.arriving,
      'completed' => MissionStatus.completed,
      'open' || 'urgent' || 'active' => MissionStatus.pending,
      'closed' || 'cancelled' || 'canceled' || 'fulfilled' || 'resolved' =>
        MissionStatus.completed,
      _ => null,
    };
  }

  bool get isDiscoverable => switch (this) {
        MissionStatus.created ||
        MissionStatus.pending ||
        MissionStatus.pitched =>
          true,
        _ => false,
      };

  bool get isLiveMission => switch (this) {
        MissionStatus.accepted ||
        MissionStatus.inProgress ||
        MissionStatus.arriving =>
          true,
        _ => false,
      };

  int get timelineIndex => index;

  static List<MissionStatus> get timelineOrder => MissionStatus.values;
}
