import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/note.dart';
import '../../domain/note_color_tag.dart';
import '../providers/notes_provider.dart';
import 'note_editor.dart';

/// Карточка заметки в списке: заголовок, превью текста и прогресс чек-листа
/// с первыми пунктами (их можно отмечать прямо здесь).
class NoteCard extends ConsumerWidget {
  const NoteCard({super.key, required this.note});

  final Note note;

  /// Сколько пунктов чек-листа показывать в превью.
  static const int previewItems = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tag = NoteColorTag.fromKey(note.colorTag);
    final cardColor = theme.cardTheme.color ?? colorScheme.surface;
    final items = note.checklist;
    final completed = note.completedCount;
    final title = note.title.trim();
    final content = note.content.trim();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: tag == null
          ? null
          : Color.alphaBlend(tag.color.withValues(alpha: 0.10), cardColor),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: tag?.color.withValues(alpha: 0.55) ?? colorScheme.outline,
        ),
      ),
      child: InkWell(
        onTap: () => openNoteEditor(context, note: note),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        title.isEmpty ? 'Без названия' : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: title.isEmpty
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: note.isPinned ? 'Открепить' : 'Закрепить',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 18,
                      color: note.isPinned
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () =>
                        ref.read(notesControllerProvider).togglePinned(note),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (content.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        content,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (items.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: completed / items.length,
                                minHeight: 4,
                                backgroundColor: colorScheme.outline,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '$completed/${items.length} выполнено',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (final item in items.take(previewItems))
                        _ChecklistPreviewRow(
                          item: item,
                          onToggle: () => ref
                              .read(notesControllerProvider)
                              .toggleChecklistItem(note, item.id),
                        ),
                      if (items.length > previewItems)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, left: 2),
                          child: Text(
                            '+ ещё ${items.length - previewItems}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChecklistPreviewRow extends StatelessWidget {
  const _ChecklistPreviewRow({required this.item, required this.onToggle});

  final NoteChecklistItem item;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        child: Row(
          children: [
            Icon(
              item.isCompleted
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 18,
              color: item.isCompleted
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.text.isEmpty ? '—' : item.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  decoration: item.isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                  color: item.isCompleted
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
