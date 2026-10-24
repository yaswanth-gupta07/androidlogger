import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../config/dropbox_config.dart';
import '../models/sync_status.dart';
import '../services/dropbox_api.dart';
import '../services/dropbox_auth_service.dart';
import '../services/dropbox_sync_service.dart';
import '../services/preference_store.dart';
import 'device_status_provider.dart';

class DropboxController extends ChangeNotifier {
  DropboxController({
    required DropboxAuthService auth,
    required DropboxSyncService sync,
    required DeviceStatusController deviceStatus,
    required PreferenceStore preferences,
    required String Function() exportText,
    DateTime Function()? now,
    bool connected = false,
    String appKey = '',
    SyncStatus status = const SyncStatus(),
  }) : _auth = auth,
       _sync = sync,
       _device = deviceStatus,
       _preferences = preferences,
       _exportText = exportText,
       _now = now ?? DateTime.now,
       _connected = connected,
       _appKey = appKey,
       _status = status;

  static const _lastSyncKey = 'dropbox_last_sync';
  static const _lastBytesKey = 'dropbox_last_bytes';

  final DropboxAuthService _auth;
  final DropboxSyncService _sync;
  final DeviceStatusController _device;
  final PreferenceStore _preferences;
  final String Function() _exportText;
  final DateTime Function() _now;
  bool _connected;
  String _appKey;
  SyncStatus _status;
  bool _busy = false;
  bool _disposed = false;

  bool get connected => _connected;
  String get appKey => _appKey;
  SyncStatus get status => _status;
  bool get busy => _busy;

  Future<void> load() async {
    final storedKey = await _auth.readAppKey();
    if (storedKey != null && storedKey.isNotEmpty) {
      _appKey = storedKey;
    } else if (DropboxConfig.environmentAppKey.isNotEmpty) {
      _appKey = DropboxConfig.environmentAppKey;
      try {
        await _auth.saveAppKey(_appKey);
      } on DropboxException {
        _appKey = '';
      }
    }
    _connected = await _auth.hasSession();
    final lastSync = await _preferences.getString(_lastSyncKey);
    final bytesRaw = await _preferences.getString(_lastBytesKey);
    _status = _status.copyWith(
      lastSuccess: lastSync == null ? null : DateTime.tryParse(lastSync),
      fileBytes: bytesRaw == null ? null : int.tryParse(bytesRaw),
    );
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<String?> saveAppKey(String key) async {
    final error = DropboxAuthService.validateAppKey(key);
    if (error != null) {
      return error;
    }
    await _auth.saveAppKey(key);
    _appKey = key.trim();
    if (!_disposed) {
      notifyListeners();
    }
    return null;
  }

  Future<void> connect() async {
    if (_busy) {
      return;
    }
    final validation = DropboxAuthService.validateAppKey(_appKey);
    if (validation != null) {
      _status = _status.copyWith(phase: SyncPhase.failure, message: validation);
      notifyListeners();
      return;
    }
    await _run(() async {
      await _auth.signInWithRedirect(_appKey);
      _connected = true;
      _status = _status.copyWith(
        phase: SyncPhase.idle,
        clearMessage: true,
        progress: 0,
      );
    });
  }

  Future<Uri> beginManualConnect() {
    return _auth.beginManualSignIn(_appKey);
  }

  Future<void> completeManualConnect(String rawInput) async {
    if (_busy) {
      return;
    }
    await _run(() async {
      await _auth.completeManualSignIn(appKey: _appKey, rawInput: rawInput);
      _connected = true;
      _status = _status.copyWith(
        phase: SyncPhase.idle,
        clearMessage: true,
        progress: 0,
      );
    });
  }

  Future<bool> syncNow() async {
    if (_busy || _status.isUploading) {
      return false;
    }
    if (!_connected) {
      _status = _status.copyWith(
        phase: SyncPhase.failure,
        message: 'Dropbox is not connected.',
      );
      notifyListeners();
      return false;
    }
    _busy = true;
    _status = _status.copyWith(
      phase: SyncPhase.uploading,
      progress: 0,
      message: 'Uploading...',
    );
    notifyListeners();
    final bytes = utf8.encode(_exportText());
    final outcome = await _sync.uploadLog(
      bytes: bytes,
      online: _device.canSync,
      onProgress: (progress) {
        if (_disposed) {
          return;
        }
        _status = _status.copyWith(
          phase: SyncPhase.uploading,
          progress: progress,
          message: progress >= 1 ? 'Waiting for Dropbox...' : 'Uploading...',
        );
        notifyListeners();
      },
    );
    _busy = false;
    if (outcome.succeeded) {
      final syncedAt = _now();
      _status = SyncStatus(
        phase: SyncPhase.success,
        progress: 1,
        message: outcome.message,
        lastSuccess: syncedAt,
        fileBytes: outcome.bytes,
      );
      await _preferences.setString(_lastSyncKey, syncedAt.toIso8601String());
      await _preferences.setString(_lastBytesKey, '${outcome.bytes}');
    } else {
      _status = _status.copyWith(
        phase: SyncPhase.failure,
        progress: 0,
        message: outcome.message,
      );
    }
    if (!_disposed) {
      notifyListeners();
    }
    return outcome.succeeded;
  }

  Future<void> disconnect() async {
    if (_busy) {
      return;
    }
    await _run(() async {
      await _auth.disconnect();
      _connected = false;
      _status = SyncStatus(lastSuccess: _status.lastSuccess);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      await action();
    } on DropboxException catch (error) {
      _status = _status.copyWith(
        phase: SyncPhase.failure,
        message: error.message,
      );
    } catch (_) {
      _status = _status.copyWith(
        phase: SyncPhase.failure,
        message: 'Dropbox sign-in failed.',
      );
    } finally {
      _busy = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
