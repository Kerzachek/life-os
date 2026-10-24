import 'package:drift/drift.dart';
import 'finance_categories_table.dart';
import 'syncable_table.dart';

/// Месячный лимит трат по категории.
///
/// Лимит действует с месяца [period] и далее, пока для категории не задан
/// лимит с более поздним [period]. `monthlyLimit <= 0` — лимит снят.
/// `id` детерминирован (`категория + период`, см. `categoryBudgetId`),
/// чтобы правки одного месяца на разных устройствах сливались в одну запись.
@DataClassName('CategoryBudgetEntity')
class CategoryBudgets extends Table with SyncableTable {
  TextColumn get categoryId => text().references(FinanceCategories, #id)();
  RealColumn get monthlyLimit => real()();

  /// Месяц начала действия в виде `год * 100 + месяц` (например, `202610`):
  /// не зависит от часового пояса устройства.
  IntColumn get period => integer()();
}
