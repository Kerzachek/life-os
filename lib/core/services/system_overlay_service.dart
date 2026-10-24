import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../features/settings/presentation/providers/settings_provider.dart';

/// Пункт меню системного оверлея.
class SystemOverlayItem {
  final String id;
  final String label;
  final Color color;

  const SystemOverlayItem({
    required this.id,
    required this.label,
    required this.color,
  });

  Map<String, Object> toMap() => {
        'id': id,
        'label': label,
        'color': color.toARGB32(),
      };
}

/// Мост к нативной кнопке быстрых действий поверх всех окон ОС.
///
/// Сам оверлей нарисован средствами платформы и живёт вне Flutter-окна:
/// Android — окно `TYPE_APPLICATION_OVERLAY` (доступ «Поверх других
/// приложений»), Windows — безрамочное topmost-окно, macOS — плавающая
/// `NSPanel`. Выбор действия в его меню выводит окно LifeOS на передний
/// план и приходит сюда событием [actions]; форму открывает главный экран.
///
/// Канал `lifeos/system_overlay`:
/// * Dart → платформа: `canDrawOverlays`, `requestPermission`, `show`,
///   `hide`, `takePendingAction` (Android: действие, с которым запущено
///   приложение, пока Flutter ещё не работал);
/// * платформа → Dart: `onAction {id}`, `onDismissed`,
///   `onMoved {isLeft, fraction}`.
class SystemOverlayService {
  static const MethodChannel defaultChannel =
      MethodChannel('lifeos/system_overlay');

  /// Платформы с нативной реализацией оверлея.
  static bool get isPlatformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows || Platform.isMacOS);

  final MethodChannel _channel;
  final _actions = StreamController<String>.broadcast();
  final _dismissed = StreamController<void>.broadcast();
  final _moves = StreamController<QuickButtonPosition>.broadcast();

  SystemOverlayService({this._channel = defaultChannel}) {
    _channel.setMethodCallHandler(_handle);
  }

  /// Выбранное в оверлее действие (id из `quickMenuActions`).
  Stream<String> get actions => _actions.stream;

  /// Пользователь нажал «Скрыть» в меню оверлея.
  Stream<void> get dismissed => _dismissed.stream;

  /// Кнопку перетащили и примагнитили к краю экрана.
  Stream<QuickButtonPosition> get moves => _moves.stream;

  Future<dynamic> _handle(MethodCall call) async {
    final args = call.arguments;
    switch (call.method) {
      case 'onAction':
        final id = args is Map ? args['id'] : null;
        if (id is String) _actions.add(id);
      case 'onDismissed':
        _dismissed.add(null);
      case 'onMoved':
        if (args is! Map) return;
        final fraction = args['fraction'];
        if (fraction is! num) return;
        _moves.add(QuickButtonPosition(
          isLeft: args['isLeft'] == true,
          verticalFraction: fraction.toDouble().clamp(0.0, 1.0),
        ));
    }
  }

  /// Есть ли доступ рисовать поверх других приложений. На десктопе
  /// отдельного разрешения нет — всегда `true`.
  Future<bool> canDrawOverlays() async =>
      await _invoke<bool>('canDrawOverlays') ?? false;

  /// Открывает системный экран спецдоступа «Поверх других приложений».
  Future<void> requestPermission() => _invoke<void>('requestPermission');

  /// Показывает оверлей или обновляет его меню и режим скрытия. Положение
  /// применяется только при создании: уже показанная кнопка не прыгает.
  /// `false` — показать не удалось (нет разрешения).
  Future<bool> show({
    required List<SystemOverlayItem> items,
    required QuickButtonPosition position,
    required bool hideWhenAppVisible,
  }) async {
    final shown = await _invoke<bool>('show', {
      'items': [for (final item in items) item.toMap()],
      'isLeft': position.isLeft,
      'fraction': position.verticalFraction,
      'hideWhenAppVisible': hideWhenAppVisible,
    });
    return shown ?? false;
  }

  /// Убирает оверлей из системы (окно уничтожается, не просто прячется).
  Future<void> hide() => _invoke<void>('hide');

  /// Действие, с которым оверлей запустил приложение «с нуля».
  Future<String?> takePendingAction() => _invoke<String>('takePendingAction');

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('SystemOverlayService.$method: $e');
      return null;
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _actions.close();
    _dismissed.close();
    _moves.close();
  }
}
