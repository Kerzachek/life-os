import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_engine.dart';
import '../sync/sync_payload.dart';
import '../sync/sync_providers.dart';

/// Имя файла копии по умолчанию: `LifeOS_Backup_2026-10-24_1830.json`
/// (локальное время устройства).
String backupFileName(DateTime now) {
  final d = now.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'LifeOS_Backup_${d.year}-${two(d.month)}-${two(d.day)}_'
      '${two(d.hour)}${two(d.minute)}.json';
}

/// Локальная резервная копия: тот же [SyncPayload], что уходит в облако,
/// только в файле, выбранном пользователем.
class LocalBackupService {
  final SyncEngine _engine;

  LocalBackupService(this._engine);

  /// Снимок всех синхронизируемых таблиц в виде JSON (UTF-8, с отступами,
  /// чтобы файл можно было прочитать глазами).
  Future<Uint8List> createBackup() async {
    return encodeBackup(await createPayload());
  }

  Future<SyncPayload> createPayload() => _engine.exportToSyncPayload();

  static Uint8List encodeBackup(SyncPayload payload) {
    final text = const JsonEncoder.withIndent('  ').convert(payload.toJson());
    return Uint8List.fromList(utf8.encode(text));
  }

  /// Разбирает и проверяет файл копии.
  /// Бросает [SyncFormatException] с понятным пользователю текстом.
  SyncPayload parseBackup(Uint8List bytes) {
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const SyncFormatException('Файл не является текстом в UTF-8');
    }
    // Редактор мог дописать BOM.
    final payload = SyncPayload.decode(
      text.startsWith('\uFEFF') ? text.substring(1) : text,
    );
    _validate(payload);
    return payload;
  }

  void _validate(SyncPayload payload) {
    final known = _engine.tableNames.toSet();
    final unknown = payload.tables.keys.where((t) => !known.contains(t));
    if (unknown.isNotEmpty) {
      throw SyncFormatException(
        'Файл не похож на резервную копию LifeOS: '
        'неизвестные таблицы ${unknown.join(', ')}',
      );
    }
    if (payload.tables.isEmpty) {
      throw const SyncFormatException('В резервной копии нет данных');
    }
    for (final entry in payload.tables.entries) {
      for (final row in entry.value) {
        if (row['id'] is! String || row['updatedAt'] is! String) {
          throw SyncFormatException(
            'Повреждена запись в таблице ${entry.key}: '
            'нет id или updatedAt',
          );
        }
      }
    }
  }

  /// Количество записей (без удалённых) — для диалога подтверждения.
  static int countRecords(SyncPayload payload) {
    var count = 0;
    for (final rows in payload.tables.values) {
      count += rows.where((r) => r['deletedAt'] == null).length;
    }
    return count;
  }

  /// Сливает копию в локальную базу по правилам синхронизации
  /// (Last-Write-Wins по `updatedAt`).
  Future<MergeResult> restore(SyncPayload payload) =>
      _engine.mergeFromSyncPayload(payload);
}

final localBackupServiceProvider = Provider<LocalBackupService>((ref) {
  return LocalBackupService(ref.watch(syncEngineProvider));
});
