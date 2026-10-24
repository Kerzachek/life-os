import '../../../core/database/app_database.dart';
import 'finance_enums.dart';

/// Диапазон дат выгрузки операций в CSV.
enum CsvExportRange {
  all('Всё время', 'all'),
  thisMonth('Этот месяц', 'this-month'),
  lastMonth('Прошлый месяц', 'last-month');

  const CsvExportRange(this.label, this.fileSuffix);

  final String label;
  final String fileSuffix;

  /// Входит ли [date] в диапазон относительно момента [now] (локальное время).
  bool contains(DateTime date, DateTime now) {
    final d = date.toLocal();
    switch (this) {
      case CsvExportRange.all:
        return true;
      case CsvExportRange.thisMonth:
        return d.year == now.year && d.month == now.month;
      case CsvExportRange.lastMonth:
        final prev = DateTime(now.year, now.month - 1);
        return d.year == prev.year && d.month == prev.month;
    }
  }
}

/// Валюта всех сумм: мультивалютности в приложении нет.
const String csvCurrency = 'RUB';

const List<String> transactionsCsvHeader = [
  'Дата и время',
  'Тип',
  'Сумма',
  'Валюта',
  'Счёт списания',
  'Счёт зачисления',
  'Категория',
  'Описание/Заметка',
];

/// Имя файла: `LifeOS_Transactions_this-month_2026-10-24.csv`.
String transactionsCsvFileName(CsvExportRange range, DateTime now) {
  final d = now.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'LifeOS_Transactions_${range.fileSuffix}_'
      '${d.year}-${two(d.month)}-${two(d.day)}.csv';
}

/// Выгрузка операций в CSV для Excel.
///
/// UTF-8 с BOM, разделитель `;` и десятичная запятая — так файл открывается
/// двойным щелчком в Excel с русской локалью без мастера импорта.
/// Операции идут по возрастанию даты.
String buildTransactionsCsv({
  required List<FinanceTransactionEntity> transactions,
  required Map<String, FinanceAccountEntity> accounts,
  required Map<String, FinanceCategoryEntity> categories,
  required CsvExportRange range,
  required DateTime now,
}) {
  final rows =
      transactions
          .where((t) => t.deletedAt == null && range.contains(t.date, now))
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  String account(String? id) => id == null ? '' : accounts[id]?.name ?? '';

  final buffer = StringBuffer('\uFEFF')..write(_line(transactionsCsvHeader));
  for (final t in rows) {
    final type = FinanceTransactionType.fromValue(t.type);
    // Доход зачисляется на accountId; расход и перевод списываются с него,
    // а targetAccountId — счёт зачисления (перевод, погашение кредита).
    final from = type == FinanceTransactionType.income
        ? ''
        : account(t.accountId);
    final to = type == FinanceTransactionType.income
        ? account(t.accountId)
        : account(t.targetAccountId);
    buffer.write(
      _line([
        _formatDateTime(t.date),
        type.label,
        _formatAmount(t.amount),
        csvCurrency,
        from,
        to,
        t.categoryId == null ? '' : categories[t.categoryId]?.name ?? '',
        t.note ?? '',
      ]),
    );
  }
  return buffer.toString();
}

String _line(List<String> fields) => '${fields.map(_escape).join(';')}\r\n';

String _escape(String field) {
  if (!field.contains(RegExp('[;"\r\n]'))) return field;
  return '"${field.replaceAll('"', '""')}"';
}

String _formatDateTime(DateTime date) {
  final d = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// `1234.5` → `1234,50`: без разделителя тысяч, чтобы Excel распознал число.
String _formatAmount(double amount) =>
    amount.toStringAsFixed(2).replaceAll('.', ',');
