import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../finance/presentation/widgets/confirm_dialog.dart';
import '../../domain/note.dart';
import '../../domain/note_color_tag.dart';
import '../providers/notes_provider.dart';

/// Открывает редактор заметки. Без [note] — новая заметка.
///
/// На телефоне — во весь экран (поля поднимаются над клавиатурой), на
/// планшете и десктопе — по центру окна шириной до [maxEditorWidth].
Future<void> openNoteEditor(BuildContext context, {Note? note}) {
  if (isPhone(context)) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NoteEditor(note: note),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: maxEditorWidth,
          maxHeight: 760,
        ),
        child: SizedBox.expand(child: NoteEditor(note: note)),
      ),
    ),
  );
}

/// Редактор заметки: заголовок, текст и чек-лист. Изменения сохраняются
/// автоматически (с задержкой и при закрытии), пустая новая заметка — нет.
class NoteEditor extends ConsumerStatefulWidget {
  const NoteEditor({super.key, this.note});

  final Note? note;

  @override
  ConsumerState<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<NoteEditor> {
  static const _saveDelay = Duration(milliseconds: 600);

  late final NotesController _controller;
  late Note _note;
  late final TextEditingController _title;
  late final TextEditingController _content;
  final _itemText = <String, TextEditingController>{};
  final _itemFocus = <String, FocusNode>{};

  /// Последнее записанное в БД состояние (`null` — заметки в БД ещё нет).
  Note? _saved;
  bool _deleted = false;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(notesControllerProvider);
    _note = widget.note ?? _controller.draft();
    _saved = widget.note;
    _title = TextEditingController(text: _note.title)..addListener(_changed);
    _content = TextEditingController(text: _note.content)
      ..addListener(_changed);
    for (final item in _note.checklist) {
      _attachItem(item);
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _save();
    _title.dispose();
    _content.dispose();
    for (final c in _itemText.values) {
      c.dispose();
    }
    for (final f in _itemFocus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _attachItem(NoteChecklistItem item) {
    _itemText[item.id] = TextEditingController(text: item.text)
      ..addListener(_changed);
    _itemFocus[item.id] = FocusNode();
  }

  /// Текущее состояние формы.
  Note get _current => _note.copyWith(
    title: _title.text,
    content: _content.text,
    checklist: [
      for (final item in _note.checklist)
        item.copyWith(text: _itemText[item.id]!.text),
    ],
  );

  void _changed() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _save);
  }

  void _save() {
    if (_deleted) return;
    final note = _current;
    final saved = _saved;
    if (saved == null && note.isEmpty) return;
    if (saved != null && note.sameContentAs(saved)) return;
    final stamped = note.copyWith(updatedAt: DateTime.now().toUtc());
    _saved = stamped;
    _controller.save(stamped);
  }

  void _update(Note note) {
    setState(() => _note = note);
    _changed();
  }

  void _addItem({int? at}) {
    final item = _controller.newChecklistItem();
    _attachItem(item);
    final list = [..._note.checklist];
    list.insert(at ?? list.length, item);
    _update(_note.copyWith(checklist: list));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _itemFocus[item.id]?.requestFocus();
    });
  }

  void _toggleItem(NoteChecklistItem item) {
    _update(
      _note.copyWith(
        checklist: [
          for (final i in _note.checklist)
            i.id == item.id ? i.copyWith(isCompleted: !i.isCompleted) : i,
        ],
      ),
    );
  }

  void _removeItem(NoteChecklistItem item) {
    _update(
      _note.copyWith(
        checklist: [
          for (final i in _note.checklist)
            if (i.id != item.id) i,
        ],
      ),
    );
    // Контроллер освобождается после кадра: поле ещё может быть в дереве.
    final text = _itemText.remove(item.id);
    final focus = _itemFocus.remove(item.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      text?.dispose();
      focus?.dispose();
    });
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    if (_saved != null) {
      final confirmed = await confirmAction(
        context,
        title: 'Удалить заметку?',
        message: 'Заметка будет удалена на всех устройствах.',
      );
      if (!confirmed) return;
      await _controller.delete(_note.id);
    }
    _deleted = true;
    _saveTimer?.cancel();
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tag = NoteColorTag.fromKey(_note.colorTag);
    final phone = isPhone(context);
    final base = phone ? AppTheme.darkBackground : AppTheme.darkSurface;
    final background = tag == null
        ? base
        : Color.alphaBlend(tag.color.withValues(alpha: 0.08), base);
    final items = _note.checklist;
    final completed = _note.completedCount;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        leading: IconButton(
          tooltip: 'Закрыть',
          icon: Icon(phone ? Icons.arrow_back : Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            key: const ValueKey('note_pin'),
            tooltip: _note.isPinned ? 'Открепить' : 'Закрепить',
            isSelected: _note.isPinned,
            icon: const Icon(Icons.push_pin_outlined),
            selectedIcon: Icon(Icons.push_pin, color: colorScheme.primary),
            onPressed: () => _update(_note.copyWith(isPinned: !_note.isPinned)),
          ),
          PopupMenuButton<String>(
            tooltip: 'Цвет',
            icon: Icon(Icons.palette_outlined, color: tag?.color),
            // null из меню означает «закрыли без выбора», поэтому «без цвета» — "".
            onSelected: (key) => _update(
              _note.copyWith(colorTag: () => key.isEmpty ? null : key),
            ),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: '',
                child: _ColorMenuRow(color: null, label: 'Без цвета'),
              ),
              for (final t in NoteColorTag.values)
                PopupMenuItem(
                  value: t.key,
                  child: _ColorMenuRow(color: t.color, label: t.label),
                ),
            ],
          ),
          IconButton(
            tooltip: 'Удалить',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxEditorWidth),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                phone ? 16 : 24,
                4,
                phone ? 16 : 24,
                24,
              ),
              children: [
                TextField(
                  key: const ValueKey('note_title'),
                  controller: _title,
                  autofocus: widget.note == null,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.next,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  decoration: InputDecoration.collapsed(
                    hintText: 'Заголовок',
                    hintStyle: theme.textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('note_content'),
                  controller: _content,
                  minLines: 3,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                  decoration: InputDecoration.collapsed(
                    hintText: 'Текст заметки',
                    hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 20),
                if (items.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.checklist_rounded,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Чек-лист · $completed/${items.length} выполнено',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (var i = 0; i < items.length; i++)
                    _ChecklistRow(
                      key: ValueKey(items[i].id),
                      item: items[i],
                      controller: _itemText[items[i].id]!,
                      focusNode: _itemFocus[items[i].id]!,
                      onToggle: () => _toggleItem(items[i]),
                      onRemove: () => _removeItem(items[i]),
                      onSubmitted: () => _addItem(at: i + 1),
                    ),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('note_add_item'),
                    onPressed: _addItem,
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить пункт чек-листа'),
                  ),
                ),
                if (_saved != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Изменено ${DateFormat('dd.MM.yyyy HH:mm').format(_saved!.updatedAt.toLocal())}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Строка чек-листа: отметка, текст пункта (с переносом) и удаление.
class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    super.key,
    required this.item,
    required this.controller,
    required this.focusNode,
    required this.onToggle,
    required this.onRemove,
    required this.onSubmitted,
  });

  final NoteChecklistItem item;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  /// Enter в пункте — новый пункт следом.
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(value: item.isCompleted, onChanged: (_) => onToggle()),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 9),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.next,
              onEditingComplete: () {},
              onSubmitted: (_) => onSubmitted(),
              style: TextStyle(
                fontSize: 15,
                decoration: item.isCompleted
                    ? TextDecoration.lineThrough
                    : null,
                color: item.isCompleted
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.onSurface,
              ),
              decoration: InputDecoration.collapsed(
                hintText: 'Пункт',
                hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Удалить пункт',
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.close,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          onPressed: onRemove,
        ),
      ],
    );
  }
}

class _ColorMenuRow extends StatelessWidget {
  const _ColorMenuRow({required this.color, required this.label});

  final Color? color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: color ?? outline, width: 2),
          ),
        ),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}
