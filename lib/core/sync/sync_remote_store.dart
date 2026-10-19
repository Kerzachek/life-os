import 'dart:convert';

import 'package:googleapis/drive/v3.dart' as drive;

import 'sync_engine.dart';
import 'sync_payload.dart';

/// Имя файла синхронизации в скрытой папке `appDataFolder`.
const String syncFileName = 'life_os_sync_v1.json';

/// Удалённое хранилище единственного файла синхронизации.
abstract class SyncRemoteStore {
  /// Содержимое файла или `null`, если файла в облаке ещё нет.
  Future<String?> download();

  /// Создаёт файл или перезаписывает существующий.
  Future<void> upload(String content);
}

/// Хранилище на Google Drive API v3 (`spaces = appDataFolder`).
///
/// Файл не виден пользователю в интерфейсе Drive и доступен только этому
/// приложению (скоуп `DriveApi.driveAppdataScope`).
class DriveAppDataStore implements SyncRemoteStore {
  static const String _space = 'appDataFolder';

  final drive.DriveApi _api;
  String? _fileId;

  DriveAppDataStore(this._api);

  /// Ищет файл по имени. Если из-за гонки двух устройств файлов несколько,
  /// берём самый старый — все устройства сойдутся на одном и том же.
  Future<String?> _findFileId() async {
    final cached = _fileId;
    if (cached != null) return cached;
    final list = await _api.files.list(
      spaces: _space,
      q: "name = '$syncFileName' and trashed = false",
      orderBy: 'createdTime',
      pageSize: 10,
      $fields: 'files(id)',
    );
    final files = list.files;
    if (files == null || files.isEmpty) return null;
    return _fileId = files.first.id;
  }

  @override
  Future<String?> download() async {
    final id = await _findFileId();
    if (id == null) return null;
    final media = await _api.files.get(
      id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  @override
  Future<void> upload(String content) async {
    final bytes = utf8.encode(content);
    final media = drive.Media(
      Stream<List<int>>.value(bytes),
      bytes.length,
      contentType: 'application/json',
    );
    final id = await _findFileId();
    if (id == null) {
      final created = await _api.files.create(
        drive.File(name: syncFileName, parents: [_space]),
        uploadMedia: media,
        $fields: 'id',
      );
      _fileId = created.id;
    } else {
      await _api.files.update(drive.File(), id, uploadMedia: media);
    }
  }
}

/// Результат одного цикла синхронизации.
class SyncOutcome {
  final MergeResult merge;
  final bool uploaded;

  const SyncOutcome({required this.merge, required this.uploaded});
}

/// Один цикл синхронизации:
/// 1. скачать файл (если есть);
/// 2. слить его в локальную БД;
/// 3. выгрузить объединённое состояние и загрузить его обратно в облако.
///
/// Загрузка пропускается, если облачные данные уже совпадают с локальными
/// (чтобы не плодить лишние запросы и не зацикливать триггеры).
Future<SyncOutcome> performSync(
  SyncEngine engine,
  SyncRemoteStore store,
) async {
  final text = await store.download();

  SyncPayload? remote;
  var merge = const MergeResult();
  if (text != null && text.trim().isNotEmpty) {
    remote = SyncPayload.decode(text);
    merge = await engine.mergeFromSyncPayload(remote);
  }

  final local = await engine.exportToSyncPayload();
  final inSync =
      remote != null && jsonEncode(remote.tables) == jsonEncode(local.tables);
  if (!inSync) {
    await store.upload(local.encode());
  }
  return SyncOutcome(merge: merge, uploaded: !inSync);
}
