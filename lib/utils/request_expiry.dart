/// Help requests expire 24 hours after creation (unless a live mission is in progress).
const Duration requestMaxAge = Duration(hours: 24);

const _protectedStatuses = {
  'accepted',
  'in_progress',
  'arriving',
  'helper_selected',
  'awaiting_helper_ack',
};

String _normStatus(String? raw) =>
    (raw ?? '').toLowerCase().replaceAll('-', '_');

bool requestIsProtectedFromExpiry(Map<String, dynamic> request) {
  return _protectedStatuses.contains(_normStatus(request['status']?.toString()));
}

DateTime? requestCreatedAt(Map<String, dynamic> request) {
  return DateTime.tryParse(request['created_at']?.toString() ?? '');
}

/// True when the request is older than [requestMaxAge] and not an active mission.
bool isRequestExpired(
  Map<String, dynamic> request, {
  DateTime? now,
  String? exceptRequestId,
}) {
  final id = request['id']?.toString();
  if (exceptRequestId != null && id == exceptRequestId) return false;
  if (requestIsProtectedFromExpiry(request)) return false;
  final created = requestCreatedAt(request);
  if (created == null) return false;
  final ref = (now ?? DateTime.now()).toUtc();
  return ref.difference(created.toUtc()) > requestMaxAge;
}

bool isRequestVisibleForDiscovery(
  Map<String, dynamic> request, {
  String? exceptRequestId,
}) {
  return !isRequestExpired(request, exceptRequestId: exceptRequestId);
}
