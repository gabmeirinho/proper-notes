class ManualSyncResult {
  const ManualSyncResult({
    required this.uploadedCount,
    required this.downloadedCount,
    required this.unchangedCount,
    required this.conflictCount,
    required this.completedAt,
    required this.totalDuration,
    required this.localLoadDuration,
    required this.remoteFetchDuration,
    required this.reconciliationDuration,
  });

  final int uploadedCount;
  final int downloadedCount;
  final int unchangedCount;
  final int conflictCount;
  final DateTime completedAt;
  final Duration totalDuration;
  final Duration localLoadDuration;
  final Duration remoteFetchDuration;
  final Duration reconciliationDuration;

  String summary() {
    final parts = <String>[
      if (uploadedCount > 0) '$uploadedCount uploaded',
      if (downloadedCount > 0) '$downloadedCount downloaded',
      if (unchangedCount > 0) '$unchangedCount unchanged',
      if (conflictCount > 0)
        '$conflictCount conflict${conflictCount == 1 ? '' : 's'} preserved',
    ];

    if (parts.isEmpty) {
      return 'Sync complete. Nothing changed.';
    }

    return 'Sync complete. ${parts.join(', ')}.';
  }
}
