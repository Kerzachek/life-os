import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Сохранение и выбор локальных файлов через системный диалог.
///
/// Вынесено за интерфейс, чтобы виджеты можно было тестировать без
/// платформенного плагина.
abstract class LocalFileGateway {
  /// Предлагает сохранить [bytes] под именем [fileName].
  /// Возвращает путь (или URI на Android), `null` — пользователь отменил.
  Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String extension,
    String? dialogTitle,
  });

  /// Открывает выбор одного файла с расширением [extension].
  /// Возвращает его содержимое, `null` — пользователь отменил.
  Future<Uint8List?> pickFile({required String extension, String? dialogTitle});
}

class FilePickerGateway implements LocalFileGateway {
  const FilePickerGateway();

  @override
  Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String extension,
    String? dialogTitle,
  }) {
    // На всех платформах плагин сам записывает bytes в выбранный файл
    // (на Android — через Storage Access Framework).
    return FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: bytes,
      lockParentWindow: true,
    );
  }

  @override
  Future<Uint8List?> pickFile({
    required String extension,
    String? dialogTitle,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      // Фильтр по расширению на Android ненадёжен (MIME json есть не у всех
      // провайдеров), поэтому формат проверяется уже при разборе файла.
      type: FileType.any,
      withData: true,
      lockParentWindow: true,
    );
    return result?.files.single.bytes;
  }
}

final localFileGatewayProvider = Provider<LocalFileGateway>(
  (ref) => const FilePickerGateway(),
);
