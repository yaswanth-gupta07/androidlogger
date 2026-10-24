import '../config/dropbox_config.dart';
import 'dropbox_api.dart';
import 'pkce.dart';
import 'secure_store.dart';

typedef AuthorizationBrowser = Future<String?> Function(Uri authorizationUrl);

class DropboxAuthService {
  DropboxAuthService({
    required SecureStore store,
    required DropboxApi api,
    required AuthorizationBrowser browser,
    DateTime Function()? now,
  }) : _store = store,
       _api = api,
       _browser = browser,
       _now = now ?? DateTime.now;

  static const accessKey = 'dropbox_access_token';
  static const refreshKey = 'dropbox_refresh_token';
  static const expiryKey = 'dropbox_access_expiry';
  static const appKeyKey = 'dropbox_app_key';
  static const verifierKey = 'dropbox_pkce_verifier';
  static const stateKey = 'dropbox_oauth_state';
  static const redirectKey = 'dropbox_oauth_redirect';

  final SecureStore _store;
  final DropboxApi _api;
  final AuthorizationBrowser _browser;
  final DateTime Function() _now;

  static final _appKeyPattern = RegExp(r'^[A-Za-z0-9]{8,80}$');

  static String? validateAppKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      return 'Enter the Dropbox app key.';
    }
    if (!_appKeyPattern.hasMatch(trimmed)) {
      return 'The app key should be the public key from the Dropbox App Console.';
    }
    return null;
  }

  static String? parseAuthorizationCode(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    final fromQuery = uri?.queryParameters['code'];
    if (fromQuery != null && fromQuery.isNotEmpty) {
      return fromQuery;
    }
    if (RegExp(r'^[A-Za-z0-9._\-]{8,}$').hasMatch(trimmed)) {
      return trimmed;
    }
    return null;
  }

  static Uri authorizeUri({
    required String appKey,
    required String challenge,
    required String state,
    required bool redirect,
  }) {
    final query = <String, String>{
      'client_id': appKey,
      'response_type': 'code',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'token_access_type': 'offline',
      'state': state,
      'scope': DropboxConfig.scope,
    };
    if (redirect) {
      query['redirect_uri'] = DropboxConfig.redirectUri;
    }
    return Uri.https(DropboxConfig.authorizeHost, '/oauth2/authorize', query);
  }

  Future<String?> readAppKey() => _store.read(appKeyKey);

  Future<void> saveAppKey(String key) async {
    final error = validateAppKey(key);
    if (error != null) {
      throw DropboxException(error);
    }
    await _store.write(appKeyKey, key.trim());
  }

  Future<bool> hasSession() async {
    final refresh = await _store.read(refreshKey);
    if (refresh != null && refresh.isNotEmpty) {
      return true;
    }
    final access = await _store.read(accessKey);
    if (access == null || access.isEmpty) {
      return false;
    }
    final expiryRaw = await _store.read(expiryKey);
    if (expiryRaw == null) {
      return true;
    }
    final expiry = DateTime.tryParse(expiryRaw);
    if (expiry == null) {
      return false;
    }
    return expiry.isAfter(_now());
  }

  Future<void> signInWithRedirect(String appKey) async {
    final error = validateAppKey(appKey);
    if (error != null) {
      throw DropboxException(error);
    }
    final pkce = PkcePair.generate();
    final state = randomUrlToken();
    await _store.write(verifierKey, pkce.verifier);
    await _store.write(stateKey, state);
    await _store.write(redirectKey, '1');
    final url = authorizeUri(
      appKey: appKey.trim(),
      challenge: pkce.challenge,
      state: state,
      redirect: true,
    );
    String? callback;
    try {
      callback = await _browser(url);
    } catch (_) {
      await _clearPending();
      throw DropboxException('Dropbox sign-in failed.');
    }
    if (callback == null || callback.isEmpty) {
      await _clearPending();
      throw DropboxException('Dropbox sign-in was cancelled.');
    }
    final uri = Uri.tryParse(callback);
    if (uri == null) {
      await _clearPending();
      throw DropboxException('Dropbox sign-in failed.');
    }
    final expected = await _store.read(stateKey);
    if (expected == null || uri.queryParameters['state'] != expected) {
      await _clearPending();
      throw DropboxException(
        'The sign-in response could not be verified. Try again.',
      );
    }
    final oauthError = uri.queryParameters['error'];
    if (oauthError != null) {
      await _clearPending();
      if (oauthError == 'access_denied') {
        throw DropboxException('Dropbox sign-in was cancelled.');
      }
      throw DropboxException('Dropbox sign-in failed.');
    }
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      await _clearPending();
      throw DropboxException('Dropbox did not return an authorization code.');
    }
    await _exchange(appKey: appKey.trim(), code: code, redirect: true);
  }

  Future<Uri> beginManualSignIn(String appKey) async {
    final error = validateAppKey(appKey);
    if (error != null) {
      throw DropboxException(error);
    }
    final pkce = PkcePair.generate();
    final state = randomUrlToken();
    await _store.write(verifierKey, pkce.verifier);
    await _store.write(stateKey, state);
    await _store.write(redirectKey, '0');
    return authorizeUri(
      appKey: appKey.trim(),
      challenge: pkce.challenge,
      state: state,
      redirect: false,
    );
  }

  Future<void> completeManualSignIn({
    required String appKey,
    required String rawInput,
  }) async {
    final code = parseAuthorizationCode(rawInput);
    if (code == null) {
      throw DropboxException('Enter the authorization code from Dropbox.');
    }
    await _exchange(appKey: appKey.trim(), code: code, redirect: false);
  }

  Future<String> validAccessToken() async {
    final access = await _store.read(accessKey);
    final expiryRaw = await _store.read(expiryKey);
    if (access != null && access.isNotEmpty) {
      final expiry = expiryRaw == null ? null : DateTime.tryParse(expiryRaw);
      if (expiry == null ||
          expiry.isAfter(_now().add(const Duration(seconds: 60)))) {
        return access;
      }
    }
    return forceRefresh();
  }

  Future<String> forceRefresh() async {
    final refresh = await _store.read(refreshKey);
    final appKey = await _store.read(appKeyKey);
    if (refresh == null ||
        refresh.isEmpty ||
        appKey == null ||
        appKey.isEmpty) {
      await _clearSession();
      throw DropboxException('The Dropbox session expired. Connect again.');
    }
    final token = await _api.refreshToken({
      'grant_type': 'refresh_token',
      'refresh_token': refresh,
      'client_id': appKey,
    });
    await _saveToken(token, fallbackRefresh: refresh);
    return token.accessToken;
  }

  Future<void> disconnect() async {
    final access = await _store.read(accessKey);
    await _clearSession();
    await _clearPending();
    if (access != null && access.isNotEmpty) {
      await _api.revoke(access);
    }
  }

  Future<void> _exchange({
    required String appKey,
    required String code,
    required bool redirect,
  }) async {
    final verifier = await _store.read(verifierKey);
    if (verifier == null || verifier.isEmpty) {
      throw DropboxException('The sign-in session expired. Try again.');
    }
    final fields = <String, String>{
      'code': code,
      'grant_type': 'authorization_code',
      'client_id': appKey,
      'code_verifier': verifier,
    };
    if (redirect) {
      fields['redirect_uri'] = DropboxConfig.redirectUri;
    }
    try {
      final token = await _api.exchangeCode(fields);
      await _store.write(appKeyKey, appKey);
      await _saveToken(token);
      await _clearPending();
    } catch (error) {
      await _clearPending();
      if (error is DropboxException) {
        rethrow;
      }
      throw DropboxException('Dropbox sign-in failed.');
    }
  }

  Future<void> _saveToken(DropboxToken token, {String? fallbackRefresh}) async {
    await _store.write(accessKey, token.accessToken);
    final refresh = token.refreshToken ?? fallbackRefresh;
    if (refresh != null && refresh.isNotEmpty) {
      await _store.write(refreshKey, refresh);
    }
    final expiry = token.expiresAt;
    if (expiry != null) {
      await _store.write(expiryKey, expiry.toIso8601String());
    }
  }

  Future<void> _clearPending() async {
    await _store.delete(verifierKey);
    await _store.delete(stateKey);
    await _store.delete(redirectKey);
  }

  Future<void> _clearSession() async {
    await _store.delete(accessKey);
    await _store.delete(refreshKey);
    await _store.delete(expiryKey);
  }
}
