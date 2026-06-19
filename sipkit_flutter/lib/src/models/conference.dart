/// Represents an active conference created by [SipKitClient.mergeCalls].
class SipKitConference {
  SipKitConference({
    required this.id,
    required this.callIds,
  });

  /// Unique conference identifier.
  final String id;

  /// IDs of the [SipKitCall]s that are merged into this conference.
  final List<String> callIds;
}
