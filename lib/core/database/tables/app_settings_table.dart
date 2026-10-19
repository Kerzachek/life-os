import 'package:drift/drift.dart';

/// Таблица пользовательских настроек в формате «ключ — значение».
@DataClassName('AppSettingEntity')
class AppSettings extends Table {
  TextColumn get settingKey => text()();
  TextColumn get settingValue => text()();

  @override
  Set<Column> get primaryKey => {settingKey};
}
