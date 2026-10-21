import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/services/update_service.dart';

ReleaseAsset _asset(String name) => ReleaseAsset(
      name: name,
      size: 1,
      browserDownloadUrl: 'https://example.com/$name',
      apiUrl: 'https://api.example.com/$name',
    );

Release _release(List<String> names) => Release(
      tagName: 'v1.4.0',
      name: '',
      body: '',
      htmlUrl: '',
      publishedAt: null,
      assets: [for (final n in names) _asset(n)],
    );

void main() {
  test('каждая платформа берёт свой файл из общего релиза', () {
    final release = _release(['LifeOS-macOS.zip', 'LifeOS-Setup.exe']);
    expect(release.windowsAsset?.name, 'LifeOS-Setup.exe');
    expect(release.macosAsset?.name, 'LifeOS-macOS.zip');
  });

  test('Windows не берёт архив macOS', () {
    final release = _release(['LifeOS-macOS.zip']);
    expect(release.windowsAsset, isNull);
    expect(release.macosAsset?.name, 'LifeOS-macOS.zip');
  });

  test('macOS без своего архива — нет обновления', () {
    final release = _release(['LifeOS-Setup.exe', 'sources.zip']);
    expect(release.macosAsset, isNull);
  });
}
