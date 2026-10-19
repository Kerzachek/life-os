import 'package:home_organizer/core/sync/sync_auth.dart';
import 'package:home_organizer/core/sync/sync_remote_store.dart';
import 'package:http/http.dart' as http;

/// Фейковое облако: один «файл» в памяти.
class FakeRemoteStore implements SyncRemoteStore {
  String? content;
  int downloads = 0;
  int uploads = 0;

  /// Если задан — выбрасывается при каждом обращении (имитация ошибки сети).
  Object? failWith;

  @override
  Future<String?> download() async {
    if (failWith != null) throw failWith!;
    downloads++;
    return content;
  }

  @override
  Future<void> upload(String content) async {
    if (failWith != null) throw failWith!;
    uploads++;
    this.content = content;
  }
}

/// Фейковая авторизация без обращения к Google.
class FakeSyncAuth implements SyncAuth {
  bool hasSession;
  int signInCalls = 0;
  int signOutCalls = 0;

  FakeSyncAuth({this.hasSession = false});

  @override
  String? get accountLabel => hasSession ? 'user@example.com' : null;

  @override
  Future<bool> restore() async => hasSession;

  @override
  Future<bool> signIn() async {
    signInCalls++;
    hasSession = true;
    return true;
  }

  @override
  Future<T> withClient<T>(Future<T> Function(http.Client client) action) async {
    final client = http.Client();
    try {
      return await action(client);
    } finally {
      client.close();
    }
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    hasSession = false;
  }
}
