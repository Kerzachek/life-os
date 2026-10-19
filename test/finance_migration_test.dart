import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/features/finance/domain/finance_category_presets.dart';

void main() {
  test('миграция v3 → v4 создаёт финансовые таблицы и сидирует данные',
      () async {
    final dir = Directory.systemTemp.createTempSync('finance_migration');
    final file = File('${dir.path}/test.sqlite');

    // Имитируем базу версии 3: актуальная схема без финансовых таблиц.
    final old = AppDatabase.forTesting(NativeDatabase(file));
    await old.customSelect('SELECT 1').get(); // создаёт схему v4
    await old.customStatement('PRAGMA foreign_keys = OFF');
    for (final t in [
      'finance_transactions',
      'obligations',
      'finance_categories',
      'finance_accounts',
    ]) {
      await old.customStatement('DROP TABLE $t');
    }
    await old.customStatement('PRAGMA user_version = 3');
    await old.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    try {
      final categories = await db.select(db.financeCategories).get();
      expect(categories.length, financeCategoryPresets.length);
      final accounts = await db.select(db.financeAccounts).get();
      expect(accounts.single.id, defaultFinanceAccountId);
      expect(await db.select(db.financeTransactions).get(), isEmpty);
      expect(await db.select(db.obligations).get(), isEmpty);
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });
}
