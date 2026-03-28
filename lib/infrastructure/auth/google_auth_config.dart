class GoogleAuthConfig {
  const GoogleAuthConfig({
    required this.desktopClientId,
    required this.desktopClientSecret,
    required this.androidServerClientId,
  });

  factory GoogleAuthConfig.fromEnvironment() {
    return const GoogleAuthConfig(
      desktopClientId: String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID'),
      desktopClientSecret:
          String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET'),
      androidServerClientId:
          String.fromEnvironment('GOOGLE_ANDROID_SERVER_CLIENT_ID'),
    );
  }

  final String desktopClientId;
  final String desktopClientSecret;
  final String androidServerClientId;

  bool get hasDesktopClientId => desktopClientId.trim().isNotEmpty;
  bool get hasDesktopClientSecret => desktopClientSecret.trim().isNotEmpty;
  bool get hasAndroidServerClientId =>
      androidServerClientId.trim().isNotEmpty;
}
