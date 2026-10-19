/// Индекс продуктивности и жизнестойкости за текущий день (0–100).
///
/// Формула при всех доступных компонентах:
/// 60% — доля выполненных задач за сегодня,
/// 30% — доля выполненных сегодня привычек,
/// 10% — активные стрики привычек.
///
/// Если компонент недоступен (модуль отключён или данных нет), он исключается,
/// а веса оставшихся компонентов нормируются до 100%.
class LifeScore {
  /// Итоговый балл 0–100.
  final int score;

  /// Доля выполненных задач (0..1) или `null`, если компонент не учитывается.
  final double? taskRatio;

  /// Доля выполненных привычек (0..1) или `null`, если компонент не учитывается.
  final double? habitRatio;

  /// Сила активных стриков (0..1) или `null`, если компонент не учитывается.
  final double? streakRatio;

  const LifeScore({
    required this.score,
    this.taskRatio,
    this.habitRatio,
    this.streakRatio,
  });

  static const double taskWeight = 0.6;
  static const double habitWeight = 0.3;
  static const double streakWeight = 0.1;

  /// Количество дней серии, при котором стрик считается «максимальным».
  static const int streakCapDays = 7;

  /// Нет ни одного доступного компонента для расчёта.
  bool get hasData =>
      taskRatio != null || habitRatio != null || streakRatio != null;

  static const LifeScore empty = LifeScore(score: 0);

  /// Рассчитывает балл. `null` в аргументе означает «компонент недоступен».
  factory LifeScore.calculate({
    double? taskRatio,
    double? habitRatio,
    double? streakRatio,
  }) {
    final task = taskRatio?.clamp(0.0, 1.0);
    final habit = habitRatio?.clamp(0.0, 1.0);
    final streak = streakRatio?.clamp(0.0, 1.0);

    var weightSum = 0.0;
    var weighted = 0.0;

    if (task != null) {
      weightSum += taskWeight;
      weighted += task * taskWeight;
    }
    if (habit != null) {
      weightSum += habitWeight;
      weighted += habit * habitWeight;
    }
    if (streak != null) {
      weightSum += streakWeight;
      weighted += streak * streakWeight;
    }

    final value = weightSum == 0 ? 0.0 : weighted / weightSum * 100;

    return LifeScore(
      score: value.round().clamp(0, 100),
      taskRatio: task,
      habitRatio: habit,
      streakRatio: streak,
    );
  }
}
