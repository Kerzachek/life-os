import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/theme/app_palette.dart';
import 'package:home_organizer/core/theme/app_theme.dart';
import 'package:home_organizer/features/settings/presentation/providers/settings_provider.dart';
import 'package:home_organizer/features/settings/presentation/screens/settings_screen.dart';
import 'package:home_organizer/features/settings/presentation/widgets/appearance_settings_card.dart';

void main() {
  group('палитры и режимы', () {
    test('по умолчанию — тёмная Cyber Obsidian', () {
      expect(AppThemeMode.fromKey(null), AppThemeMode.dark);
      expect(AppThemeMode.fromKey('garbage'), AppThemeMode.dark);
      expect(AppPalette.fromKey(null), AppPalette.cyberObsidian);
      expect(AppPalette.fromKey('garbage'), AppPalette.cyberObsidian);
    });

    test('ключи уникальны и читаются обратно', () {
      expect(AppPalette.values, hasLength(greaterThanOrEqualTo(4)));
      for (final p in AppPalette.values) {
        expect(AppPalette.fromKey(p.key), p);
      }
      for (final m in AppThemeMode.values) {
        expect(AppThemeMode.fromKey(m.key), m);
      }
    });

    test('тема по умолчанию совпадает с прежней тёмной', () {
      final theme = AppTheme.darkLauncherTheme;
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppTheme.darkBackground);
      expect(theme.colorScheme.primary, AppTheme.primaryAccent);
      expect(theme.colorScheme.surface, AppTheme.darkSurfaceCard);
      expect(theme.colorScheme.outline, AppTheme.darkBorder);
    });

    test('контейнеры FAB и сегментов берутся из палитры', () {
      for (final p in AppPalette.values) {
        for (final b in Brightness.values) {
          final scheme = AppTheme.build(p, b).colorScheme;
          expect(scheme.primaryContainer, p.primary, reason: '${p.label} $b');
          expect(scheme.secondaryContainer, p.secondary);
        }
      }
    });

    test('у каждой палитры текст контрастен фону в обеих яркостях', () {
      for (final p in AppPalette.values) {
        for (final b in Brightness.values) {
          final theme = AppTheme.build(p, b);
          expect(theme.brightness, b, reason: '${p.label} $b');
          final bg = theme.scaffoldBackgroundColor.computeLuminance();
          final fg = theme.colorScheme.onSurface.computeLuminance();
          final contrast =
              (([bg, fg]..sort()).last + 0.05) /
              (([bg, fg]..sort()).first + 0.05);
          expect(contrast, greaterThan(7), reason: '${p.label} $b');
        }
      }
    });
  });

  group('SettingsController', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<Map<String, String>> read() async {
      final rows = await db.select(db.appSettings).get();
      return {for (final r in rows) r.settingKey: r.settingValue};
    }

    test('режим сохраняется', () async {
      await container
          .read(settingsControllerProvider)
          .setThemeMode(AppThemeMode.system);
      expect((await read())[themeModeKey], 'system');
    });

    test('светлая палитра переключает тёмный режим на светлый', () async {
      final controller = container.read(settingsControllerProvider);
      await controller.setThemePalette(
        AppPalette.cleanLight,
        currentMode: AppThemeMode.dark,
      );
      var settings = await read();
      expect(settings[themePaletteKey], 'clean_light');
      expect(settings[themeModeKey], 'light');

      await controller.setThemePalette(
        AppPalette.forestEmerald,
        currentMode: AppThemeMode.light,
      );
      settings = await read();
      expect(settings[themePaletteKey], 'forest_emerald');
      expect(settings[themeModeKey], 'dark');
    });

    test('режим «Как в системе» палитра не меняет', () async {
      await container
          .read(settingsControllerProvider)
          .setThemePalette(
            AppPalette.cleanLight,
            currentMode: AppThemeMode.system,
          );
      final settings = await read();
      expect(settings[themePaletteKey], 'clean_light');
      expect(settings.containsKey(themeModeKey), isFalse);
    });
  });

  group('карточка «Внешний вид»', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    /// Убирает дерево, чтобы потоки drift закрылись до конца теста.
    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pumpAndSettle();
      }
    }

    /// Приложение с темой из настроек, как в `main.dart`.
    Widget themedApp(Widget home) => ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: Consumer(
        builder: (context, ref, _) {
          final palette = ref.watch(themePaletteProvider);
          return MaterialApp(
            theme: AppTheme.build(palette, Brightness.light),
            darkTheme: AppTheme.build(palette, Brightness.dark),
            themeMode: ref.watch(themeModeProvider).themeMode,
            home: Scaffold(body: SingleChildScrollView(child: home)),
          );
        },
      ),
    );

    testWidgets('по умолчанию выбраны «Тёмная» и Cyber Obsidian', (
      tester,
    ) async {
      await tester.pumpWidget(themedApp(const AppearanceSettingsCard()));
      await settle(tester);

      final selector = tester.widget<SegmentedButton<AppThemeMode>>(
        find.byKey(const ValueKey('theme_mode_selector')),
      );
      expect(selector.selected, {AppThemeMode.dark});
      expect(find.text('Цветовая схема: Cyber Obsidian'), findsOneWidget);
      for (final p in AppPalette.values) {
        expect(find.byKey(ValueKey('theme_palette_${p.key}')), findsOneWidget);
      }
      final context = tester.element(find.byType(AppearanceSettingsCard));
      expect(Theme.of(context).brightness, Brightness.dark);
      await unmount(tester);
    });

    testWidgets('выбор палитры и режима применяется сразу', (tester) async {
      await tester.pumpWidget(themedApp(const AppearanceSettingsCard()));
      await settle(tester);

      await tester.tap(
        find.byKey(const ValueKey('theme_palette_midnight_blue')),
      );
      await settle(tester);
      var context = tester.element(find.byType(AppearanceSettingsCard));
      expect(
        Theme.of(context).colorScheme.primary,
        AppPalette.midnightBlue.primary,
      );
      expect(find.text('Цветовая схема: Midnight Blue'), findsOneWidget);

      await tester.tap(find.text('Светлая'));
      await settle(tester);
      context = tester.element(find.byType(AppearanceSettingsCard));
      expect(Theme.of(context).brightness, Brightness.light);
      expect(
        Theme.of(context).scaffoldBackgroundColor,
        AppPalette.midnightBlue.light.background,
      );
      await unmount(tester);
    });

    testWidgets('экран настроек строится в светлой теме', (tester) async {
      await tester.runAsync(
        () => db
            .into(db.appSettings)
            .insert(
              AppSettingsCompanion.insert(
                settingKey: themePaletteKey,
                settingValue: AppPalette.cleanLight.key,
              ),
            ),
      );
      await tester.runAsync(
        () => db
            .into(db.appSettings)
            .insert(
              AppSettingsCompanion.insert(
                settingKey: themeModeKey,
                settingValue: AppThemeMode.light.key,
              ),
            ),
      );
      tester.view.physicalSize = const Size(1400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              theme: AppTheme.build(
                ref.watch(themePaletteProvider),
                Brightness.light,
              ),
              themeMode: ref.watch(themeModeProvider).themeMode,
              home: const SettingsScreen(),
            ),
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(SettingsScreen));
      expect(Theme.of(context).brightness, Brightness.light);
      final title = tester.widget<Text>(find.text('Настройки'));
      expect(title.style?.color, AppPalette.cleanLight.light.onSurface);
      await unmount(tester);
    });
  });
}
