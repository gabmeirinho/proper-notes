import 'package:flutter/material.dart';

import '../application/auth_controller.dart';

class AccountSheet extends StatelessWidget {
  const AccountSheet({
    required this.authController,
    super.key,
  });

  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: authController,
      builder: (context, _) {
        final session = authController.session;
        final isBusy = authController.isBusy;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Account',
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
                child: session == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Not signed in',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Google sign-in powers the future sync backend. On Linux, run the app with GOOGLE_DESKTOP_CLIENT_ID configured.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.displayName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            session.email,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
              ),
              if (authController.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  authController.errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isBusy
                      ? null
                      : () async {
                          if (session == null) {
                            await authController.signIn();
                          } else {
                            await authController.signOut();
                          }

                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                  icon: Icon(session == null ? Icons.login : Icons.logout),
                  label: Text(
                    isBusy
                        ? 'Working...'
                        : (session == null ? 'Sign in' : 'Sign out'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
