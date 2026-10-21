import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';

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

  /// Инсталлятор для Windows: сначала *setup*.exe, затем любой .exe, затем .zip.
  ReleaseAsset? get installerAsset {
    final exes = assets.where((a) => a.isExe).toList();
    for (final asset in exes) {
      if (asset.name.toLowerCase().contains('setup')) return asset;
    }
    if (exes.isNotEmpty) return exes.first;
    for (final asset in assets) {
      if (asset.isZip) return asset;
    }
    return null;
  }

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

  /// Скачивает инсталлятор потоком, запускает его отдельно и завершает
  /// приложение, чтобы снять блокировки с файлов в каталоге установки.
  Future<void> downloadAndInstallUpdate(
    Release release,
    void Function(double progress) onProgress,
  ) async {
    if (!Platform.isWindows) {
      throw const UpdateException(
          'Автоустановка поддерживается только на Windows');
    }
    final asset = release.installerAsset;
    if (asset == null) {
      throw const UpdateException('В релизе нет файла установщика');
    }

    final file = await _download(asset, onProgress);
    final installer =
        asset.isZip ? await _extractInstaller(file) : file;

    await _launchInstaller(installer);
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

  /// Распаковывает zip штатным PowerShell и ищет внутри .exe-инсталлятор.
  Future<File> _extractInstaller(File zip) async {
    final outDir = Directory(p.join(zip.parent.path, 'extracted'));
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      'Expand-Archive -LiteralPath "${zip.path}" '
          '-DestinationPath "${outDir.path}" -Force',
    ]);
    if (result.exitCode != 0) {
      throw const UpdateException('Не удалось распаковать архив обновления');
    }

    final exes = await outDir
        .list(recursive: true)
        .where((e) => e is File && e.path.toLowerCase().endsWith('.exe'))
        .cast<File>()
        .toList();
    if (exes.isEmpty) {
      throw const UpdateException('В архиве нет установщика (.exe)');
    }
    return exes.firstWhere(
      (f) => p.basename(f.path).toLowerCase().contains('setup'),
      orElse: () => exes.first,
    );
  }

  Future<void> _launchInstaller(File installer) async {
    // Inno Setup в тихом режиме; [Run] в installer.iss перезапускает приложение.
    const args = [
      '/SILENT',
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
