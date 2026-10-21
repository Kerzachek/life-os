import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/responsive.dart';
import '../../../finance/presentation/widgets/safe_to_spend_card.dart';
import '../../../settings/domain/app_module.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../widgets/dashboard_empty_state.dart';
import '../widgets/habits_overview_card.dart';
import '../widgets/overview_header.dart';
import '../widgets/quick_actions_card.dart';
import '../widgets/routine_overview_card.dart';
import '../widgets/today_tasks_overview_card.dart';
import '../widgets/weekly_progress_card.dart';

/// Дашборд. Состав карточек зависит от включённых разделов: карточки
/// отключённых разделов не строятся, а сетка перестраивается без пустот.
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key, this.onOpenSettings});

  /// Переход в Настройки (кнопка пустого состояния).
  final VoidCallback? onOpenSettings;

  static const double _gap = 16;

  /// Минимальная ширина, при которой карточки раскладываются в две колонки.
  static const double twoColumnBreakpoint = 900;

  static List<Widget> _spaced(List<Widget> cards) => [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: _gap),
          cards[i],
        ],
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(enabledModulesProvider);
    final tasksOn = enabled.contains(AppModule.tasks);
    final habitsOn = enabled.contains(AppModule.habits);
    final financeOn = enabled.contains(AppModule.finance);
    final routineOn = enabled.contains(AppModule.routine);

    // Основная колонка — списки дел; боковая — действия и сводки.
    final primary = <Widget>[
      if (routineOn) const RoutineOverviewCard(),
      if (tasksOn) const TodayTasksOverviewCard(),
      if (habitsOn) const HabitsOverviewCard(),
    ];
    final secondary = <Widget>[
      if (enabled.isNotEmpty) const QuickActionsCard(),
      if (financeOn) const SafeToSpendCard(compact: true),
      if (WeeklyProgressCard.isVisibleFor(enabled)) const WeeklyProgressCard(),
    ];

    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isMobileLayout(context) ? 12 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OverviewHeader(),
            const SizedBox(height: _gap),
            if (enabled.isEmpty)
              DashboardEmptyState(onOpenSettings: onOpenSettings)
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth > twoColumnBreakpoint &&
                      primary.isNotEmpty &&
                      secondary.isNotEmpty;

                  if (!twoColumns) {
                    // Узкий экран или одна из колонок пуста — одна колонка
                    // на всю ширину. Быстрые действия — первыми.
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _spaced([
                        ...secondary.take(1),
                        ...primary,
                        ...secondary.skip(1),
                      ]),
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Column(children: _spaced(primary)),
                      ),
                      const SizedBox(width: _gap),
                      Expanded(
                        flex: 4,
                        child: Column(children: _spaced(secondary)),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
