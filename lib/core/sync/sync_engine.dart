import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../features/finance/data/repositories/finance_repository.dart';
import '../../features/finance/domain/finance_calculations.dart';
import '../database/app_database.dart';
import 'sync_payload.dart';
import 'sync_table_adapter.dart';

export 'sync_table_adapter.dart' show MergeResult;

/// [TaskEntity.fromJson] с поддержкой снимков старых версий, где ещё нет
/// полей напоминания (`reminderAt` → `null`, `isReminderSent` → `false`).
TaskEntity taskFromSyncJson(
  Map<String, dynamic> json, {
  ValueSerializer? serializer,
}) {
  return TaskEntity.fromJson(
    {...json, 'isReminderSent': json['isReminderSent'] ?? false},
    serializer: serializer,
  );
}

/// [FinanceAccountEntity.fromJson] с поддержкой снимков старых версий, где
/// ещё нет полей плавающего графика (`isFlexibleSchedule` → `false`,
/// `nextPaymentDate` / `nextPaymentAmount` → `null`) и начального остатка
/// (`initialBalance` → `0`; при слиянии он заранее выводится из операций
/// снимка, см. [withDerivedInitialBalances]).
FinanceAccountEntity financeAccountFromSyncJson(
  Map<String, dynamic> json, {
  ValueSerializer? serializer,
}) {
  return FinanceAccountEntity.fromJson(
    {
      ...json,
      'isFlexibleSchedule': json['isFlexibleSchedule'] ?? false,
      'initialBalance': json['initialBalance'] ?? 0.0,
    },
    serializer: serializer,
  );
}

/// Снимок версии до v1.8.8 не содержит `initialBalance`. Его баланс был
/// согласован с операциями того же снимка, поэтому начальный остаток
/// выводится из них — иначе пересчёт после слияния учёл бы операции дважды.
Map<String, List<Map<String, dynamic>>> withDerivedInitialBalances(
  Map<String, List<Map<String, dynamic>>> tables,
) {
  final accounts = tables['finance_accounts'];
  if (accounts == null ||
      accounts.every((a) => a.containsKey('initialBalance'))) {
    return tables;
  }
  final transactions = [
    for (final t in tables['finance_transactions'] ?? const [])
      FinanceTransactionEntity.fromJson(t, serializer: syncValueSerializer),
  ];
  return {
    ...tables,
    'finance_accounts': [
      for (final a in accounts)
        if (a.containsKey('initialBalance'))
          a
        else
          {
            ...a,
            'initialBalance': roundMoney(initialBalanceFor(
              kind: (a['kind'] as num?)?.toInt() ?? 0,
              balance: (a['balance'] as num?)?.toDouble() ?? 0,
              flow: accountMoneyFlow(a['id'] as String, transactions),
            )),
          },
    ],
  };
}

/// [ObligationEntity.fromJson] с поддержкой снимков старых версий, где ещё
/// нет полей плавающей суммы (`isVariableAmount` → `false`,
/// `estimatedAmount` / `accountId` → `null`).
ObligationEntity obligationFromSyncJson(
  Map<String, dynamic> json, {
  ValueSerializer? serializer,
}) {
  return ObligationEntity.fromJson(
    {...json, 'isVariableAmount': json['isVariableAmount'] ?? false},
    serializer: serializer,
  );
}

/// Движок построчного слияния локальной БД с облачным снимком
/// (Last-Write-Wins по `updatedAt` / `deletedAt`).
///
/// * Идентификатор записи — существующий `id` (UUID v4).
/// * Soft-delete (`deletedAt != null`) входит в снимок и распространяется.
/// * `app_settings` не синхронизируется — это настройки конкретного устройства.
class SyncEngine {
  static const String deviceIdSettingKey = 'sync_device_id';

  final AppDatabase _db;
  final DateTime Function() _now;

