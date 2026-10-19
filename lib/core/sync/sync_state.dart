import 'package:intl/intl.dart';

enum SyncActivity { idle, signingIn, syncing, error }

/// Состояние облачной синхронизации для UI.
class SyncState {
  final bool signedIn;
  final SyncActivity activity;
  final DateTime? lastSyncAt;
  final String? errorMessage;
  final bool offline;
  final String? accountLabel;

  /// `false`, если в сборку не переданы OAuth Client ID.
  final bool configured;

  const SyncState({
    this.signedIn = false,
    this.activity = SyncActivity.idle,
    this.lastSyncAt,
    this.errorMessage,
    this.offline = false,
    this.accountLabel,
    this.configured = true,
  });

  bool get isBusy =>
      activity == SyncActivity.syncing || activity == SyncActivity.signingIn;

  /// Короткий статус: «Не подключено», «Синхронизация...»,
  /// «Синхронизировано (12:30)», «Ошибка (офлайн)».
  String get label {
    if (activity == SyncActivity.signingIn) return 'Вход...';
    if (activity == SyncActivity.syncing) return 'Синхронизация...';
    if (activity == SyncActivity.error) {
      return offline ? 'Ошибка (офлайн)' : 'Ошибка синхронизации';
    }
    if (!signedIn) return 'Не подключено';
    final last = lastSyncAt;
    if (last == null) return 'Подключено';
    return 'Синхронизировано (${DateFormat('HH:mm').format(last.toLocal())})';
  }

  SyncState copyWith({
    bool? signedIn,
    SyncActivity? activity,
    DateTime? lastSyncAt,
    String? errorMessage,
    bool clearError = false,
    bool? offline,
    String? accountLabel,
    bool clearAccount = false,
    bool? configured,
  }) {
    return SyncState(
      signedIn: signedIn ?? this.signedIn,
      activity: activity ?? this.activity,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      offline: offline ?? this.offline,
      accountLabel: clearAccount ? null : (accountLabel ?? this.accountLabel),
      configured: configured ?? this.configured,
    );
  }
}
