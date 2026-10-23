import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/notes_repository.dart';
import '../../domain/note.dart';

final notesStreamProvider = StreamProvider<List<Note>>((ref) {
  return ref.watch(notesRepositoryProvider).watchNotes();
});

final notesControllerProvider = Provider<NotesController>((ref) {
  return NotesController(ref.watch(notesRepositoryProvider));
});

class NotesController {
  final NotesRepository _repository;
  final _uuid = const Uuid();

  NotesController(this._repository);

  /// Новая заметка в памяти; в БД попадает при первом непустом сохранении.
  Note draft() {
    final now = DateTime.now().toUtc();
    return Note(id: _uuid.v4(), createdAt: now, updatedAt: now);
  }

  NoteChecklistItem newChecklistItem([String text = '']) {
    return NoteChecklistItem(id: _uuid.v4(), text: text);
  }

  /// Сохраняет заметку как есть ([Note.updatedAt] выставляет вызывающий).
  Future<void> save(Note note) => _repository.saveNote(note);

  Future<void> togglePinned(Note note) {
    return _repository.setPinned(note.id, !note.isPinned);
  }

  /// Отметка пункта прямо из карточки списка.
  Future<void> toggleChecklistItem(Note note, String itemId) {
    return save(
      note.copyWith(
        updatedAt: DateTime.now().toUtc(),
        checklist: [
          for (final item in note.checklist)
            item.id == itemId
                ? item.copyWith(isCompleted: !item.isCompleted)
                : item,
        ],
      ),
    );
  }

  Future<void> delete(String id) => _repository.deleteNote(id);
}
