import 'package:flutter/material.dart';

import '../application/auth_controller.dart';
import '../domain/sync_account_credentials.dart';

class AccountSheet extends StatefulWidget {
  const AccountSheet({
    required this.authController,
    super.key,
  });

  final AuthController authController;

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  late final TextEditingController _serverUrlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _remoteRootController;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    final session = widget.authController.session;
    _serverUrlController =
        TextEditingController(text: session?.serverUrl ?? '');
    _usernameController = TextEditingController(text: session?.username ?? '');
    _passwordController = TextEditingController();
    _remoteRootController = TextEditingController(
      text: session?.remoteRoot ?? 'ProperNotes',
    );
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _remoteRootController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.authController,
      builder: (context, _) {
        final session = widget.authController.session;
        final isBusy = widget.authController.isBusy;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sync account',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    session == null
                        ? 'Connect a WebDAV account. Nextcloud app passwords are the recommended v1 target.'
                        : 'Connected as ${session.accountLabel}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _serverUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText:
                        'https://cloud.example.com/remote.php/dav/files/user',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'App password',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _remoteRootController,
                  decoration: const InputDecoration(
                    labelText: 'Remote folder',
                    hintText: 'ProperNotes',
                  ),
                ),
                if (widget.authController.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.authController.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_statusMessage != null &&
                    widget.authController.errorMessage == null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _statusMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: isBusy ? null : _handleTestConnection,
                    child: Text(isBusy ? 'Working...' : 'Test connection'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: isBusy ? null : _handleSaveConnection,
                    child: Text(isBusy ? 'Working...' : 'Save connection'),
                  ),
                ),
                if (session != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: isBusy ? null : _handleDisconnect,
                      child: const Text('Disconnect'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleTestConnection() async {
    final credentials = _buildCredentials();
    if (credentials == null) {
      setState(() {
        _statusMessage =
            'Enter the server URL, username, and app password first.';
      });
      return;
    }

    setState(() {
      _statusMessage = null;
    });

    await widget.authController.testConnection(credentials);
    if (!mounted) {
      return;
    }
    if (widget.authController.errorMessage == null) {
      setState(() {
        _statusMessage = 'Connection OK. You can save this account now.';
      });
    }
  }

  Future<void> _handleSaveConnection() async {
    final credentials = _buildCredentials();
    if (credentials == null) {
      setState(() {
        _statusMessage =
            'Enter the server URL, username, and app password first.';
      });
      return;
    }
    setState(() {
      _statusMessage = null;
    });
    await widget.authController.saveConnection(credentials);
    if (mounted && widget.authController.errorMessage == null) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleDisconnect() async {
    setState(() {
      _statusMessage = null;
    });
    await widget.authController.clearConnection();
    if (mounted && widget.authController.errorMessage == null) {
      Navigator.of(context).pop();
    }
  }

  SyncAccountCredentials? _buildCredentials() {
    final serverUrl = _serverUrlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final remoteRoot = _remoteRootController.text.trim().isEmpty
        ? 'ProperNotes'
        : _remoteRootController.text.trim();
    if (serverUrl.isEmpty || username.isEmpty || password.isEmpty) {
      return null;
    }

    return SyncAccountCredentials(
      serverUrl: serverUrl,
      username: username,
      password: password,
      remoteRoot: remoteRoot,
    );
  }
}
