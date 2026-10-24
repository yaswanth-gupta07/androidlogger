import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/dropbox_config.dart';

class DropboxException implements Exception {
  DropboxException(this.message, {this.statusCode, this.unauthorized = false});

  final String message;
  final int? statusCode;
  final bool unauthorized;

  @override
  String toString() => message;
}

class DropboxToken {
  const DropboxToken({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  static DropboxToken fromResponse(
    Map<String, dynamic> json, {
    required DateTime now,
    String? previousRefreshToken,
  }) {
    final access = json['access_token'];
    if (access is! String || access.isEmpty) {
      throw DropboxException('Dropbox did not return an access token.');
    }
    final refresh = json['refresh_token'];
    DateTime? expiry;
    final expiresIn = json['expires_in'];
    if (expiresIn is int) {
      expiry = now.add(Duration(seconds: expiresIn));
    } else if (expiresIn is num) {
      expiry = now.add(Duration(seconds: expiresIn.round()));
    }
    return DropboxToken(
      accessToken: access,
      refreshToken: refresh is String && refresh.isNotEmpty
          ? refresh
          : previousRefreshToken,
      expiresAt: expiry,
    );
  }

  @override
  String toString() =>
      'DropboxToken(hasRefresh: ${refreshToken != null && refreshToken!.isNotEmpty})';
}

class DropboxUploadConfirmation {
  const DropboxUploadConfirmation({this.pathLower, this.rev});

  final String? pathLower;
  final String? rev;
}

abstract class DropboxApi {
  Future<DropboxToken> exchangeCode(Map<String, String> fields);
  Future<DropboxToken> refreshToken(Map<String, String> fields);
  Future<void> revoke(String accessToken);
  Future<DropboxUploadConfirmation> upload({
    required String accessToken,
    required String path,
    required List<int> bytes,
    required void Function(double progress) onProgress,
  });
}

String safeDropboxMessage(int status, String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['error_summary'] is String) {
      final summary = decoded['error_summary'] as String;
      if (summary.length < 180 && !_looksSensitive(summary)) {
        return 'Dropbox rejected the request ($status): $summary';
      }
    }
    if (decoded is Map && decoded['error'] is String) {
      final code = decoded['error'] as String;
      if (code.length < 80 && !_looksSensitive(code)) {
        return 'Dropbox rejected the request ($status): $code';
      }
    }
  } catch (_) {}
  return 'Dropbox request failed ($status).';
}

/// Turns a socket failure into a message that does not hide Dropbox errors.
String describeTransportFailure(Object error) {
  final raw = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  final lower = raw.toLowerCase();
  if (lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('network unreachable') ||
      lower.contains('no address associated')) {
    return "You're offline. Logs will continue to be stored locally.";
  }
  final detail = raw.length > 160 ? raw.substring(0, 160) : raw;
  if (_looksSensitive(detail)) {
    return 'Unable to reach Dropbox.';
  }
  return 'Unable to reach Dropbox. $detail';
}

bool _looksSensitive(String value) {
  final lower = value.toLowerCase();
  return lower.contains('token') ||
      lower.contains('bearer') ||
      lower.contains('secret') ||
      lower.contains('password');
}

void ensureUploadSucceeded(int status, String body) {
  if (status == 401) {
    throw DropboxException(
      'The Dropbox session expired. Connect again.',
      statusCode: status,
      unauthorized: true,
    );
  }
  if (status != 200) {
    throw DropboxException(
      safeDropboxMessage(status, body),
      statusCode: status,
    );
  }
  final decoded = jsonDecode(body);
  if (decoded is! Map ||
      (!decoded.containsKey('id') &&
          !decoded.containsKey('rev') &&
          !decoded.containsKey('path_lower'))) {
    throw DropboxException('Dropbox did not confirm the upload.');
  }
}

