import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';

import 'tray_service.dart';

/// Параметры источника обновлений. Переопределяются через --dart-define.
class UpdateConfig {
  static const String owner =
      String.fromEnvironment('UPDATE_REPO_OWNER', defaultValue: 'Kerzachek');
  static const String repo =
      String.fromEnvironment('UPDATE_REPO_NAME', defaultValue: 'life-os');

  /// Токен нужен только для приватного репозитория (scope: contents:read).
  static const String token = String.fromEnvironment('GITHUB_UPDATE_TOKEN');
}

class UpdateException implements Exception {
  final String message;

  const UpdateException(this.message);

  @override
  String toString() => message;
}

/// Файл, прикреплённый к GitHub Release.
class ReleaseAsset {
  final String name;
  final int size;
  final String browserDownloadUrl;

  /// API-адрес ассета: работает и для приватных репозиториев.
  final String apiUrl;

  const ReleaseAsset({
    required this.name,
    required this.size,
    required this.browserDownloadUrl,
    required this.apiUrl,
  });

  bool get isExe => name.toLowerCase().endsWith('.exe');
  bool get isZip => name.toLowerCase().endsWith('.zip');
  bool get isApk => name.toLowerCase().endsWith('.apk');

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) => ReleaseAsset(
        name: json['name'] as String? ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        browserDownloadUrl: json['browser_download_url'] as String? ?? '',
        apiUrl: json['url'] as String? ?? '',
      );
}

/// DTO ответа /repos/{owner}/{repo}/releases/latest.
class Release {
  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;

  const Release({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
    required this.assets,
  });

  /// Версия из tag_name (`v1.2.3` → `1.2.3`); null, если тег не semver.
  Version? get version => parseVersion(tagName);

  /// Файл обновления для текущей платформы.
  ReleaseAsset? get installerAsset {
    if (Platform.isAndroid) return androidAsset;
    return Platform.isMacOS ? macosAsset : windowsAsset;
  }

  /// APK для Android: `LifeOS-Android.apk`, затем любой .apk.
  ReleaseAsset? get androidAsset {
    final apks = assets.where((a) => a.isApk).toList();
    for (final asset in apks) {
      if (asset.name == androidAssetName) return asset;
    }
    return apks.isNotEmpty ? apks.first : null;
  }

  /// Инсталлятор для Windows: `LifeOS-Setup.exe`, затем *setup*.exe, затем любой .exe.
  ReleaseAsset? get windowsAsset {
    final exes = assets.where((a) => a.isExe).toList();
    for (final asset in exes) {
      if (asset.name == windowsAssetName) return asset;
    }
    for (final asset in exes) {
      if (asset.name.toLowerCase().contains('setup')) return asset;
    }
    return exes.isNotEmpty ? exes.first : null;
  }

  /// Архив бандла для macOS: `LifeOS-macOS.zip`, затем любой *macos*.zip.
  ReleaseAsset? get macosAsset {
    final zips = assets.where((a) => a.isZip).toList();
    for (final asset in zips) {
      if (asset.name == macosAssetName) return asset;
    }
    for (final asset in zips) {
      if (asset.name.toLowerCase().contains('macos')) return asset;
    }
    return null;
  }

  static const String windowsAssetName = 'LifeOS-Setup.exe';
  static const String macosAssetName = 'LifeOS-macOS.zip';
  static const String androidAssetName = 'LifeOS-Android.apk';

  factory Release.fromJson(Map<String, dynamic> json) => Release(
        tagName: json['tag_name'] as String? ?? '',
        name: json['name'] as String? ?? '',
        body: json['body'] as String? ?? '',
        htmlUrl: json['html_url'] as String? ?? '',
        publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
        assets: [
          for (final a in json['assets'] as List<dynamic>? ?? const [])
            ReleaseAsset.fromJson(a as Map<String, dynamic>),
        ],
      );
}

/// Разбирает версию, допуская префикс `v`. Build-часть (`+1`) отбрасывается,
/// чтобы `1.0.0+1` из pubspec совпадала с тегом `v1.0.0`.
Version? parseVersion(String raw) {
  var value = raw.trim();
  if (value.startsWith('v') || value.startsWith('V')) {
    value = value.substring(1);
  }
  try {
    final v = Version.parse(value);
    final pre = v.preRelease.join('.');
    return Version(v.major, v.minor, v.patch, pre: pre.isEmpty ? null : pre);
  } on FormatException {
    return null;
  }
}

