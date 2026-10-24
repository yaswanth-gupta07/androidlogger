import 'package:android_logger/config/dropbox_config.dart';
import 'package:android_logger/services/dropbox_api.dart';
import 'package:android_logger/services/dropbox_auth_service.dart';
import 'package:android_logger/services/dropbox_sync_service.dart';
import 'package:android_logger/services/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const appKey = 'abc123xyz9';

  DropboxAuthService authWith({
    required MemorySecureStore store,
    required FakeDropboxApi api,
    required AuthorizationBrowser browser,
  }) {
    return DropboxAuthService(store: store, api: api, browser: browser);
  }

  test('authorization succeeds and stores tokens securely', () async {
    final store = MemorySecureStore();
    final api = FakeDropboxApi();
    final auth = authWith(
      store: store,
      api: api,
      browser: (uri) async {
        expect(uri.queryParameters['code_challenge_method'], 'S256');
        expect(uri.queryParameters['token_access_type'], 'offline');
        expect(uri.queryParameters['redirect_uri'], DropboxConfig.redirectUri);
        expect(uri.queryParameters.containsKey('client_secret'), isFalse);
        final state = uri.queryParameters['state']!;
        return Uri.parse(
          '${DropboxConfig.redirectUri}?code=auth-code&state=$state',
        ).toString();
      },
    );

    await auth.signInWithRedirect(appKey);

    expect(await auth.hasSession(), isTrue);
    expect(store.values[DropboxAuthService.accessKey], 'access-token');
    expect(store.values[DropboxAuthService.refreshKey], 'refresh-token');
    expect(store.values.containsKey(DropboxAuthService.verifierKey), isFalse);
    expect(api.exchanges, 1);
  });

  test('cancelled and failed authorization do not store a session', () async {
    final cancelledStore = MemorySecureStore();
    final cancelled = authWith(
      store: cancelledStore,
      api: FakeDropboxApi(),
      browser: (_) async => null,
    );
    await expectLater(
      cancelled.signInWithRedirect(appKey),
      throwsA(
        isA<DropboxException>().having(
          (error) => error.message,
          'message',
          contains('cancelled'),
        ),
      ),
    );
    expect(await cancelled.hasSession(), isFalse);

    final failed = authWith(
      store: MemorySecureStore(),
      api: FakeDropboxApi(failAuth: true),
      browser: (uri) async {
        return '${DropboxConfig.redirectUri}?code=auth-code&state=${uri.queryParameters['state']}';
      },
    );
    await expectLater(
      failed.signInWithRedirect(appKey),
      throwsA(isA<DropboxException>()),
    );
    expect(await failed.hasSession(), isFalse);
  });

  test('state mismatch is rejected', () async {
    final auth = authWith(
      store: MemorySecureStore(),
      api: FakeDropboxApi(),
      browser: (_) async =>
          '${DropboxConfig.redirectUri}?code=auth-code&state=wrong',
    );
    await expectLater(
      auth.signInWithRedirect(appKey),
      throwsA(isA<DropboxException>()),
    );
  });

  test('upload success is reported only when the api confirms it', () async {
    final store = MemorySecureStore();
    final api = FakeDropboxApi();
    final auth = authWith(
      store: store,
      api: api,
      browser: (uri) async =>
          '${DropboxConfig.redirectUri}?code=auth-code&state=${uri.queryParameters['state']}',
    );
    await auth.signInWithRedirect(appKey);
    final sync = DropboxSyncService(api: api, auth: auth);

    final success = await sync.uploadLog(
      bytes: [1, 2, 3],
      online: true,
      onProgress: (_) {},
    );
    expect(success.succeeded, isTrue);
    expect(success.message, contains('uploaded successfully'));
    expect(api.uploads, 1);

    api.failUpload = true;
    final failure = await sync.uploadLog(
      bytes: [1, 2, 3],
      online: true,
      onProgress: (_) {},
    );
    expect(failure.succeeded, isFalse);
    expect(failure.message, 'Unable to upload the log file.');
  });

  test('upload failure paths do not report success', () async {
    final store = MemorySecureStore();
    final api = FakeDropboxApi();
    final auth = authWith(store: store, api: api, browser: (_) async => null);
    final sync = DropboxSyncService(api: api, auth: auth);

    final disconnected = await sync.uploadLog(
      bytes: [1],
      online: true,
      onProgress: (_) {},
    );
    expect(disconnected.succeeded, isFalse);
    expect(api.uploads, 0);

    await auth.saveAppKey(appKey);
    await store.write(DropboxAuthService.refreshKey, 'refresh-token');
    await store.write(DropboxAuthService.accessKey, 'expired');
    await store.write(
      DropboxAuthService.expiryKey,
      DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    );
    api.unauthorizedOnce = true;
    final refreshed = await sync.uploadLog(
      bytes: [1, 2],
      online: true,
      onProgress: (_) {},
    );
    expect(refreshed.succeeded, isTrue);
    expect(api.uploads, 2);
    expect(api.refreshes, 1);

    final offline = await sync.uploadLog(
      bytes: [1],
      online: false,
      onProgress: (_) {},
    );
    expect(offline.succeeded, isFalse);
    expect(offline.message, contains('offline'));
    expect(api.uploads, 2);
  });

  test('disconnect removes the session', () async {
    final store = MemorySecureStore();
    final api = FakeDropboxApi();
    final auth = authWith(
      store: store,
      api: api,
      browser: (uri) async =>
          '${DropboxConfig.redirectUri}?code=auth-code&state=${uri.queryParameters['state']}',
    );
    await auth.signInWithRedirect(appKey);
    await auth.disconnect();
    expect(await auth.hasSession(), isFalse);
    expect(store.values.containsKey(DropboxAuthService.accessKey), isFalse);
    expect(api.revocations, 1);
    expect(store.values[DropboxAuthService.appKeyKey], appKey);
  });

  test('upload confirmation requires a dropbox metadata response', () {
    expect(
      () => ensureUploadSucceeded(
        200,
        '{"id":"id:1","rev":"rev","path_lower":"/android_log.txt"}',
      ),
      returnsNormally,
    );
    expect(
      () => ensureUploadSucceeded(200, '{"ok":true}'),
      throwsA(isA<DropboxException>()),
    );
    expect(
      () => ensureUploadSucceeded(409, '{"error_summary":"path/not_found/."}'),
      throwsA(isA<DropboxException>()),
    );
    expect(
      () => ensureUploadSucceeded(401, '{}'),
      throwsA(
        isA<DropboxException>().having(
          (error) => error.unauthorized,
          'unauthorized',
          isTrue,
        ),
      ),
    );
  });
}
