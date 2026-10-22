import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/widgets/app_sidebar.dart';
import 'package:home_organizer/features/routine/presentation/widgets/routine_item_dialog.dart';
import 'package:home_organizer/main.dart';

const _phonePortrait = Size(360, 780);
const _phoneLandscape = Size(780, 360);

Future<void> _withApp(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final testDb = AppDatabase.forTesting(NativeDatabase.memory());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(testDb)],
      child: const HomeOrganizerApp(),
    ),
  );
  await tester.pumpAndSettle();
  try {
    await body();
  } finally {
    // Сначала размонтировать приложение (отписка от стримов drift),
    // затем закрыть базу — иначе остаются таймеры и тест зависает.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await testDb.close();
  }
}

/// Переход в раздел через нижнюю панель или боковую ленту.
Future<void> _openSection(WidgetTester tester, IconData icon) async {
  final nav = find.byWidgetPredicate(
    (w) => w is NavigationBar || w is NavigationRail,
  );
  await tester.tap(find.descendant(of: nav, matching: find.byIcon(icon)));
  await tester.pumpAndSettle();
}

/// Ни один Row/Column не вылезает за свои границы. Проверяет и экраны,
/// скрытые в IndexedStack: о переполнении Flutter сообщает только при
/// отрисовке, а скрытые экраны не рисуются.
void _expectNoFlexOverflow(WidgetTester tester) {
  final overflows = <String>[];
  void visit(RenderObject node) {
    if (node is RenderFlex && node.hasSize) {
      final horizontal = node.direction == Axis.horizontal;
      var used = 0.0;
      node.visitChildren((child) {
        final box = child as RenderBox;
        if (box.hasSize) used += horizontal ? box.size.width : box.size.height;
      });
      final available = horizontal ? node.size.width : node.size.height;
      if (used > available + 0.5) {
        final creator = node.debugCreator as DebugCreator?;
        overflows.add('${(used - available).toStringAsFixed(1)}px: '
            '${creator?.element.debugGetCreatorChain(12)}');
      }
    }
    node.visitChildren(visit);
  }

  tester.binding.renderViews.forEach(visit);
  expect(overflows, isEmpty);
}

void main() {
  for (final size in const [
    _phonePortrait,
    _phoneLandscape,
    Size(412, 915),
    Size(915, 412),
  ]) {
    testWidgets('экраны без переполнений на ${size.width}×${size.height}',
        (WidgetTester tester) async {
      await _withApp(tester, size, () async {
        _expectNoFlexOverflow(tester);
      });
    });
  }

  testWidgets('телефон вертикально: панель без подписей, кнопка под текстом',
      (WidgetTester tester) async {
    await _withApp(tester, _phonePortrait, () async {
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.labelBehavior, NavigationDestinationLabelBehavior.alwaysHide);

      await _openSection(tester, Icons.wb_sunny_outlined);
      final button = tester.getRect(find.text('Добавить действие'));
      final title = tester.getRect(find.text('Выполнено 0 из 0'));
      expect(button.top, greaterThan(title.bottom));
    });
  });

  testWidgets('на телефоне форма открывается шторкой снизу',
      (WidgetTester tester) async {
    await _withApp(tester, _phonePortrait, () async {
      await _openSection(tester, Icons.wb_sunny_outlined);
      await tester.tap(find.text('Добавить действие'));
      await tester.pumpAndSettle();

      expect(find.byType(RoutineItemDialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  testWidgets('финансы на узком экране: сводка в одну колонку',
      (WidgetTester tester) async {
    await _withApp(tester, _phonePortrait, () async {
      await _openSection(tester, Icons.account_balance_wallet_rounded);
      final balance = tester.getRect(find.text('Общий баланс'));
      final debt = tester.getRect(find.text('Долги / Кредиты'));
      expect(debt.top, greaterThan(balance.bottom));
    });
  });

  testWidgets('телефон горизонтально: узкая лента слева вместо нижней панели',
      (WidgetTester tester) async {
    await _withApp(tester, _phoneLandscape, () async {
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(AppSidebar), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);

      await _openSection(tester, Icons.task_alt_rounded);
      expect(find.text('Поиск задач...'), findsOneWidget);
    });
  });

  testWidgets('планшет и десктоп сохраняют боковое меню и диалоги',
      (WidgetTester tester) async {
    await _withApp(tester, const Size(1280, 800), () async {
      expect(find.byType(AppSidebar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);

      await tester.tap(find.descendant(
        of: find.byType(AppSidebar),
        matching: find.text('Рутина'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить действие'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });
}
