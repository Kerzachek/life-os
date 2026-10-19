import 'dart:convert';

import 'package:drift/drift.dart';

/// Сериализатор значений Drift для облачного JSON.
///
/// Даты всегда пишутся как ISO-8601 в UTC (а не unix-timestamp), чтобы файл
/// был читаемым и не зависел от часового пояса устройства.
class SyncValueSerializer extends ValueSerializer {
  const SyncValueSerializer();

  static const ValueSerializer _defaults =
      ValueSerializer.defaults(serializeDateTimeValuesAsString: true);

  @override
  T fromJson<T>(dynamic json) => _defaults.fromJson<T>(json);

  @override
  dynamic toJson<T>(T value) {
    if (value is DateTime) return value.toUtc().toIso8601String();
    return _defaults.toJson<T>(value);
  }
}

const SyncValueSerializer syncValueSerializer = SyncValueSerializer();

/// Исключение формата / версии облачного файла.
class SyncFormatException implements Exception {
  final String message;

  const SyncFormatException(this.message);

  @override
  String toString() => 'SyncFormatException: $message';
}

/// Снимок синхронизируемых таблиц, который хранится в облачном JSON.
///
/// Записи, помеченные удалёнными (`deletedAt != null`), входят в снимок:
/// именно так удаление доезжает до остальных устройств.
class SyncPayload {
  /// Версия формата файла. Увеличивается при несовместимых изменениях.
  static const int currentVersion = 1;

  final int version;
  final DateTime lastSyncTimestamp;
  final String deviceId;

  /// Имя таблицы → список строк (JSON-представление Drift-сущностей).
  final Map<String, List<Map<String, dynamic>>> tables;

  const SyncPayload({
    this.version = currentVersion,
    required this.lastSyncTimestamp,
    required this.deviceId,
    required this.tables,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'lastSyncTimestamp': lastSyncTimestamp.toUtc().toIso8601String(),
        'deviceId': deviceId,
        'tables': tables,
      };

  String encode() => jsonEncode(toJson());

  factory SyncPayload.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final timestamp = json['lastSyncTimestamp'];
    final deviceId = json['deviceId'];
    final rawTables = json['tables'];
    if (version is! int ||
        timestamp is! String ||
        deviceId is! String ||
        rawTables is! Map) {
      throw const SyncFormatException('Некорректная структура файла синхронизации');
    }
    if (version > currentVersion) {
      throw SyncFormatException(
        'Файл создан более новой версией приложения (v$version). '
        'Обновите приложение.',
      );
    }
    final tables = <String, List<Map<String, dynamic>>>{};
    for (final entry in rawTables.entries) {
      final rows = entry.value;
      if (entry.key is! String || rows is! List) {
        throw const SyncFormatException('Некорректный список записей в файле синхронизации');
      }
      tables[entry.key as String] = [
        for (final row in rows) Map<String, dynamic>.from(row as Map),
      ];
    }
    return SyncPayload(
      version: version,
      lastSyncTimestamp: DateTime.parse(timestamp).toUtc(),
      deviceId: deviceId,
      tables: tables,
    );
  }

  factory SyncPayload.decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw SyncFormatException('Файл синхронизации повреждён: ${e.message}');
    }
    if (decoded is! Map) {
      throw const SyncFormatException('Файл синхронизации повреждён');
    }
    return SyncPayload.fromJson(Map<String, dynamic>.from(decoded));
  }
}
