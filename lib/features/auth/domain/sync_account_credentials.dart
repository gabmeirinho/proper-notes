class SyncAccountCredentials {
  const SyncAccountCredentials({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.remoteRoot = 'ProperNotes',
  });

  final String serverUrl;
  final String username;
  final String password;
  final String remoteRoot;
}
