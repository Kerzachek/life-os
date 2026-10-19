import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/app_module.dart';
import '../providers/settings_provider.dart';
import '../widgets/module_toggle_tile.dart';
import '../widgets/sync_settings_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const String lastModuleMessage =
      'Нельзя скрыть все разделы: хотя бы один должен оставаться активным';

  Future<void> _onToggle(
    BuildContext context,
    WidgetRef ref,
    AppModule module,
    bool value,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final accepted = await ref
        .read(settingsControllerProvider)
        .setModuleEnabled(module, value);

    if (!accepted) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(lastModuleMessage),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            width: 460,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabledModules = ref.watch(enabledModulesProvider);

    return Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Icon(Icons.settings_rounded, color: colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Настройки',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Персонализация приложения',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.dashboard_customize_rounded,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Активные разделы',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          'Отключённые разделы скрываются из бокового меню. '
                          'Данные при этом не удаляются.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      for (final module in AppModule.values) ...[
                        ModuleToggleTile(
                          key: ValueKey(module),
                          module: module,
                          enabled: enabledModules.contains(module),
                          onChanged: (value) =>
                              _onToggle(context, ref, module, value),
                        ),
                        if (module != AppModule.values.last)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const SyncSettingsCard(),
            ],
          ),
        ),
      ),
    );
  }
}