class UpdateService {
  final http.Client _client;
  final Future<String> Function() _currentVersionLoader;

  UpdateService({
    http.Client? client,
    Future<String> Function()? currentVersionLoader,
  })  : _client = client ?? http.Client(),
        _currentVersionLoader = currentVersionLoader ??
            (() async => (await PackageInfo.fromPlatform()).version);

  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'LifeOS-Updater',
        if (UpdateConfig.token.isNotEmpty)
          'Authorization': 'Bearer ${UpdateConfig.token}',
      };

  Future<String> currentVersion() => _currentVersionLoader();

  /// Возвращает релиз, если он новее текущей версии, иначе null.
  Future<Release?> checkForUpdates() async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/${UpdateConfig.owner}/${UpdateConfig.repo}/releases/latest',
    );

    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const UpdateException('GitHub не ответил вовремя');
    } on SocketException {
      throw const UpdateException('Нет подключения к интернету');
    }

    // 404: релизов нет (или репозиторий приватный и токен не задан).
    if (response.statusCode == 404) return null;
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw const UpdateException(
          'Превышен лимит запросов к GitHub, попробуйте позже');
    }
    if (response.statusCode != 200) {
      throw UpdateException('Ошибка GitHub API: ${response.statusCode}');
    }

    final release = Release.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    final latest = release.version;
    final current = parseVersion(await currentVersion());
    if (latest == null || current == null) return null;
    return latest > current ? release : null;
  }

  /// Скачивает обновление потоком, запускает установку отдельным процессом
  /// и завершает приложение, чтобы снять блокировки с файлов.
  ///
  /// Windows: тихий запуск `LifeOS-Setup.exe`.
  /// macOS: замена текущего `LifeOS.app` содержимым `LifeOS-macOS.zip`
  /// и перезапуск.
  /// Android: открытие `LifeOS-Android.apk` системным установщиком; приложение
  /// не завершается — установщик сам закроет его при замене пакета.
  Future<void> downloadAndInstallUpdate(
    Release release,
    void Function(double progress) onProgress,
  ) async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isAndroid) {
      throw const UpdateException(
          'Автоустановка поддерживается только на Windows, macOS и Android');
    }
    final asset = release.installerAsset;
    if (asset == null) {
      throw UpdateException(Platform.isMacOS
          ? 'В релизе нет архива для macOS'
          : Platform.isAndroid
              ? 'В релизе нет APK для Android'
              : 'В релизе нет файла установщика');
    }

    if (Platform.isAndroid) {
      final apk = await _download(asset, onProgress);
      await _openAndroidInstaller(apk);
      return;
    }

    if (Platform.isMacOS) {
      // Проверяем права до загрузки, чтобы не качать впустую.
      final bundle = _currentMacAppBundle();
      final file = await _download(asset, onProgress);
      final newApp = await _extractMacApp(file);
      await _launchMacReplacer(newApp, bundle);
    } else {
      final installer = await _download(asset, onProgress);
      await _launchInstaller(installer);
    }
    // exit(0), а не закрытие окна: крестик перехвачен для сворачивания в трей
    // (setPreventClose), и окно не должно пережить запуск установщика.
    TrayService.removeTrayIcon();
    exit(0);
  }

  Future<File> _download(
    ReleaseAsset asset,
    void Function(double progress) onProgress,
  ) async {
    final tempRoot = await getTemporaryDirectory();
    final dir = Directory(p.join(tempRoot.path, 'lifeos_update'));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, asset.name));

    // Для приватного репозитория качаем через API с octet-stream.
    final usesApi = UpdateConfig.token.isNotEmpty && asset.apiUrl.isNotEmpty;
    final request = http.Request(
      'GET',
      Uri.parse(usesApi ? asset.apiUrl : asset.browserDownloadUrl),
    )..headers.addAll({
        ..._headers,
        if (usesApi) 'Accept': 'application/octet-stream',
      });

    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw UpdateException('Не удалось скачать файл: ${response.statusCode}');
    }

    final total = response.contentLength ?? asset.size;
    var received = 0;
    final sink = target.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress((received / total).clamp(0.0, 1.0));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (total > 0 && received != total) {
      throw const UpdateException('Загрузка прервана, файл повреждён');
    }
    onProgress(1.0);
    return target;
  }

  /// Путь к запущенному `.app` (…/LifeOS.app/Contents/MacOS/LifeOS → …/LifeOS.app)
  /// с проверкой, что его можно заменить.
  Directory _currentMacAppBundle() {
    final bundle =
        p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable)));
    if (!bundle.endsWith('.app')) {
      throw const UpdateException('Не удалось определить путь к приложению');
    }
    // Gatekeeper запускает неподписанные приложения из «Загрузок»
    // с копии только для чтения.
    if (bundle.contains('/AppTranslocation/')) {
      throw const UpdateException(
          'Переместите LifeOS в папку «Программы» и запустите снова');
    }
    final probe = File(p.join(p.dirname(bundle), '.lifeos_update_probe'));
    try {
      probe.writeAsStringSync('');
      probe.deleteSync();
    } on FileSystemException {
      throw UpdateException(
          'Нет прав на запись в ${p.dirname(bundle)}, обновите вручную');
    }
    return Directory(bundle);
  }

  /// Распаковывает архив через `ditto` (сохраняет симлинки фреймворков)
  /// и ищет внутри `.app`.
  Future<Directory> _extractMacApp(File zip) async {
    final outDir = Directory(p.join(zip.parent.path, 'extracted'));
    final result = await Process.run(
      '/usr/bin/ditto',
      ['-x', '-k', zip.path, outDir.path],
    );
    if (result.exitCode != 0) {
      throw const UpdateException('Не удалось распаковать архив обновления');
    }

    final apps = await outDir
        .list()
        .where((e) => e is Directory && e.path.endsWith('.app'))
        .cast<Directory>()
        .toList();
    if (apps.isEmpty) {
      throw const UpdateException('В архиве нет приложения (.app)');
    }
    return apps.firstWhere(
      (d) => p.basename(d.path) == 'LifeOS.app',
      orElse: () => apps.first,
    );
  }

  /// Скрипт ждёт выхода приложения, подменяет бандл (с откатом при ошибке),
  /// снимает карантин и запускает новую версию.
  static const String _macReplaceScript = r'''
PID="$1"; NEW="$2"; TARGET="$3"
while kill -0 "$PID" 2>/dev/null; do sleep 0.5; done
rm -rf "$TARGET.old"
if mv "$TARGET" "$TARGET.old"; then
  if /usr/bin/ditto "$NEW" "$TARGET"; then
    rm -rf "$TARGET.old"
  else
    rm -rf "$TARGET"
    mv "$TARGET.old" "$TARGET"
  fi
fi
/usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
/usr/bin/open "$TARGET"
''';

  Future<void> _launchMacReplacer(Directory newApp, Directory target) async {
    final script = File(p.join(newApp.parent.parent.path, 'replace.sh'));
    // Исходник может быть с CRLF (Windows-checkout), а sh не терпит \r.
    await script.writeAsString(_macReplaceScript.replaceAll('\r\n', '\n'));
    try {
      await Process.start(
        '/bin/sh',
        [script.path, '$pid', newApp.path, target.path],
        mode: ProcessStartMode.detached,
      );
    } on ProcessException catch (e) {
      throw UpdateException('Не удалось запустить обновление: ${e.message}');
    }
  }

  /// Передаёт APK системному установщику через FileProvider плагина.
  /// Разрешение «Установка неизвестных приложений» Android запросит сам.
  Future<void> _openAndroidInstaller(File apk) async {
    final result = await OpenFilex.open(
      apk.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw UpdateException('Не удалось открыть установщик: ${result.message}');
    }
  }

  Future<void> _launchInstaller(File installer) async {
    // Inno Setup в тихом режиме; [Run] в installer.iss перезапускает приложение.
    const args = [
      '/VERYSILENT',
      '/SP-',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
    ];

    try {
      await Process.start(
        installer.path,
        args,
        mode: ProcessStartMode.detached,
      );
    } on ProcessException catch (e) {
      throw UpdateException('Не удалось запустить установщик: ${e.message}');
    }
  }
}

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

final currentAppVersionProvider = FutureProvider<String>(
  (ref) => ref.watch(updateServiceProvider).currentVersion(),
);
