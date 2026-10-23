import 'package:drift/drift.dart';

import 'syncable_table.dart';

/// Заметки. Чек-лист хранится JSON-массивом в [checklist] и синхронизируется
/// вместе с заметкой целиком (Last-Write-Wins по `updatedAt`).
@DataClassName('NoteEntity')
class Notes extends Table with SyncableTable {
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get content => text().withDefault(const Constant(''))();

  /// `[{"id": …, "text": …, "isCompleted": …}, …]`.
  TextColumn get checklist => text().withDefault(const Constant('[]'))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();

  /// Ключ цветовой метки (`NoteColorTag.key`) или `null`.
  TextColumn get colorTag => text().nullable()();
}
