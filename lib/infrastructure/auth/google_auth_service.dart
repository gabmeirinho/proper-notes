import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/auth/domain/auth_service.dart';
import '../../features/auth/domain/auth_session.dart';
import 'google_auth_config.dart';
import 'google_oauth_token_client.dart';
import 'oauth_session_store.dart';

class GoogleAuthService implements AuthService {
  GoogleAuthService({
    required GoogleAuthConfig config,
    OAuthSessionStore? sessionStore,
    GoogleOAuthTokenClient? tokenClient,
  })  : _config = config,
        _sessionStore = sessionStore ?? SharedPreferencesOAuthSessionStore(),
        _tokenClient = tokenClient ?? GoogleOAuthTokenClient();

  static const _scopes = <String>[
    'openid',
    'email',
    'profile',
    'https://www.googleapis.com/auth/drive.appdata',
  ];
  static const _androidScopeHint = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
  ];
  static const _androidAccessTokenTtl = Duration(minutes: 50);
  final GoogleAuthConfig _config;
  final OAuthSessionStore _sessionStore;
  final GoogleOAuthTokenClient _tokenClient;
  Future<void>? _androidInitialization;

  @override
  Future<AuthSession?> restoreSession() async {
    if (kIsWeb) {
      throw UnsupportedError('Web is not part of this app target.');
    }

    if (Platform.isLinux) {
      return _restoreDesktopSession();
    }

    if (Platform.isAndroid) {
      return _restoreAndroidSession();
    }

    throw UnsupportedError('Google auth is not implemented for this platform.');
  }

  @override
  Future<AuthSession> signIn() async {
    if (kIsWeb) {
      throw UnsupportedError('Web is not part of this app target.');
    }

    if (Platform.isLinux) {
      return _signInDesktop();
    }

    if (Platform.isAndroid) {
      return _signInAndroid();
    }

    throw UnsupportedError('Google auth is not implemented for this platform.');
  }

  @override
  Future<void> signOut() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await GoogleSignIn.instance.disconnect();
      } catch (_) {
        await GoogleSignIn.instance.signOut();
      }
    }

    await _sessionStore.clear();
  }

  Future<AuthSession?> _restoreDesktopSession() async {
    if (!_config.hasDesktopClientId) {
      return null;
    }

    final storedSession = await _sessionStore.read();
    final refreshToken = storedSession?.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }

    final tokenResponse = await _tokenClient.refreshAccessToken(
      clientId: _config.desktopClientId,
      clientSecret:
          _config.hasDesktopClientSecret ? _config.desktopClientSecret : null,
      refreshToken: refreshToken,
    );
    final idToken = tokenResponse.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Google refresh response did not include an id_token.');
    }

    final session = _sessionFromIdToken(idToken);
    await _storeSession(
      session: session,
      refreshToken: refreshToken,
    );
    return session;
  }

  Future<AuthSession> _signInDesktop() async {
    _requireDesktopClientId();

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final port = server.port;
      final redirectUri = 'http://127.0.0.1:$port';
      final state = _randomUrlSafeString(24);
      final codeVerifier = _randomUrlSafeString(64);
      final codeChallenge = _codeChallengeFor(codeVerifier);

      final authUri = Uri.https(
        'accounts.google.com',
        '/o/oauth2/v2/auth',
        <String, String>{
          'client_id': _config.desktopClientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': _scopes.join(' '),
          'access_type': 'offline',
          'prompt': 'consent',
          'state': state,
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
        },
      );

      final launched = await launchUrl(
        authUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception(
            'Could not launch the system browser for Google sign-in.');
      }

      final request = await server.first.timeout(
        const Duration(minutes: 3),
        onTimeout: () {
          throw TimeoutException(
            'Timed out waiting for the Google sign-in redirect.',
          );
        },
      );

      final uri = request.uri;
      final incomingState = uri.queryParameters['state'];
      final error = uri.queryParameters['error'];
      final code = uri.queryParameters['code'];

      await _writeRedirectResponse(request.response, error: error);

      if (incomingState != state) {
        throw Exception('Google sign-in state verification failed.');
      }

      if (error != null) {
        throw Exception('Google sign-in failed: $error');
      }

      if (code == null || code.isEmpty) {
        throw Exception('Google sign-in did not return an authorization code.');
      }

      final tokenResponse = await _tokenClient.exchangeAuthorizationCode(
        clientId: _config.desktopClientId,
        clientSecret:
            _config.hasDesktopClientSecret ? _config.desktopClientSecret : null,
        code: code,
        codeVerifier: codeVerifier,
        redirectUri: redirectUri,
      );
      final idToken = tokenResponse.idToken;
      final refreshToken = tokenResponse.refreshToken;

      if (idToken == null || idToken.isEmpty) {
        throw Exception('Google token exchange did not return an id_token.');
      }

      final session = _sessionFromIdToken(idToken);
      await _storeSession(
        session: session,
        refreshToken: refreshToken,
      );
      return session;
    } finally {
      await server.close(force: true);
    }
  }

  Future<AuthSession?> _restoreAndroidSession() async {
    await _ensureAndroidInitialized();
    final storedSession = await _sessionStore.read();
    return storedSession?.session;
  }

  Future<AuthSession> _signInAndroid() async {
    await _ensureAndroidInitialized();

    final user = await GoogleSignIn.instance.authenticate(
      scopeHint: _androidScopeHint,
    );
    final authorization = await user.authorizationClient.authorizationForScopes(
      _androidScopeHint,
    );
    if (authorization == null) {
      await user.authorizationClient.authorizeScopes(_androidScopeHint);
    }
    final session = AuthSession(
      email: user.email,
      displayName: user.displayName ?? user.email,
    );
    final authHeaders = await user.authorizationClient.authorizationHeaders(
      _androidScopeHint,
      promptIfNecessary: false,
    );
    await _storeSession(
      session: session,
      accessToken: _extractBearerToken(authHeaders),
      accessTokenExpiresAt: DateTime.now().toUtc().add(_androidAccessTokenTtl),
    );
    return session;
  }

  Future<void> _ensureAndroidInitialized() {
    return _androidInitialization ??= GoogleSignIn.instance.initialize(
      serverClientId: _config.hasAndroidServerClientId
          ? _config.androidServerClientId
          : null,
    );
  }

  Future<void> _storeSession({
    required AuthSession session,
    String? refreshToken,
    String? accessToken,
    DateTime? accessTokenExpiresAt,
  }) async {
    await _sessionStore.write(
      session: session,
      refreshToken: refreshToken,
      accessToken: accessToken,
      accessTokenExpiresAt: accessTokenExpiresAt,
    );
  }

  String? _extractBearerToken(Map<String, String>? authHeaders) {
    final authorization = authHeaders?['Authorization'];
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      return null;
    }

    return authorization.substring('Bearer '.length);
  }

  AuthSession _sessionFromIdToken(String idToken) {
    final payload = _decodeJwtPayload(idToken);
    final email = payload['email'] as String?;
    final displayName = payload['name'] as String?;

    if (email == null || email.isEmpty) {
      throw Exception('Google id_token did not include an email.');
    }

    return AuthSession(
      email: email,
      displayName:
          (displayName == null || displayName.isEmpty) ? email : displayName,
    );
  }

  Map<String, dynamic> _decodeJwtPayload(String idToken) {
    final parts = idToken.split('.');
    if (parts.length != 3) {
      throw Exception('Received an invalid Google id_token.');
    }

    final normalized = base64Url.normalize(parts[1]);
    final decoded = utf8.decode(base64Url.decode(normalized));
    return json.decode(decoded) as Map<String, dynamic>;
  }

  String _codeChallengeFor(String codeVerifier) {
    final digest = sha256.convert(ascii.encode(codeVerifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  String _randomUrlSafeString(int length) {
    const charset =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List<String>.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
      growable: false,
    ).join();
  }

  void _requireDesktopClientId() {
    if (!_config.hasDesktopClientId) {
      throw Exception(
        'Missing GOOGLE_DESKTOP_CLIENT_ID. Run the app with '
        '--dart-define=GOOGLE_DESKTOP_CLIENT_ID=your-client-id.apps.googleusercontent.com',
      );
    }
  }

  Future<void> _writeRedirectResponse(
    HttpResponse response, {
    String? error,
  }) async {
    response.headers.contentType = ContentType.html;
    response.write('''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Proper Notes Sign-In</title>
    <style>
      body {
        font-family: sans-serif;
        background: #f6f4ef;
        color: #1f2722;
        padding: 48px;
      }
      .card {
        max-width: 640px;
        margin: 0 auto;
        background: #ffffff;
        border-radius: 16px;
        padding: 24px;
        box-shadow: 0 12px 36px rgba(0, 0, 0, 0.08);
      }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>${error == null ? 'Sign-in complete' : 'Sign-in failed'}</h1>
      <p>${error == null ? 'You can return to Proper Notes now.' : 'Google returned: $error'}</p>
    </div>
  </body>
</html>
''');
    await response.close();
  }
}
