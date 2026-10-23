import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../domain/note.dart';

final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  return NotesRepository(ref.watch(appDatabaseProvider));
});

class NotesRepository {
  final AppDatabase _db;

  NotesRepository(this._db);

  /// Поток активных заметок: сначала закреплённые, затем по дате изменения.
  Stream<List<Note>> watchNotes() {
    return (_db.select(_db.notes)
          ..where((n) => n.deletedAt.isNull())
          ..orderBy([
            (n) => OrderingTerm.desc(n.isPinned),
            (n) => OrderingTerm.desc(n.updatedAt),
          ]))
        .watch()
        .map((rows) => [for (final row in rows) Note.fromEntity(row)]);
  }

  Future<Note?> getNote(String id) async {
    final row = await (_db.select(
      _db.notes,
    )..where((n) => n.id.equals(id) & n.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : Note.fromEntity(row);
  }

  /// Создаёт или перезаписывает заметку целиком.
  Future<void> saveNote(Note note) {
    return _db
        .into(_db.notes)
        .insertOnConflictUpdate(
          NotesCompanion.insert(
            id: note.id,
            createdAt: note.createdAt.toUtc(),
            updatedAt: note.updatedAt.toUtc(),
            deletedAt: const Value(null),
            title: Value(note.title),
            content: Value(note.content),
            checklist: Value(note.encodedChecklist),
            isPinned: Value(note.isPinned),
            colorTag: Value(note.colorTag),
          ),
        );
  }

  Future<void> setPinned(String id, bool pinned) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        isPinned: Value(pinned),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Мягкое удаление заметки.
  Future<void> deleteNote(String id) async {
    final now = DateTime.now().toUtc();
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
