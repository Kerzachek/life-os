import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/services/system_overlay_service.dart';
import 'package:home_organizer/features/quick_actions/presentation/providers/system_overlay_provider.dart';
import 'package:home_organizer/features/quick_actions/presentation/widgets/quick_note_sheet.dart';
import 'package:home_organizer/features/settings/data/repositories/settings_repository.dart';
import 'package:home_organizer/features/settings/domain/app_module.dart';
import 'package:home_organizer/features/settings/presentation/providers/settings_provider.dart';
import 'package:home_organizer/main.dart';

const _channel = SystemOverlayService.defaultChannel;

/// Вызовы Dart → платформа, записанные подменённым каналом.
final List<MethodCall> _calls = [];

void _mockPlatform({bool canDraw = true}) {
  _calls.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
    _calls.add(call);
    switch (call.method) {
      case 'canDrawOverlays':
        return canDraw;
      case 'show':
        return canDraw;
    }
    return null;
  });
}

/// Событие платформа → Dart (как от нативного оверлея).
Future<void> _fromPlatform(String method, [Object? arguments]) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    _channel.name,
    _channel.codec.encodeMethodCall(MethodCall(method, arguments)),
    (_) {},
  );
}

Iterable<String> get _methods => _calls.map((c) => c.method);

Future<void> _withApp(
  WidgetTester tester,
  Future<void> Function(AppDatabase db) body, {
  Future<void> Function(AppDatabase db)? seed,
}) async {
  tester.view.physicalSize = const Size(1600, 1300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  if (seed != null) await tester.runAsync(() => seed(db));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        systemOverlaySupportedProvider.overrideWithValue(true),
      ],
      child: const HomeOrganizerApp(),
    ),
  );
  await tester.pumpAndSettle();
  try {
    await body(db);
  } finally {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await db.close();
  }
}

Future<void> _enable(AppDatabase db) =>
    SettingsRepository(db).setValue(systemOverlayEnabledKey, 'true');

void main() {
  setUp(_mockPlatform);
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));

  test('по умолчанию оверлей выключен и прячется при открытом окне', () {
    expect(resolveSystemOverlayEnabled({}), isFalse);
    expect(resolveSystemOverlayHideWhenAppVisible({}), isTrue);
    expect(
      resolveSystemOverlayEnabled({systemOverlayEnabledKey: 'true'}),
      isTrue,
    );
  });

  testWidgets('выключенный оверлей не создаётся', (tester) async {
    await _withApp(tester, (db) async {
      expect(_methods, isNot(contains('show')));
    });
  });

  testWidgets('включённый оверлей показывается с действиями разделов',
      (tester) async {
    await _withApp(
      tester,
      seed: (db) async {
        await _enable(db);
        await SettingsRepository(db)
            .setValue(AppModule.finance.storageKey, 'false');
      },
      (db) async {
        final show = _calls.lastWhere((c) => c.method == 'show');
        final args = show.arguments as Map;
        final ids = [for (final item in args['items'] as List) item['id']];
        expect(ids, ['note', 'check_in']);
        expect(args['hideWhenAppVisible'], isTrue);
      },
    );
  });

  testWidgets('тумблер в Настройках сразу создаёт и уничтожает оверлей',
      (tester) async {
    await _withApp(tester, (db) async {
      await tester.tap(find.text('Настройки'));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('system_overlay_switch'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(_methods, contains('show'));
      // Разрешение есть — системные настройки не открываются.
      expect(_methods, isNot(contains('requestPermission')));

      _calls.clear();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(_methods, contains('hide'));
      expect(_methods, isNot(contains('show')));
    });
  });

  testWidgets('чекбокс скрытия при открытом окне передаётся оверлею',
      (tester) async {
    await _withApp(tester, seed: _enable, (db) async {
      await tester.tap(find.text('Настройки'));
      await tester.pumpAndSettle();
      final checkbox =
          find.byKey(const ValueKey('system_overlay_hide_checkbox'));
      await tester.ensureVisible(checkbox);
      await tester.pumpAndSettle();

      _calls.clear();
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      final show = _calls.lastWhere((c) => c.method == 'show');
      expect((show.arguments as Map)['hideWhenAppVisible'], isFalse);
    });
  });

  testWidgets('«Скрыть» прячет оверлей до повторного включения',
      (tester) async {
    await _withApp(tester, seed: _enable, (db) async {
      _calls.clear();
      await _fromPlatform('onDismissed');
      await tester.pumpAndSettle();
      // Окно уже убрано нативной стороной — повторно не показываем.
      expect(_methods, isNot(contains('show')));

      await tester.tap(find.text('Настройки'));
      await tester.pumpAndSettle();
      final restore =
          find.byKey(const ValueKey('system_overlay_restore_button'));
      await tester.ensureVisible(restore);
      await tester.pumpAndSettle();
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(_methods, contains('show'));
    });
  });

  testWidgets('действие из оверлея открывает форму в окне LifeOS',
      (tester) async {
    await _withApp(tester, seed: _enable, (db) async {
      await _fromPlatform('onAction', {'id': 'note'});
      await tester.pumpAndSettle();
      expect(find.byType(QuickNoteSheet), findsOneWidget);
    });
  });

  testWidgets('действие отключённого раздела игнорируется', (tester) async {
    await _withApp(
      tester,
      seed: (db) async {
        await _enable(db);
        await SettingsRepository(db)
            .setValue(AppModule.notes.storageKey, 'false');
      },
      (db) async {
        await _fromPlatform('onAction', {'id': 'note'});
        await tester.pumpAndSettle();
        expect(find.byType(QuickNoteSheet), findsNothing);
      },
    );
  });

  testWidgets('перетаскивание оверлея сохраняет положение', (tester) async {
    await _withApp(tester, seed: _enable, (db) async {
      await _fromPlatform('onMoved', {'isLeft': true, 'fraction': 0.25});
      await tester.pumpAndSettle();
      final raw = await tester.runAsync(
          () async => (await SettingsRepository(db).readAll())[
              systemOverlayPositionKey]);
      expect(
        QuickButtonPosition.decode(raw),
        const QuickButtonPosition(isLeft: true, verticalFraction: 0.25),
      );
    });
  });

  testWidgets('без разрешения включение ведёт в системные настройки',
      (tester) async {
    _mockPlatform(canDraw: false);
    await _withApp(tester, (db) async {
      await tester.tap(find.text('Настройки'));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('system_overlay_switch'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(_methods, contains('requestPermission'));
    });
  });
}
