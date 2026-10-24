import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/finance/domain/finance_category_presets.dart';
import '../sync/sync_payload.dart';
import 'local_backup_service.dart';
import 'local_backup_store.dart';

/// Автоматическая копия в папку приложения: раз в сутки (при старте и
/// проверкой каждый час) и при уходе приложения в фон или выходе.
class AutoBackupService {
  static const Duration checkInterval = Duration(hours: 1);

  final LocalBackupService _backup;
  final LocalBackupStore _store;
  final DateTime Function() _now;

  Timer? _periodic;
  Future<void>? _inFlight;

  AutoBackupService(this._backup, this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  void start() {
    if (_periodic != null) return;
    _periodic = Timer.periodic(checkInterval, (_) => unawaited(ensureDaily()));
    unawaited(ensureDaily());
  }

  /// Создаёт копию за сегодня, если её ещё нет.
  Future<void> ensureDaily() => _run(onlyIfMissing: true);

  /// Обновляет сегодняшнюю копию актуальными данными (фон, выход).
  Future<void> backupNow() => _run(onlyIfMissing: false);

  Future<void> _run({required bool onlyIfMissing}) {
    return _inFlight ??= _perform(onlyIfMissing)
        .whenComplete(() => _inFlight = null);
  }

  Future<void> _perform(bool onlyIfMissing) async {
    try {
      final now = _now();
      if (onlyIfMissing && await _store.hasCopyFor(now)) return;
      final payload = await _backup.createPayload();
      // Пустая база (свежая установка) не должна вытеснять ротацией
      // настоящие копии.
      if (!hasUserData(payload)) return;
      await _store.save(LocalBackupService.encodeBackup(payload), now);
    } on SyncFormatException catch (e) {
      debugPrint('AutoBackupService: ${e.message}');
    } catch (e) {
      debugPrint('AutoBackupService: копия не создана: $e');
    }
  }

  /// Есть ли в снимке что-то кроме предустановленных данных новой базы
  /// (категории задач и финансов, «Основной счёт»).
  static bool hasUserData(SyncPayload payload) {
    for (final entry in payload.tables.entries) {
      if (entry.key == 'categories' || entry.key == 'finance_categories') {
        continue;
      }
      for (final row in entry.value) {
        if (row['deletedAt'] != null) continue;
        if (entry.key == 'finance_accounts' &&
            row['id'] == defaultFinanceAccountId) {
          continue;
        }
        return true;
      }
    }
    return false;
  }

  void dispose() {
    _periodic?.cancel();
    _periodic = null;
  }
}

final autoBackupServiceProvider = Provider<AutoBackupService>((ref) {
  final service = AutoBackupService(
    ref.watch(localBackupServiceProvider),
    ref.watch(localBackupStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
