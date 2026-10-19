import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'sync_payload.dart';
import 'sync_providers.dart';
import 'sync_remote_store.dart';
import 'sync_state.dart';

final googleDriveSyncServiceProvider =
    NotifierProvider<GoogleDriveSyncService, SyncState>(
  GoogleDriveSyncService.new,
);

/// Local-First синхронизация через Google Drive `appDataFolder`.
///
/// Приложение всегда работает с локальной БД; сервис в фоне делает
/// «скачать → слить → выгрузить» (см. [performSync]).
class GoogleDriveSyncService extends Notifier<SyncState> {
  /// Пауза после последнего локального изменения перед синхронизацией.
  static const Duration debounce = Duration(seconds: 5);

  /// Период фоновой синхронизации.
  static const Duration periodicInterval = Duration(minutes: 15);

  Timer? _debounceTimer;
  Timer? _periodicTimer;
  StreamSubscription<void>? _changesSub;
  bool _syncing = false;
  bool _rerun = false;

  @override
  SyncState build() {
    ref.onDispose(_stopTriggers);
    return SyncState(configured: ref.read(syncConfiguredProvider));
  }

  /// Вызывается при старте приложения: восстанавливает сессию и синхронизирует.
  Future<void> start() async {
    if (!state.configured || state.signedIn) return;
    try {
      final restored = await ref.read(syncAuthProvider).restore();
      if (!ref.mounted || !restored) return;
      _onSignedIn();
      await syncNow();
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> signIn() async {
    if (!state.configured || state.isBusy) return;
    state = state.copyWith(activity: SyncActivity.signingIn, clearError: true);
    try {
      final ok = await ref.read(syncAuthProvider).signIn();
      if (!ref.mounted) return;
      if (!ok) {
        state = state.copyWith(activity: SyncActivity.idle);
        return;
      }
      _onSignedIn();
      await syncNow();
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> signOut() async {
    _stopTriggers();
    try {
      await ref.read(syncAuthProvider).signOut();
    } catch (_) {
      // Выход локальный: сетевая ошибка не должна оставлять сессию активной.
    }
    if (!ref.mounted) return;
    state = SyncState(configured: state.configured);
  }

  /// Один цикл синхронизации. Параллельные вызовы схлопываются в один повтор.
  Future<void> syncNow() async {
    if (!state.signedIn) return;
    if (_syncing) {
      _rerun = true;
      return;
    }
    _syncing = true;
    _debounceTimer?.cancel();
    state = state.copyWith(activity: SyncActivity.syncing, clearError: true);
    try {
      final auth = ref.read(syncAuthProvider);
      final engine = ref.read(syncEngineProvider);
      final makeStore = ref.read(syncRemoteStoreFactoryProvider);
      await auth.withClient((client) => performSync(engine, makeStore(client)));
      if (!ref.mounted) return;
      state = state.copyWith(
        activity: SyncActivity.idle,
        lastSyncAt: DateTime.now(),
        offline: false,
        clearError: true,
        accountLabel: auth.accountLabel,
      );
    } catch (e) {
      _fail(e);
    } finally {
      _syncing = false;
    }
    if (_rerun && ref.mounted) {
      _rerun = false;
      await syncNow();
    }
  }

  void _onSignedIn() {
    state = state.copyWith(
      signedIn: true,
      activity: SyncActivity.idle,
      clearError: true,
      accountLabel: ref.read(syncAuthProvider).accountLabel,
    );
    _startTriggers();
  }

  void _startTriggers() {
    _stopTriggers();
    _changesSub = ref.read(syncEngineProvider).watchLocalChanges().listen((_) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounce, syncNow);
    });
    _periodicTimer = Timer.periodic(periodicInterval, (_) => syncNow());
  }

  void _stopTriggers() {
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    _changesSub?.cancel();
    _debounceTimer = null;
    _periodicTimer = null;
    _changesSub = null;
  }

  void _fail(Object error) {
    if (!ref.mounted) return;
    final offline = error is SocketException ||
        error is TimeoutException ||
        error is http.ClientException;
    state = state.copyWith(
      activity: SyncActivity.error,
      offline: offline,
      errorMessage:
          error is SyncFormatException ? error.message : error.toString(),
    );
  }
}
