import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

/// Аргумент командной строки автозапуска: стартовать свёрнутым в трей.
/// Тот же флаг проверяет нативный раннер (windows/runner/utils.h).
const String launchMinimizedArg = '--minimized';

/// Автозапуск с Windows: запись `LifeOS` в
/// `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
class AutostartService {
  static const String appName = 'LifeOS';

  static bool _initialized = false;

  /// Автозапуск доступен: платформа Windows и [setup] вызван в `main`.
  static bool get isAvailable => _initialized;

  /// Задаёт имя записи и команду запуска. Вызывается один раз в `main`.
  static void setup() {
    if (!Platform.isWindows) return;
    launchAtStartup.setup(
      appName: appName,
      // Путь в кавычках: каталог установки содержит пробелы («Life OS»).
      appPath: '"${Platform.resolvedExecutable}"',
      args: const [launchMinimizedArg],
    );
    _initialized = true;
  }

  /// Есть ли в реестре запись, указывающая на текущий exe.
  Future<bool> isEnabled() async {
    if (!_initialized) return false;
    try {
      return await launchAtStartup.isEnabled();
    } catch (e) {
      debugPrint('AutostartService: не удалось прочитать реестр: $e');
      return false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (!_initialized) return;
    if (enabled) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }
}

final autostartServiceProvider =
    Provider<AutostartService>((ref) => AutostartService());
