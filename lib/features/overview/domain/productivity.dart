/// Общий процент продуктивности (0..1) по активным разделам.
///
/// `null` в [ratios] означает, что раздел отключён или в нём нет данных:
/// такой компонент не учитывается и не занижает итог. Если учитывать
/// нечего — возвращает `null`.
double? overallProductivity(Iterable<double?> ratios) {
  final active = ratios.whereType<double>().toList();
  if (active.isEmpty) return null;
  final sum = active.fold<double>(0, (acc, r) => acc + r.clamp(0.0, 1.0));
  return sum / active.length;
}
