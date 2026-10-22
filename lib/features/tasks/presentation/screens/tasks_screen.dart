import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/responsive.dart';
import '../../domain/task_category.dart';
import '../providers/tasks_provider.dart';
import '../widgets/add_task_dialog.dart';
import '../widgets/task_item_widget.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tasksAsync = ref.watch(filteredTasksProvider);

    final currentCategoryFilter = ref.watch(taskCategoryFilterProvider);
    final currentStatusFilter = ref.watch(taskStatusFilterProvider);
    final compactLandscape = isCompactLandscape(context);

    final search = TextField(
      decoration: InputDecoration(
        hintText: 'Поиск задач...',
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      onChanged: (value) {
        ref.read(taskSearchQueryProvider.notifier).setQuery(value);
      },
    );

    final categoryChips = <Widget>[
      FilterChip(
        label: const Text('Все'),
        selected: currentCategoryFilter == null,
        onSelected: (_) =>
            ref.read(taskCategoryFilterProvider.notifier).setFilter(null),
      ),
      ...TaskCategory.values.map((category) {
        final isSelected = currentCategoryFilter == category;
        // Только иконка (название — в подсказке), чтобы все
        // фильтры помещались в панель.
        return Tooltip(
          message: category.label,
          child: FilterChip(
            key: ValueKey('task-category-filter-${category.id}'),
            label: Icon(category.icon, size: 18, color: category.color),
            showCheckmark: false,
            labelPadding: const EdgeInsets.symmetric(horizontal: 2),
            selected: isSelected,
            selectedColor: category.color.withValues(alpha: 0.25),
            side: BorderSide(
              color: isSelected
                  ? category.color
                  : theme.colorScheme.outlineVariant,
            ),
            onSelected: (_) {
              ref
                  .read(taskCategoryFilterProvider.notifier)
                  .setFilter(isSelected ? null : category);
            },
          ),
        );
      }),
    ];

    final statusChips = <Widget>[
      for (final filter in TaskStatusFilter.values)
        FilterChip(
          label: Text(filter.label),
          selected: currentStatusFilter == filter,
          onSelected: (_) {
            ref.read(taskStatusFilterProvider.notifier).setFilter(filter);
          },
        ),
    ];

    final list = tasksAsync.when(
      data: (tasks) {
        if (tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.task_outlined,
                  size: 64,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  'Задач пока нет',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Нажмите "+", чтобы добавить новую задачу',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            final task = tasks[index];
            return TaskItemWidget(key: ValueKey(task.id), task: task);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Ошибка загрузки задач: $err')),
    );

    final Widget body;
    if (compactLandscape) {
      // Телефон горизонтально: поиск и фильтры слева, список справа —
      // иначе панели фильтров съедают почти всю высоту экрана.
      body = LandscapeSplit(
        summaryFlex: 2,
        listFlex: 3,
        summary: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            search,
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: categoryChips),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: statusChips),
          ],
        ),
        list: list,
      );
    } else {
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: search,
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    for (final chip in categoryChips)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: chip,
                      ),
                    const SizedBox(width: 8),
                    Container(
                      height: 24,
                      width: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    const SizedBox(width: 8),
                    for (final chip in statusChips)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: chip,
                      ),
                  ],
                ),
              ),
              const Divider(height: 16),
              Expanded(child: list),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showFormSheet<void>(
            context: context,
            builder: (context) => const AddTaskDialog(),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Новая задача'),
        isExtended: !compactLandscape,
      ),
    );
  }
}
