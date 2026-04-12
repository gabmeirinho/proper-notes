class AuthSession {
  const AuthSession({
    String? email,
    String? displayName,
    String? accountLabel,
    String? serverUrl,
    String? username,
    String? remoteRoot,
  })  : email = email ?? username ?? '',
        displayName = displayName ?? accountLabel ?? username ?? email ?? '',
        accountLabel = accountLabel ?? displayName ?? username ?? email ?? '',
        serverUrl = serverUrl ?? '',
        username = username ?? email ?? '',
        remoteRoot = remoteRoot ?? 'ProperNotes';

  final String email;
  final String displayName;
  final String accountLabel;
  final String serverUrl;
  final String username;
  final String remoteRoot;
}
