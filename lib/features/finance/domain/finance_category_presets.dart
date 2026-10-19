/// Предустановленная категория (без зависимостей от Flutter, чтобы
/// использоваться в сидировании БД).
class FinanceCategoryPreset {
  const FinanceCategoryPreset({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.colorHex,
    this.isIncome = false,
  });

  final String id;
  final String name;
  final String iconKey;
  final String colorHex;
  final bool isIncome;
}

/// Идентификаторы категорий, на которые ссылается логика модуля.
abstract final class FinanceCategoryIds {
  static const String loans = 'fin_loans';
  static const String obligations = 'fin_obligations';
  static const String food = 'fin_food';
  static const String shopping = 'fin_shopping';
  static const String transport = 'fin_transport';
  static const String entertainment = 'fin_entertainment';
  static const String health = 'fin_health';
  static const String home = 'fin_home';
  static const String otherExpense = 'fin_other_expense';
  static const String salary = 'fin_salary';
  static const String otherIncome = 'fin_other_income';
}

/// Идентификатор счёта, создаваемого по умолчанию.
const String defaultFinanceAccountId = 'fin_main_account';

const List<FinanceCategoryPreset> financeCategoryPresets = [
  FinanceCategoryPreset(
    id: FinanceCategoryIds.loans,
    name: 'Кредиты',
    iconKey: 'card',
    colorHex: '#FFFF7675',
  ),
  FinanceCategoryPreset(
    id: FinanceCategoryIds.obligations,
    name: 'Обязательные платежи',
    iconKey: 'receipt',
    colorHex: '#FF6366F1',
  ),
  FinanceCategoryPreset(
    id: FinanceCategoryIds.food,
    name: 'Еда / Фастфуд',
    iconKey: 'fastfood',
    colorHex: '#FFFF9F43',
  ),
  FinanceCategoryPreset(
    id: FinanceCategoryIds.shopping,
    name: 'Покупки',
    iconKey: 'cart',
    colorHex: '#FFFD79A8',
  ),
  FinanceCategoryPreset(
    id: FinanceCategoryIds.transport,
    name: 'Транспорт',
    iconKey: 'transport',
    colorHex: '#FF54A0FF',
  ),
  FinanceCategoryPreset(
    id: FinanceCategoryIds.entertainment,
    name: 'Развлечения',
    iconKey: 'movie',
    colorHex: '#FFA29BFE',
  ),
  FinanceCategoryPreset(
    id: FinanceCategoryIds.health,
    name: 'Здоровье',
    iconKey: 'health',
    colorHex: '#FF00B894',
  ),
  FinanceCategoryPreset(
    id: FinanceCategoryIds.home,
    name: 'Дом',
    iconKey: 'home',
    colorHex: '#FF00CEC9',
  ),
  FinanceCategoryPreset(
    id: FinanceCategoryIds.otherExpense,
    name: 'Прочие расходы',
    iconKey: 'more',
    colorHex: '#FF8B949E',
  ),
  FinanceCategoryPreset(
    id: FinanceCategoryIds.salary,
    name: 'Зарплата',
    iconKey: 'salary',
    colorHex: '#FF00B894',
    isIncome: true,
  ),
  FinanceCategoryPreset(
    id: FinanceCategoryIds.otherIncome,
    name: 'Прочие доходы',
    iconKey: 'gift',
    colorHex: '#FF00CEC9',
    isIncome: true,
  ),
];
