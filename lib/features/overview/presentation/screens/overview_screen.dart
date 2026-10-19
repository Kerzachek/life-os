import 'package:flutter/material.dart';

import '../widgets/habits_overview_card.dart';
import '../widgets/overview_header.dart';
import '../widgets/quick_actions_card.dart';
import '../widgets/today_tasks_overview_card.dart';
import '../widgets/weekly_progress_card.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OverviewHeader(),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 900) {
                  return const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Column(
                          children: [
                            TodayTasksOverviewCard(),
                            SizedBox(height: 16),
                            HabitsOverviewCard(),
                          ],
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        flex: 4,
                        child: Column(
                          children: [
                            QuickActionsCard(),
                            SizedBox(height: 16),
                            WeeklyProgressCard(),
                          ],
                        ),
                      ),
                    ],
                  );
                } else {
                  return const Column(
                    children: [
                      QuickActionsCard(),
                      SizedBox(height: 16),
                      TodayTasksOverviewCard(),
                      SizedBox(height: 16),
                      HabitsOverviewCard(),
                      SizedBox(height: 16),
                      WeeklyProgressCard(),
                    ],
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
