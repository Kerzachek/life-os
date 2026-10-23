import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/responsive.dart';
import '../../../notes/presentation/providers/notes_provider.dart';

/// Быстрая заметка из меню быстрых действий: заголовок, текст и опция
/// «Сделать чек-листом» — тогда каждая непустая строка текста становится
/// пунктом. Сохраняется сразу в раздел «Заметки».
class QuickNoteSheet extends ConsumerStatefulWidget {
  const QuickNoteSheet({super.key});

  @override
  ConsumerState<QuickNoteSheet> createState() => _QuickNoteSheetState();
}

class _QuickNoteSheetState extends ConsumerState<QuickNoteSheet> {
  final _title = TextEditingController();
  final _text = TextEditingController();
  bool _asChecklist = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = ref.read(notesControllerProvider);
    final lines = [
      for (final line in _text.text.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    final note = controller.draft().copyWith(
      title: _title.text.trim(),
      content: _asChecklist ? '' : _text.text.trim(),
      checklist: _asChecklist
          ? [for (final line in lines) controller.newChecklistItem(line)]
          : const [],
    );
    if (note.isEmpty) {
      setState(() => _error = 'Введите заголовок или текст');
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    await controller.save(note);
    navigator.pop();
    messenger?.showSnackBar(
      const SnackBar(content: Text('Заметка сохранена')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveFormDialog(
      title: const Text('Быстрая заметка'),
      content: SizedBox(
        width: formDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('quick_note_title'),
              controller: _title,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Заголовок',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('quick_note_text'),
              controller: _text,
              minLines: 3,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: _asChecklist ? 'Пункты — по одному в строке' : 'Текст',
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              key: const ValueKey('quick_note_checklist'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Сделать чек-листом'),
              value: _asChecklist,
              onChanged: (v) => setState(() => _asChecklist = v),
            ),
            if (_error != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const ValueKey('quick_note_submit'),
          onPressed: _submit,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
