import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/habits_provider.dart';
import '../widgets/add_challenge_dialog.dart';
import '../widgets/add_habit_dialog.dart';
import '../widgets/challenge_card.dart';
import '../widgets/habit_card.dart';
import '../widgets/habits_summary_card.dart';

class HabitsScreen extends ConsumerStatefulWidget {
  const HabitsScreen({super.key});

  @override
  ConsumerState<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends ConsumerState<HabitsScreen> {
  int _selectedTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment<int>(
                      value: 0,
                      label: Text('Мои привычки'),
                      icon: Icon(Icons.check_circle_outline),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      label: Text('Челленджи'),
                      icon: Icon(Icons.emoji_events_outlined),
                    ),
                  ],
                  selected: {_selectedTabIndex},
                  onSelectionChanged: (newVal) {
                    setState(() => _selectedTabIndex = newVal.first);
                  },
                ),
              ),
              Expanded(
                child: _selectedTabIndex == 0
                    ? const _HabitsListSection()
                    : const _ChallengesListSection(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => _selectedTabIndex == 0
                ? const AddHabitDialog()
                : const AddChallengeDialog(),
          );
        },
        icon: const Icon(Icons.add),
        label: Text(_selectedTabIndex == 0 ? 'Новая привычка' : 'Новый челлендж'),
      ),
    );
  }
}

class _HabitsListSection extends ConsumerWidget {
  const _HabitsListSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsWithStatusProvider);

    return Column(
      children: [
        habitsAsync.when(
          data: (habits) => HabitsSummaryCard(habits: habits),
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        ),
        Expanded(
          child: habitsAsync.when(
            data: (habits) {
              if (habits.isEmpty) {
                return _EmptyStateView(
                  icon: Icons.local_fire_department_outlined,
                  title: 'Привычек пока нет',
                  subtitle: 'Нажмите "+", чтобы создать новую привычку',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: habits.length,
                itemBuilder: (context, index) {
                  final item = habits[index];
                  return HabitCard(key: ValueKey(item.habit.id), item: item);
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Ошибка: $err')),
          ),
        ),
      ],
    );
  }
}

class _ChallengesListSection extends ConsumerWidget {
  const _ChallengesListSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challengesAsync = ref.watch(activeChallengesStreamProvider);

    return challengesAsync.when(
      data: (challenges) {
        if (challenges.isEmpty) {
          return const _EmptyStateView(
            icon: Icons.emoji_events_outlined,
            title: 'Активных челленджей нет',
            subtitle: 'Нажмите "+", чтобы запустить челлендж',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: challenges.length,
          itemBuilder: (context, index) {
            final challenge = challenges[index];
            return ChallengeCard(key: ValueKey(challenge.id), challenge: challenge);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Ошибка: $err')),
    );
  }
}

class _EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyStateView({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 8),
          Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }
}
