import 'dart:io';

/// Десктоп: доступны окно, трей и автозапуск (window_manager, tray_manager,
/// launch_at_startup). На Android эти плагины не регистрируются, и любой
/// вызов к ним закончится `MissingPluginException`.
bool get isDesktopPlatform =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// macOS: сочетания клавиш — через Cmd, а не Ctrl.
bool get isMacOSPlatform => Platform.isMacOS;

/// Название ОС для подписей в настройках.
String get platformDisplayName {
  if (Platform.isMacOS) return 'macOS';
  if (Platform.isAndroid) return 'Android';
  if (Platform.isLinux) return 'Linux';
  return 'Windows';
}
