import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/responsive.dart';
import '../../domain/note.dart';
import '../providers/notes_provider.dart';
import '../widgets/note_card.dart';
import '../widgets/note_editor.dart';

/// Экран «Заметки»: закреплённые сверху, остальные — сеткой ниже.
class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  /// Ширина области, начиная с которой заметки идут в две колонки.
  static const double twoColumnMinWidth = 560;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final notesAsync = ref.watch(notesStreamProvider);
    final mobile = isMobileLayout(context);

    final header = <Widget>[
      Row(
        children: [
          Icon(Icons.sticky_note_2_outlined, color: colorScheme.primary),
          const SizedBox(width: 10),
          Text(
            'Заметки',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        'Мысли, списки покупок и чек-листы. Важное можно закрепить сверху.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 20),
    ];

    final body = notesAsync.when(
      data: (notes) {
        if (notes.isEmpty) return const _EmptyNotes();
        final pinned = notes.where((n) => n.isPinned).toList();
        final others = notes.where((n) => !n.isPinned).toList();
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= twoColumnMinWidth ? 2 : 1;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (pinned.isNotEmpty) ...[
                  const _SectionLabel('Закреплённые'),
                  _MasonryGrid(columns: columns, notes: pinned),
                  const SizedBox(height: 20),
                  if (others.isNotEmpty) const _SectionLabel('Остальные'),
                ],
                _MasonryGrid(columns: columns, notes: others),
              ],
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Text('Ошибка: $err'),
    );

    return Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxEditorWidth),
          child: ListView(
            // Снизу — место под плавающую кнопку.
            padding: EdgeInsets.fromLTRB(
              mobile ? 12 : 20,
              mobile ? 12 : 20,
              mobile ? 12 : 20,
              88,
            ),
            children: [...header, body],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openNoteEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Новая заметка'),
        isExtended: !isCompactLandscape(context),
      ),
    );
  }
}

/// Сетка разной высоты: карточки раскладываются по колонкам по очереди,
/// каждая колонка — своей высоты, без пустот под короткими заметками.
class _MasonryGrid extends StatelessWidget {
  const _MasonryGrid({required this.columns, required this.notes});

  final int columns;
  final List<Note> notes;

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    Widget column(int index) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = index; i < notes.length; i += columns)
          Padding(
            padding: const EdgeInsets.only(bottom: _gap),
            child: NoteCard(key: ValueKey(notes[i].id), note: notes[i]),
          ),
      ],
    );

    if (columns == 1) return column(0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var c = 0; c < columns; c++) ...[
          if (c > 0) const SizedBox(width: _gap),
          Expanded(child: column(c)),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 1.2,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.sticky_note_2_outlined,
            size: 48,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Заметок пока нет',
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'Нажмите «Новая заметка», чтобы записать мысль или чек-лист.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
