import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_palette.dart';
import '../providers/settings_provider.dart';

/// «Внешний вид»: режим темы и цветовая палитра. Выбор применяется сразу
/// и хранится в настройках устройства.
class AppearanceSettingsCard extends ConsumerWidget {
  const AppearanceSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mode = ref.watch(themeModeProvider);
    final palette = ref.watch(themePaletteProvider);
    final controller = ref.read(settingsControllerProvider);

    return Card(
      key: const ValueKey('appearance_settings_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.palette_outlined,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Внешний вид',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<AppThemeMode>(
              key: const ValueKey('theme_mode_selector'),
              showSelectedIcon: false,
              segments: [
                for (final m in AppThemeMode.values)
                  ButtonSegment(
                    value: m,
                    icon: Icon(m.icon, size: 18),
                    label: Text(m.label),
                  ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) =>
                  controller.setThemeMode(selection.single),
            ),
            const SizedBox(height: 16),
            Text(
              'Цветовая схема: ${palette.label}',
              key: const ValueKey('theme_palette_label'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final p in AppPalette.values)
                  _PaletteSwatch(
                    palette: p,
                    selected: p == palette,
                    onTap: () =>
                        controller.setThemePalette(p, currentMode: mode),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Кружок палитры: фон её «родной» яркости, половины — основной и
/// дополнительный акценты.
class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = palette.surfaces(palette.naturalBrightness).background;
    return Tooltip(
      message: palette.label,
      child: Semantics(
        button: true,
        selected: selected,
        label: palette.label,
        child: InkWell(
          key: ValueKey('theme_palette_${palette.key}'),
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? colorScheme.primary : colorScheme.outline,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: background,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    background,
                    background,
                    palette.primary,
                    palette.primary,
                    palette.secondary,
                  ],
                  stops: const [0, 0.35, 0.36, 0.7, 0.71],
                ),
              ),
              child: selected
                  ? Icon(
                      Icons.check_rounded,
                      size: 18,
                      color:
                          ThemeData.estimateBrightnessForColor(
                                palette.primary,
                              ) ==
                              Brightness.dark
                          ? Colors.white
                          : Colors.black,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
