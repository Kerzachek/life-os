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

/// Короткое название месяца для подписей осей: `Окт`.
String formatMonthShort(DateTime month) =>
    _monthNames[month.month - 1].substring(0, 3);

/// Сумма для подписей осей: `950`, `12 тыс`, `1,2 млн`.
String formatMoneyCompact(double value) {
  final sign = value < 0 ? '−' : '';
  final abs = value.abs();
  if (abs >= 1e6) {
    final m = (abs / 1e6).toStringAsFixed(abs >= 1e7 ? 0 : 1);
    return '$sign${m.replaceAll('.', ',')} млн';
  }
  if (abs >= 1e3) return '$sign${(abs / 1e3).round()} тыс';
  return '$sign${abs.round()}';
}

/// Разбор суммы из поля ввода (допускает запятую и пробелы).
double? parseMoney(String? raw) {
  if (raw == null) return null;
  final cleaned = raw.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}
