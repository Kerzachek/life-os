enum HabitFrequencyType {
  daily(0, 'Ежедневно'),
  weekly(1, 'По дням недели'),
  interval(2, 'Интервал');

  final int value;
  final String label;

  const HabitFrequencyType(this.value, this.label);

  static HabitFrequencyType fromValue(int value) {
    return HabitFrequencyType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => HabitFrequencyType.daily,
    );
  }
}
