import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(appDatabaseProvider));
});

class SettingsRepository {
  final AppDatabase _db;

  SettingsRepository(this._db);

  /// Поток всех настроек в виде карты «ключ — значение».
  Stream<Map<String, String>> watchAll() {
    return _db.select(_db.appSettings).watch().map(_toMap);
  }

  /// Однократное чтение всех настроек.
  Future<Map<String, String>> readAll() async {
    final rows = await _db.select(_db.appSettings).get();
    return _toMap(rows);
  }

  Future<void> setValue(String key, String value) {
    return _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(settingKey: key, settingValue: value),
        );
  }

  Map<String, String> _toMap(List<AppSettingEntity> rows) {
    return {for (final row in rows) row.settingKey: row.settingValue};
  }
}