  SyncEngine(this._db, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Порядок важен: сначала родительские таблицы, затем зависимые.
  late final List<SyncTable> _tables = [
    DriftSyncTable(
      name: 'categories',
      db: _db,
      table: _db.categories,
      fromJson: Category.fromJson,
    ),
    DriftSyncTable(
      name: 'finance_categories',
      db: _db,
      table: _db.financeCategories,
      fromJson: FinanceCategoryEntity.fromJson,
    ),
    DriftSyncTable(
      name: 'finance_accounts',
      db: _db,
      table: _db.financeAccounts,
      fromJson: financeAccountFromSyncJson,
    ),
    DriftSyncTable(
      name: 'habits',
      db: _db,
      table: _db.habits,
      fromJson: HabitEntity.fromJson,
    ),
    DriftSyncTable(
      name: 'challenges',
      db: _db,
      table: _db.challenges,
      fromJson: ChallengeEntity.fromJson,
    ),
    DriftSyncTable(
      name: 'tasks',
      db: _db,
      table: _db.tasks,
      fromJson: taskFromSyncJson,
    ),
    DriftSyncTable(
      name: 'habit_logs',
      db: _db,
      table: _db.habitLogs,
      fromJson: HabitLogEntity.fromJson,
    ),
    DriftSyncTable(
      name: 'challenge_habits',
      db: _db,
      table: _db.challengeHabits,
      fromJson: ChallengeHabitEntity.fromJson,
    ),
    DriftSyncTable(
      name: 'obligations',
      db: _db,
      table: _db.obligations,
      fromJson: obligationFromSyncJson,
    ),
    DriftSyncTable(
      name: 'finance_transactions',
      db: _db,
      table: _db.financeTransactions,
      fromJson: FinanceTransactionEntity.fromJson,
    ),
    DriftSyncTable(
      name: 'routine_items',
      db: _db,
      table: _db.routineItems,
      fromJson: RoutineItemEntity.fromJson,
    ),
    DriftSyncTable(
      name: 'routine_daily_logs',
      db: _db,
      table: _db.routineDailyLogs,
      fromJson: RoutineDailyLogEntity.fromJson,
    ),
    DriftSyncTable(
      name: 'notes',
      db: _db,
      table: _db.notes,
      fromJson: NoteEntity.fromJson,
    ),
  ];

  /// Имена синхронизируемых таблиц.
  List<String> get tableNames => [for (final t in _tables) t.name];

  /// Поток событий «в синхронизируемых таблицах что-то изменилось».
  Stream<void> watchLocalChanges() {
    return _db
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            for (final t in _tables) t.tableInfo,
          ]),
        )
        .map((_) {});
  }

  /// Стабильный идентификатор этого устройства (создаётся при первом вызове).
  Future<String> getDeviceId() async {
    final existing = await (_db.select(_db.appSettings)
          ..where((s) => s.settingKey.equals(deviceIdSettingKey)))
        .getSingleOrNull();
    if (existing != null) return existing.settingValue;

    final id = const Uuid().v4();
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            settingKey: deviceIdSettingKey,
            settingValue: id,
          ),
        );
    return id;
  }

  /// Выгружает текущее состояние локальных таблиц (включая soft-deleted).
  Future<SyncPayload> exportToSyncPayload() async {
    final deviceId = await getDeviceId();
    final tables = <String, List<Map<String, dynamic>>>{};
    for (final table in _tables) {
      tables[table.name] = await table.exportRows();
    }
    return SyncPayload(
      lastSyncTimestamp: _now().toUtc(),
      deviceId: deviceId,
      tables: tables,
    );
  }

  /// Построчно сливает [remotePayload] в локальную БД (Last-Write-Wins).
  ///
  /// Балансы продуктов затем пересчитываются из операций в той же
  /// транзакции: запись счёта сливается целиком, и без пересчёта операции,
  /// добавленные параллельно на другом устройстве, потерялись бы в балансе.
  Future<MergeResult> mergeFromSyncPayload(SyncPayload remotePayload) {
    if (remotePayload.version > SyncPayload.currentVersion) {
      throw SyncFormatException(
        'Неподдерживаемая версия файла синхронизации: ${remotePayload.version}',
      );
    }
    final tables = withDerivedInitialBalances(remotePayload.tables);
    return _db.transaction(() async {
      var result = const MergeResult();
      for (final table in _tables) {
        final rows = tables[table.name];
        if (rows == null || rows.isEmpty) continue;
        result += await table.merge(rows);
      }
      await FinanceRepository(_db)
          .recalculateBalances(_touchedAccounts(tables));
      return result;
    });
  }

  /// Продукты, чьи записи или операции пришли в снимке.
  static Set<String> _touchedAccounts(
    Map<String, List<Map<String, dynamic>>> tables,
  ) {
    return {
      for (final a in tables['finance_accounts'] ?? const []) a['id'] as String,
      for (final t in tables['finance_transactions'] ?? const []) ...[
        t['accountId'] as String,
        ?t['targetAccountId'] as String?,
      ],
    };
  }
}

