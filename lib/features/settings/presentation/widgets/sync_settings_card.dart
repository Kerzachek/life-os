import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/google_drive_sync_service.dart';
import 'sync_status_banner.dart';

/// Компактный блок управления облачной синхронизацией (Google Drive).
class SyncSettingsCard extends ConsumerWidget {
  const SyncSettingsCard({super.key});

  static const String notConfiguredHint =
      'Вход недоступен: в сборку не переданы OAuth Client ID '
      '(GOOGLE_DESKTOP_CLIENT_ID / GOOGLE_SERVER_CLIENT_ID).';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(googleDriveSyncServiceProvider);
    final service = ref.read(googleDriveSyncServiceProvider.notifier);

    return Card(
      key: const ValueKey('sync_settings_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_sync_rounded,
                    size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Облачная синхронизация',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Google Drive · скрытая папка приложения',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SyncStatusBanner(state: state),
            if (!state.configured) ...[
              const SizedBox(height: 8),
              Text(
                notConfiguredHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!state.signedIn)
                  FilledButton.icon(
                    key: const ValueKey('sync_sign_in'),
                    onPressed: state.configured && !state.isBusy
                        ? service.signIn
                        : null,
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('Войти через Google'),
                  )
                else ...[
                  FilledButton.icon(
                    key: const ValueKey('sync_now'),
                    onPressed: state.isBusy ? null : service.syncNow,
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('Синхронизировать сейчас'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('sync_sign_out'),
                    onPressed: state.isBusy ? null : service.signOut,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Выйти'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
