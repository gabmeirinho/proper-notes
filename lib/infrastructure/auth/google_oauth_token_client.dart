import 'dart:convert';

import 'package:http/http.dart' as http;

class GoogleOAuthTokenResponse {
  const GoogleOAuthTokenResponse({
    this.accessToken,
    this.idToken,
    this.refreshToken,
    this.expiresInSeconds,
  });

  final String? accessToken;
  final String? idToken;
  final String? refreshToken;
  final int? expiresInSeconds;
}

class GoogleOAuthTokenClient {
  GoogleOAuthTokenClient({
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  http.Client? _httpClient;

  Future<GoogleOAuthTokenResponse> exchangeAuthorizationCode({
    required String clientId,
    String? clientSecret,
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final response = await _client().post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: <String, String>{
        'client_id': clientId,
        if (clientSecret != null && clientSecret.isNotEmpty)
          'client_secret': clientSecret,
        'code': code,
        'code_verifier': codeVerifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Google token exchange failed: ${response.body}');
    }

    return _parseTokenResponse(response.body);
  }

  Future<GoogleOAuthTokenResponse> refreshAccessToken({
    required String clientId,
    String? clientSecret,
    required String refreshToken,
  }) async {
    if (clientId.trim().isEmpty) {
      throw Exception('Missing OAuth client id for token refresh.');
    }

    final response = await _client().post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: <String, String>{
        'client_id': clientId,
        if (clientSecret != null && clientSecret.isNotEmpty)
          'client_secret': clientSecret,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to refresh Google access token: ${response.body}');
    }

    return _parseTokenResponse(response.body);
  }

  GoogleOAuthTokenResponse _parseTokenResponse(String body) {
    final payload = json.decode(body) as Map<String, dynamic>;
    return GoogleOAuthTokenResponse(
      accessToken: payload['access_token'] as String?,
      idToken: payload['id_token'] as String?,
      refreshToken: payload['refresh_token'] as String?,
      expiresInSeconds: payload['expires_in'] as int?,
    );
  }

  http.Client _client() {
    return _httpClient ??= http.Client();
  }
}
