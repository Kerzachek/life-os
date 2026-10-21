import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/routine/data/repositories/routine_repository.dart';
import '../../features/settings/data/repositories/settings_repository.dart';
import '../../features/settings/domain/app_module.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';

/// Ежедневный сброс рутины: при старте, при показе окна из трея
/// и раз в минуту (ловит смену суток в 00:00).
class RoutineResetService {
  static const Duration checkInterval = Duration(minutes: 1);

  final RoutineRepository _routine;
  final SettingsRepository _settings;

  Timer? _periodic;
  Future<void>? _inFlight;

  RoutineResetService(this._routine, this._settings);

  void start() {
    if (_periodic != null) return;
    _periodic = Timer.periodic(checkInterval, (_) => unawaited(checkNow()));
    unawaited(checkNow());
  }

  /// Проверяет смену суток и при необходимости сбрасывает чек-лист.
  Future<void> checkNow() {
    return _inFlight ??= _check().whenComplete(() => _inFlight = null);
  }

  Future<void> _check() async {
    try {
      // Пока раздел отключён, отметки сбрасываются, но история не пишется:
      // иначе диаграмма заполнилась бы нулями за дни без рутины.
      final enabled = resolveEnabledModules(await _settings.readAll())
          .contains(AppModule.routine);
      await _routine.performDailyReset(writeLog: enabled);
    } catch (e) {
      debugPrint('RoutineResetService: ошибка сброса: $e');
    }
  }

  void dispose() {
    _periodic?.cancel();
    _periodic = null;
  }
}

final routineResetServiceProvider = Provider<RoutineResetService>((ref) {
  final service = RoutineResetService(
    ref.watch(routineRepositoryProvider),
    ref.watch(settingsRepositoryProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
