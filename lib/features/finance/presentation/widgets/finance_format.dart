import 'package:intl/intl.dart';

final NumberFormat _moneyFormat = NumberFormat('#,##0.##', 'en_US');

/// Форматирует сумму: `12 345,5 ₽` (разделитель тысяч — пробел).
String formatMoney(double value, {bool withSign = false}) {
  final abs = _moneyFormat.format(value.abs()).replaceAll(',', '\u00A0');
  final text = '$abs\u00A0₽';
  if (value < 0) return '−$text';
  return withSign && value > 0 ? '+$text' : text;
}

/// Дата вида `05.03.2026`.
String formatDate(DateTime date) {
  final d = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

const List<String> _monthNames = [
  'Январь',
  'Февраль',
  'Март',
  'Апрель',
  'Май',
  'Июнь',
  'Июль',
  'Август',
  'Сентябрь',
  'Октябрь',
  'Ноябрь',
  'Декабрь',
];

String formatMonth(DateTime month) => '${_monthNames[month.month - 1]} ${month.year}';

/// Разбор суммы из поля ввода (допускает запятую и пробелы).
double? parseMoney(String? raw) {
  if (raw == null) return null;
  final cleaned = raw.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}