class HttpDropboxApi implements DropboxApi {
  HttpDropboxApi({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _now;

  @override
  Future<DropboxToken> exchangeCode(Map<String, String> fields) {
    return _token(fields);
  }

  @override
  Future<DropboxToken> refreshToken(Map<String, String> fields) {
    return _token(fields, previousRefresh: fields['refresh_token']);
  }

  Future<DropboxToken> _token(
    Map<String, String> fields, {
    String? previousRefresh,
  }) async {
    try {
      final response = await _client
          .post(Uri.parse(DropboxConfig.tokenUrl), body: fields)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw DropboxException(
          safeDropboxMessage(response.statusCode, response.body),
          statusCode: response.statusCode,
          unauthorized: response.statusCode == 401,
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw DropboxException(
          'Dropbox returned an unreadable token response.',
        );
      }
      return DropboxToken.fromResponse(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
        now: _now(),
        previousRefreshToken: previousRefresh,
      );
    } on DropboxException {
      rethrow;
    } on SocketException {
      throw DropboxException(
        "You're offline. Logs will continue to be stored locally.",
      );
    } on http.ClientException {
      throw DropboxException(
        "You're offline. Logs will continue to be stored locally.",
      );
    } on TimeoutException {
      throw DropboxException('The Dropbox request timed out.');
    }
  }

  @override
  Future<void> revoke(String accessToken) async {
    try {
      await _client
          .post(
            Uri.parse(DropboxConfig.revokeUrl),
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      // Local sign-out still proceeds when revoke cannot reach Dropbox.
    }
  }

  @override
  Future<DropboxUploadConfirmation> upload({
    required String accessToken,
    required String path,
    required List<int> bytes,
    required void Function(double progress) onProgress,
  }) async {
    // Dropbox rejects chunked uploads and leaves the connection open.
    // A normal request sets Content-Length so the file is actually stored.
    final request = http.Request('POST', Uri.parse(DropboxConfig.uploadUrl));
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.headers['Content-Type'] = 'application/octet-stream';
    request.headers['Dropbox-API-Arg'] = jsonEncode({
      'path': path,
      'mode': 'overwrite',
      'autorename': false,
      'mute': true,
      'strict_conflict': false,
    });
    request.bodyBytes = bytes;
    onProgress(0);
    try {
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 45));
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(const Duration(seconds: 45));
      ensureUploadSucceeded(response.statusCode, response.body);
      final decoded = jsonDecode(response.body);
      final map = decoded is Map ? decoded : const {};
      return DropboxUploadConfirmation(
        pathLower: map['path_lower'] as String?,
        rev: map['rev'] as String?,
      );
    } on DropboxException {
      rethrow;
    } on SocketException {
      throw DropboxException(
        "You're offline. Logs will continue to be stored locally.",
      );
    } on http.ClientException {
      throw DropboxException(
        "You're offline. Logs will continue to be stored locally.",
      );
    } on TimeoutException {
      throw DropboxException('The Dropbox request timed out.');
    }
  }

  void close() {
    _client.close();
  }
}

/// Test double. Success is returned only when [failUpload] is false.
class FakeDropboxApi implements DropboxApi {
  FakeDropboxApi({
    this.failAuth = false,
    this.failUpload = false,
    this.unauthorizedOnce = false,
  });

  bool failAuth;
  bool failUpload;
  bool unauthorizedOnce;
  int uploads = 0;
  int exchanges = 0;
  int refreshes = 0;
  int revocations = 0;
  String? lastUploadToken;

  @override
  Future<DropboxToken> exchangeCode(Map<String, String> fields) async {
    exchanges += 1;
    if (failAuth) {
      throw DropboxException('Dropbox rejected the sign-in.');
    }
    return DropboxToken(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.now().add(const Duration(hours: 4)),
    );
  }

  @override
  Future<DropboxToken> refreshToken(Map<String, String> fields) async {
    refreshes += 1;
    if (failAuth) {
      throw DropboxException('The Dropbox session expired. Connect again.');
    }
    return DropboxToken(
      accessToken: 'refreshed-access-token',
      refreshToken: fields['refresh_token'],
      expiresAt: DateTime.now().add(const Duration(hours: 4)),
    );
  }

  @override
  Future<void> revoke(String accessToken) async {
    revocations += 1;
  }

  @override
  Future<DropboxUploadConfirmation> upload({
    required String accessToken,
    required String path,
    required List<int> bytes,
    required void Function(double progress) onProgress,
  }) async {
    uploads += 1;
    lastUploadToken = accessToken;
    onProgress(1);
    if (unauthorizedOnce) {
      unauthorizedOnce = false;
      throw DropboxException(
        'The Dropbox session expired. Connect again.',
        statusCode: 401,
        unauthorized: true,
      );
    }
    if (failUpload) {
      throw DropboxException('Unable to upload the log file.');
    }
    return const DropboxUploadConfirmation(
      pathLower: '/android_log.txt',
      rev: 'rev-1',
    );
  }
}
