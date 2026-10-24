import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/dropbox_config.dart';
import 'dropbox_api.dart';
import 'dropbox_auth_service.dart';

class SyncOutcome {
  const SyncOutcome.success({required this.bytes, this.confirmation})
    : succeeded = true,
      message = 'android_log.txt uploaded successfully.';

  const SyncOutcome.failure(this.message)
    : succeeded = false,
      bytes = 0,
      confirmation = null;

  final bool succeeded;
  final String message;
  final int bytes;
  final DropboxUploadConfirmation? confirmation;
}

/// Uploads the current log only after Dropbox confirms the file.
class DropboxSyncService {
  DropboxSyncService({
    required DropboxApi api,
    required DropboxAuthService auth,
  }) : _api = api,
       _auth = auth;

  final DropboxApi _api;
  final DropboxAuthService _auth;

  Future<SyncOutcome> uploadLog({
    required List<int> bytes,
    required bool online,
    required void Function(double progress) onProgress,
  }) async {
    if (!await _auth.hasSession()) {
      return const SyncOutcome.failure('Dropbox is not connected.');
    }
    if (!online) {
      return const SyncOutcome.failure(
        "You're offline. Logs will continue to be stored locally.",
      );
    }
    if (bytes.isEmpty) {
      return const SyncOutcome.failure('The log file could not be created.');
    }
    try {
      final token = await _auth.validAccessToken();
      final confirmation = await _uploadWithRefresh(
        token: token,
        bytes: bytes,
        onProgress: onProgress,
      );
      return SyncOutcome.success(
        bytes: bytes.length,
        confirmation: confirmation,
      );
    } catch (error) {
      return SyncOutcome.failure(_message(error));
    }
  }

  Future<DropboxUploadConfirmation> _uploadWithRefresh({
    required String token,
    required List<int> bytes,
    required void Function(double progress) onProgress,
  }) async {
    try {
      return await _api.upload(
        accessToken: token,
        path: DropboxConfig.uploadPath,
        bytes: bytes,
        onProgress: onProgress,
      );
    } on DropboxException catch (error) {
      if (!error.unauthorized) {
        rethrow;
      }
      final refreshed = await _auth.forceRefresh();
      return _api.upload(
        accessToken: refreshed,
        path: DropboxConfig.uploadPath,
        bytes: bytes,
        onProgress: onProgress,
      );
    }
  }

  String _message(Object error) {
    if (error is DropboxException) {
      return error.message;
    }
    if (error is SocketException ||
        error is HttpException ||
        error is http.ClientException ||
        error is TimeoutException) {
      return "You're offline. Logs will continue to be stored locally.";
    }
    return 'Unable to upload the log file.';
  }
}
