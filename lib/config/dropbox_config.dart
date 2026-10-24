/// Public OAuth settings. No access token or client secret belongs here.
class DropboxConfig {
  const DropboxConfig._();

  static const redirectScheme = 'androidlogger';
  static const redirectUri = 'androidlogger://oauth2redirect';
  static const uploadPath = '/android_log.txt';
  static const scope = 'files.content.write';
  static const authorizeHost = 'www.dropbox.com';
  static const tokenUrl = 'https://api.dropboxapi.com/oauth2/token';
  static const revokeUrl = 'https://api.dropboxapi.com/2/auth/token/revoke';
  static const uploadUrl = 'https://content.dropboxapi.com/2/files/upload';

  static const environmentAppKey = String.fromEnvironment('DROPBOX_APP_KEY');
}
