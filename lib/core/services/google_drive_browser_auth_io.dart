import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class GoogleDriveBrowserAuth {
  GoogleDriveBrowserAuth._();

  static Future<Map<String, dynamic>> authorize({
    required String clientId,
    required String clientSecret,
    required String scope,
  }) async {
    final cleanClientId = clientId.trim();
    if (cleanClientId.isEmpty) {
      throw StateError('Google Drive Client ID is required.');
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://localhost:${server.port}/';
    final state = _randomToken(24);
    final verifier = _randomToken(64);
    final challenge = _codeChallenge(verifier);
    final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': cleanClientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': scope,
      'access_type': 'offline',
      'prompt': 'consent',
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    });

    try {
      await openUrl(authUri.toString());
      final request = await server.first.timeout(const Duration(minutes: 3));
      final params = request.uri.queryParameters;
      final html = params['error'] == null
          ? _successHtml
          : _errorHtml(params['error_description'] ??
              params['error'] ??
              'Authorization failed.');
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(html);
      await request.response.close();

      if (params['state'] != state) {
        throw StateError('Google authorization state did not match.');
      }
      final error = params['error'];
      if (error != null && error.isNotEmpty) {
        throw StateError(params['error_description'] ?? error);
      }
      final code = params['code'];
      if (code == null || code.isEmpty) {
        throw StateError('Google authorization code was not returned.');
      }

      final body = <String, String>{
        'client_id': cleanClientId,
        'code': code,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      };
      if (clientSecret.trim().isNotEmpty) {
        body['client_secret'] = clientSecret.trim();
      }
      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      );
      final decoded = response.body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'];
        final description = decoded['error_description'];
        throw StateError(description?.toString() ??
            error?.toString() ??
            'Google authorization failed.');
      }
      return decoded;
    } finally {
      await server.close(force: true);
    }
  }

  static Future<void> openUrl(String url) async {
    if (Platform.isWindows) {
      await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      return;
    }
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
      return;
    }
    if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
      return;
    }
    throw UnsupportedError(
        'Opening a browser is not supported on this platform.');
  }

  static String _randomToken(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _codeChallenge(String verifier) {
    final digest = sha256.convert(ascii.encode(verifier)).bytes;
    return base64UrlEncode(digest).replaceAll('=', '');
  }

  static const String _successHtml = '''
<!doctype html>
<html>
  <head><title>Ventio connected</title></head>
  <body style="font-family:Arial,sans-serif;margin:40px">
    <h2>Google Drive connected</h2>
    <p>You can close this window and return to Ventio.</p>
  </body>
</html>
''';

  static String _errorHtml(String message) => '''
<!doctype html>
<html>
  <head><title>Ventio connection failed</title></head>
  <body style="font-family:Arial,sans-serif;margin:40px">
    <h2>Google Drive connection failed</h2>
    <p>${htmlEscape.convert(message)}</p>
    <p>You can close this window and return to Ventio.</p>
  </body>
</html>
''';
}
