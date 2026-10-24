/// Outcome of a Dropbox upload attempt.
enum SyncPhase { idle, uploading, success, failure }

/// User-visible synchronization state.
///
/// [phase] becomes [SyncPhase.success] only after the Dropbox API confirms
/// the upload. It is never set from a local guess.
class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.progress = 0,
    this.message,
    this.lastSuccess,
    this.fileBytes,
  });

  final SyncPhase phase;
  final double progress;
  final String? message;
  final DateTime? lastSuccess;
  final int? fileBytes;

  bool get isUploading => phase == SyncPhase.uploading;

  SyncStatus copyWith({
    SyncPhase? phase,
    double? progress,
    String? message,
    DateTime? lastSuccess,
    int? fileBytes,
    bool clearMessage = false,
  }) {
    return SyncStatus(
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      message: clearMessage ? null : (message ?? this.message),
      lastSuccess: lastSuccess ?? this.lastSuccess,
      fileBytes: fileBytes ?? this.fileBytes,
    );
  }
}
