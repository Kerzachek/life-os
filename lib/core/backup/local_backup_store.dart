import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Одна копия в папке приложения.
class LocalBackupEntry {
  const LocalBackupEntry({
    required this.file,
    required this.date,
    required this.sizeBytes,
  });

  final File file;

  /// День копии (из имени файла, локальная дата).
  final DateTime date;
  final int sizeBytes;

  String get fileName => p.basename(file.path);
}

/// Папка с автоматическими и ручными копиями внутри данных приложения:
/// одна копия на день (`LifeOS_Backup_YYYY-MM-DD.json`), старше
/// [maxCopies] удаляются.
class LocalBackupStore {
  static const int maxCopies = 10;

  static final RegExp _namePattern = RegExp(
    r'^LifeOS_Backup_(\d{4})-(\d{2})-(\d{2})\.json$',
  );

  /// Папка; `Future`, потому что путь у плагина запрашивается асинхронно.
  final Future<Directory> Function() _directory;

  LocalBackupStore(this._directory);

  /// Имя ежедневной копии: `LifeOS_Backup_2026-10-25.json`.
  static String dailyFileName(DateTime now) {
    final d = now.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'LifeOS_Backup_${d.year}-${two(d.month)}-${two(d.day)}.json';
  }

  Future<String> get directoryPath async => (await _directory()).path;

  /// Копии от новых к старым.
  Future<List<LocalBackupEntry>> list() async {
    final dir = await _directory();
    if (!await dir.exists()) return const [];
    final entries = <LocalBackupEntry>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final match = _namePattern.firstMatch(p.basename(entity.path));
      if (match == null) continue;
      entries.add(
        LocalBackupEntry(
          file: entity,
          date: DateTime(
            int.parse(match.group(1)!),
            int.parse(match.group(2)!),
            int.parse(match.group(3)!),
          ),
          sizeBytes: await entity.length(),
        ),
      );
    }
    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  /// Есть ли уже копия за день [now].
  Future<bool> hasCopyFor(DateTime now) async {
    final dir = await _directory();
    return File(p.join(dir.path, dailyFileName(now))).exists();
  }

  /// Записывает копию за день [now] (перезаписывая копию этого дня) и
  /// удаляет лишние старые.
  Future<File> save(Uint8List bytes, DateTime now) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, dailyFileName(now)));
    // Сначала во временный файл: оборванная запись не испортит копию дня.
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
    await _rotate();
    return file;
  }

  Future<Uint8List> read(LocalBackupEntry entry) => entry.file.readAsBytes();

  Future<void> _rotate() async {
    final entries = await list();
    for (final old in entries.skip(maxCopies)) {
      try {
        await old.file.delete();
      } on FileSystemException {
        // Файл занят или уже удалён — попробуем при следующей копии.
      }
    }
  }
}

/// `<документы приложения>/LifeOS/backups`. На Windows документы приложения —
/// папка «Документы» пользователя, поэтому копии лежат в своей подпапке.
Future<Directory> defaultBackupDirectory() async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory(p.join(docs.path, 'LifeOS', 'backups'));
}

final localBackupStoreProvider = Provider<LocalBackupStore>(
  (ref) => LocalBackupStore(defaultBackupDirectory),
);
