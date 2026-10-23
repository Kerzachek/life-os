import 'dart:convert';

import '../../../core/database/app_database.dart';

/// Пункт чек-листа заметки.
class NoteChecklistItem {
  final String id;
  final String text;
  final bool isCompleted;

  const NoteChecklistItem({
    required this.id,
    required this.text,
    this.isCompleted = false,
  });

  NoteChecklistItem copyWith({String? text, bool? isCompleted}) {
    return NoteChecklistItem(
      id: id,
      text: text ?? this.text,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'isCompleted': isCompleted,
  };

  factory NoteChecklistItem.fromJson(Map<String, dynamic> json) {
    return NoteChecklistItem(
      id: json['id'] as String,
      text: json['text'] as String? ?? '',
      isCompleted: json['isCompleted'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NoteChecklistItem &&
      other.id == id &&
      other.text == text &&
      other.isCompleted == isCompleted;

  @override
  int get hashCode => Object.hash(id, text, isCompleted);
}

/// Заметка: заголовок, текст и необязательный чек-лист.
class Note {
  final String id;
  final String title;
  final String content;
  final List<NoteChecklistItem> checklist;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPinned;

  /// Ключ цветовой метки (`NoteColorTag.key`) или `null`.
  final String? colorTag;

  const Note({
    required this.id,
    this.title = '',
    this.content = '',
    this.checklist = const [],
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
    this.colorTag,
  });

  /// Пустая заметка не сохраняется: ни заголовка, ни текста, ни пунктов.
  bool get isEmpty =>
      title.trim().isEmpty &&
      content.trim().isEmpty &&
      checklist.every((i) => i.text.trim().isEmpty);

  int get completedCount => checklist.where((i) => i.isCompleted).length;

  Note copyWith({
    String? title,
    String? content,
    List<NoteChecklistItem>? checklist,
    DateTime? updatedAt,
    bool? isPinned,
    String? Function()? colorTag,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      checklist: checklist ?? this.checklist,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      colorTag: colorTag != null ? colorTag() : this.colorTag,
    );
  }

  /// Совпадает ли содержимое (без учёта времени изменения).
  bool sameContentAs(Note other) {
    if (title != other.title ||
        content != other.content ||
        isPinned != other.isPinned ||
        colorTag != other.colorTag ||
        checklist.length != other.checklist.length) {
      return false;
    }
    for (var i = 0; i < checklist.length; i++) {
      if (checklist[i] != other.checklist[i]) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'checklist': [for (final item in checklist) item.toJson()],
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'isPinned': isPinned,
    'colorTag': colorTag,
  };

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      checklist: [
        for (final item in json['checklist'] as List? ?? const [])
          NoteChecklistItem.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
      isPinned: json['isPinned'] as bool? ?? false,
      colorTag: json['colorTag'] as String?,
    );
  }

  factory Note.fromEntity(NoteEntity entity) {
    return Note(
      id: entity.id,
      title: entity.title,
      content: entity.content,
      checklist: decodeChecklist(entity.checklist),
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      isPinned: entity.isPinned,
      colorTag: entity.colorTag,
    );
  }

  /// Чек-лист в виде JSON-строки для колонки `notes.checklist`.
  String get encodedChecklist =>
      jsonEncode([for (final item in checklist) item.toJson()]);

  /// Разбирает колонку `notes.checklist`. Повреждённое значение — пустой
  /// список, чтобы одна битая запись не ломала весь раздел.
  static List<NoteChecklistItem> decodeChecklist(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map && item['id'] is String)
            NoteChecklistItem.fromJson(Map<String, dynamic>.from(item)),
      ];
    } on FormatException {
      return const [];
    }
  }
}
