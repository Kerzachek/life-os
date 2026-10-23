import 'package:flutter/material.dart';

/// Цветовые метки заметок. В БД хранится [key].
enum NoteColorTag {
  red('red', 'Красная', Color(0xFFFF7675)),
  orange('orange', 'Оранжевая', Color(0xFFFDAA5E)),
  yellow('yellow', 'Жёлтая', Color(0xFFFDD663)),
  green('green', 'Зелёная', Color(0xFF00B894)),
  cyan('cyan', 'Бирюзовая', Color(0xFF00CEC9)),
  blue('blue', 'Синяя', Color(0xFF74B9FF)),
  purple('purple', 'Фиолетовая', Color(0xFFA29BFE));

  const NoteColorTag(this.key, this.label, this.color);

  final String key;
  final String label;
  final Color color;

  /// Метка по ключу; неизвестный ключ (например, с более новой версии) —
  /// `null`, заметка показывается без цвета.
  static NoteColorTag? fromKey(String? key) {
    for (final tag in values) {
      if (tag.key == key) return tag;
    }
    return null;
  }
}
