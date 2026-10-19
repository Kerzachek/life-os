import 'package:drift/drift.dart';

import 'sync_payload.dart';

/// Итог слияния облачного снимка с локальной БД.
class MergeResult {
  final int inserted;
  final int updated;
  final int skipped;

  const MergeResult({
    this.inserted = 0,
    this.updated = 0,
    this.skipped = 0,
  });

  /// Сколько локальных строк изменилось.
  int get changed => inserted + updated;

  MergeResult operator +(MergeResult other) => MergeResult(
        inserted: inserted + other.inserted,
        updated: updated + other.updated,
        skipped: skipped + other.skipped,
      );

  @override
  String toString() =>
      'MergeResult(inserted: $inserted, updated: $updated, skipped: $skipped)';
}

/// Синхронизируемая таблица: выгрузка строк и построчное слияние (LWW).
abstract class SyncTable {
  String get name;
  TableInfo<Table, dynamic> get tableInfo;
  Future<List<Map<String, dynamic>>> exportRows();
  Future<MergeResult> merge(List<Map<String, dynamic>> remoteRows);
}

typedef EntityFromJson<D> = D Function(
  Map<String, dynamic> json, {
  ValueSerializer? serializer,
});

/// Адаптер конкретной Drift-таблицы к [SyncTable].
///
/// Идентификатор записи — существующий `id` (UUID v4). «Возраст» записи —
/// `max(updatedAt, deletedAt)`: удаление, выполненное позже чужой правки,
/// побеждает. При равных метках побеждает удаление, чтобы запись не
/// «воскресала».
class DriftSyncTable<T extends Table, D extends DataClass>
    implements SyncTable {
  DriftSyncTable({
    required this.name,
    required this.db,
    required this.table,
    required this.fromJson,
  });

  @override
  final String name;

  final GeneratedDatabase db;
  final TableInfo<T, D> table;
  final EntityFromJson<D> fromJson;

  @override
  TableInfo<Table, dynamic> get tableInfo => table;

  Map<String, dynamic> _toMap(D row) {
    return row.toJson(serializer: syncValueSerializer);
  }

  @override
  Future<List<Map<String, dynamic>>> exportRows() async {
    final rows = await db.select(table).get();
    // Детерминированный порядок: по нему сравнивается «облако == локально».
    return [for (final row in rows) _toMap(row)]
      ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  }

  @override
  Future<MergeResult> merge(List<Map<String, dynamic>> remoteRows) async {
    final localRows = await db.select(table).get();
    final localById = <String, Map<String, dynamic>>{};
    for (final row in localRows) {
      final map = _toMap(row);
      localById[map['id'] as String] = map;
    }

    var inserted = 0;
    var updated = 0;
    var skipped = 0;

    for (final remote in remoteRows) {
      final id = remote['id'];
      if (id is! String) {
        throw SyncFormatException('Запись таблицы $name без идентификатора');
      }
      final local = localById[id];
      if (local == null) {
        await _write(remote);
        inserted++;
      } else if (_remoteWins(remote: remote, local: local)) {
        await _write(remote);
        updated++;
      } else {
        skipped++;
      }
    }
    return MergeResult(inserted: inserted, updated: updated, skipped: skipped);
  }

  /// Пишет строку целиком. `toColumns(false)` сохраняет `NULL`-значения, чтобы
  /// очищенные в облаке поля очищались и локально.
  Future<void> _write(Map<String, dynamic> json) {
    final entity = fromJson(json, serializer: syncValueSerializer);
    final insertable = entity as Insertable<D>;
    return db.into(table).insertOnConflictUpdate(
          RawValuesInsertable<D>(insertable.toColumns(false)),
        );
  }

  bool _remoteWins({
    required Map<String, dynamic> remote,
    required Map<String, dynamic> local,
  }) {
    final remoteStamp = _effectiveTimestamp(remote);
    final localStamp = _effectiveTimestamp(local);
    if (remoteStamp.isAfter(localStamp)) return true;
    if (remoteStamp.isAtSameMomentAs(localStamp)) {
      return remote['deletedAt'] != null && local['deletedAt'] == null;
    }
    return false;
  }

  DateTime _effectiveTimestamp(Map<String, dynamic> row) {
    final updatedAt = _parseDate(row['updatedAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final deletedAt = _parseDate(row['deletedAt']);
    if (deletedAt != null && deletedAt.isAfter(updatedAt)) return deletedAt;
    return updatedAt;
  }

  DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    return DateTime.parse(value.toString()).toUtc();
  }
}
