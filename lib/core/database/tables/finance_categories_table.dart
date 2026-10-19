import 'package:drift/drift.dart';
import 'syncable_table.dart';

/// Категории доходов и расходов (предустановленные и пользовательские).
@DataClassName('FinanceCategoryEntity')
class FinanceCategories extends Table with SyncableTable {
  TextColumn get name => text()();

  /// Цвет в формате `#AARRGGBB`.
  TextColumn get color => text()();

  /// Код иконки (`IconData.codePoint`) в виде строки.
  TextColumn get icon => text().nullable()();
  BoolColumn get isIncome => boolean().withDefault(const Constant(false))();

  /// Предустановленные категории нельзя удалить.
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
}
