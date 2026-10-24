import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/system_overlay_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../quick_menu_actions.dart';

/// Есть ли нативный оверлей на этой платформе (в тестах переопределяется).
final systemOverlaySupportedProvider =
    Provider<bool>((_) => SystemOverlayService.isPlatformSupported);

final systemOverlayServiceProvider = Provider<SystemOverlayService>((ref) {
  final service = SystemOverlayService();
  ref.onDispose(service.dispose);
  return service;
});

/// Оверлей спрятан кнопкой «Скрыть» — до следующего запуска приложения
/// или повторного включения в настройках. Не сохраняется в базе.
class SystemOverlayDismissedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;

  void restore() => state = false;
}

final systemOverlayDismissedProvider =
    NotifierProvider<SystemOverlayDismissedNotifier, bool>(
  SystemOverlayDismissedNotifier.new,
);

/// Доступ «Поверх других приложений» (Android; на десктопе всегда есть).
/// Перечитывается при возврате в приложение из системных настроек.
final systemOverlayPermissionProvider = FutureProvider<bool>((ref) {
  if (!ref.watch(systemOverlaySupportedProvider)) return false;
  return ref.watch(systemOverlayServiceProvider).canDrawOverlays();
});

/// Пункты меню оверлея: быстрые действия включённых разделов.
final systemOverlayItemsProvider = Provider<List<SystemOverlayItem>>((ref) {
  final enabled = ref.watch(enabledModulesProvider);
  return [
    for (final action in quickMenuActions)
      if (enabled.contains(action.module))
        SystemOverlayItem(
          id: action.id,
          label: action.label,
          color: action.color,
        ),
  ];
});

/// Держит нативный оверлей в соответствии с настройками: показывает,
/// обновляет меню, уничтожает при выключении или «Скрыть». Сохраняет
/// положение, в которое кнопку перетащили.
final systemOverlayControllerProvider =
    Provider<SystemOverlayController>((ref) {
  final controller = SystemOverlayController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

class SystemOverlayController {
  final Ref _ref;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  AppLifecycleListener? _lifecycle;
  bool _started = false;
  bool _syncScheduled = false;
  bool _shown = false;

  SystemOverlayController(this._ref);

  SystemOverlayService get _service => _ref.read(systemOverlayServiceProvider);

  /// Подписывается на настройки и события оверлея. Повторный вызов — no-op.
  void start() {
    if (_started || !_ref.read(systemOverlaySupportedProvider)) return;
    _started = true;

    void resync(Object? _, Object? _) => _scheduleSync();
    _ref.listen(systemOverlayEnabledProvider, resync);
    _ref.listen(systemOverlayHideWhenAppVisibleProvider, resync);
    _ref.listen(systemOverlayItemsProvider, resync);
    _ref.listen(systemOverlayDismissedProvider, resync);

    _subscriptions
      ..add(_service.dismissed.listen((_) {
        // Нативная сторона окно уже убрала.
        _shown = false;
        _ref.read(systemOverlayDismissedProvider.notifier).dismiss();
      }))
      ..add(_service.moves.listen((position) => _ref
          .read(settingsControllerProvider)
          .setSystemOverlayPosition(position)));

    // Вернулись из системных настроек: доступ могли только что выдать.
    _lifecycle = AppLifecycleListener(onResume: () {
      _ref.invalidate(systemOverlayPermissionProvider);
      _scheduleSync();
    });
    _scheduleSync();
  }

  /// Несколько изменений подряд (загрузка настроек) — один вызов канала.
  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    scheduleMicrotask(() {
      _syncScheduled = false;
      unawaited(_sync());
    });
  }

  Future<void> _sync() async {
    final items = _ref.read(systemOverlayItemsProvider);
    final wanted = _ref.read(systemOverlayEnabledProvider) &&
        !_ref.read(systemOverlayDismissedProvider) &&
        items.isNotEmpty;
    if (wanted) {
      _shown = await _service.show(
        items: items,
        position: _ref.read(systemOverlayPositionProvider),
        hideWhenAppVisible: _ref.read(systemOverlayHideWhenAppVisibleProvider),
      );
    } else if (_shown) {
      _shown = false;
      await _service.hide();
    }
  }

  void dispose() {
    _lifecycle?.dispose();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
  }
}
