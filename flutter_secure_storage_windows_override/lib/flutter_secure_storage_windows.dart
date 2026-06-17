import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

class FlutterSecureStorageWindows extends FlutterSecureStoragePlatform {
  final DpapiJsonFileMapStorage _storage = DpapiJsonFileMapStorage();

  /// Registers this plugin.
  static void registerWith() {
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageWindows();
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    final map = await _storage.load(options);
    return map.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    final map = await _storage.load(options);
    final initialSize = map.length;
    map.remove(key);
    if (map.length != initialSize) {
      await _storage.save(map, options);
    }
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    await _storage.clear(options);
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    final map = await _storage.load(options);
    return map[key];
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    return await _storage.load(options);
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    final map = await _storage.load(options);
    map[key] = value;
    await _storage.save(map, options);
  }
}

const String encryptedJsonFileName = 'flutter_secure_storage.dat';

class DpapiJsonFileMapStorage {
  DpapiJsonFileMapStorage();

  FutureOr<String> _getJsonFilePath() async {
    final appDataDirectory = await getApplicationSupportDirectory();
    return path.canonicalize(
      path.join(
        appDataDirectory.path,
        encryptedJsonFileName,
      ),
    );
  }

  FutureOr<Map<String, String>> load(Map<String, String> options) async {
    final file = File(await _getJsonFilePath());
    if (!(await file.exists())) {
      return {};
    }

    late final Uint8List encryptedText;
    try {
      encryptedText = await file.readAsBytes();
    } on FileSystemException catch (e) {
      debugPrint('Reading file has been deleted by another process. $e');
      return {};
    }

    late final String plainText;
    try {
      plainText = using((alloc) {
        final Pointer<Uint8> pEncryptedText = alloc(encryptedText.length);
        pEncryptedText
            .asTypedList(encryptedText.length)
            .setAll(0, encryptedText);

        final Pointer<CRYPT_INTEGER_BLOB> encryptedTextBlob =
            alloc.allocate(sizeOf<CRYPT_INTEGER_BLOB>());
        encryptedTextBlob.ref.cbData = encryptedText.length;
        encryptedTextBlob.ref.pbData = pEncryptedText;

        final Pointer<CRYPT_INTEGER_BLOB> plainTextBlob =
            alloc.allocate(sizeOf<CRYPT_INTEGER_BLOB>());
        if (CryptUnprotectData(
              encryptedTextBlob,
              nullptr,
              nullptr,
              nullptr,
              nullptr,
              0,
              plainTextBlob,
            ) ==
            0) {
          throw WindowsException(
            GetLastError(),
            message: 'Failure on CryptUnprotectData()',
          );
        }

        if (plainTextBlob.ref.pbData.address == NULL) {
          throw WindowsException(
            ERROR_OUTOFMEMORY,
            message: 'Failure on CryptUnprotectData()',
          );
        }

        try {
          return utf8.decoder.convert(
            plainTextBlob.ref.pbData.asTypedList(plainTextBlob.ref.cbData),
          );
        } finally {
          if (plainTextBlob.ref.pbData.address != NULL) {
            LocalFree(plainTextBlob.ref.pbData);
          }
        }
      });
    } catch (e) {
      debugPrint('Failed to decrypt data: $e. Deleting corrupt file: ${file.path}');
      if (await file.exists()) {
        await file.delete();
      }
      return {};
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(plainText);
    } catch (e) {
      debugPrint('Failed to parse JSON: $e. Deleting corrupt file: ${file.path}');
      if (await file.exists()) {
        await file.delete();
      }
      return {};
    }

    if (decoded is! Map) {
      debugPrint('Failed to parse JSON: Not an object. Deleting corrupt file: ${file.path}');
      if (await file.exists()) {
        await file.delete();
      }
      return {};
    }

    return {
      for (final e
          in decoded.entries.where((x) => x.key is String && x.value is String))
        e.key as String: e.value as String,
    };
  }

  FutureOr<void> save(
    Map<String, String> data,
    Map<String, String> options,
  ) async {
    final file = File(await _getJsonFilePath());
    final json = jsonEncode(data);
    final plainText = utf8.encode(json);

    await using((alloc) async {
      final Pointer<Uint8> pPlainText = alloc(plainText.length);
      pPlainText.asTypedList(plainText.length).setAll(0, plainText);

      final Pointer<CRYPT_INTEGER_BLOB> plainTextBlob =
          alloc.allocate(sizeOf<CRYPT_INTEGER_BLOB>());
      plainTextBlob.ref.cbData = plainText.length;
      plainTextBlob.ref.pbData = pPlainText;

      final Pointer<CRYPT_INTEGER_BLOB> encryptedTextBlob =
          alloc.allocate(sizeOf<CRYPT_INTEGER_BLOB>());
      if (CryptProtectData(
            plainTextBlob,
            nullptr,
            nullptr,
            nullptr,
            nullptr,
            0,
            encryptedTextBlob,
          ) ==
          0) {
        throw WindowsException(
          GetLastError(),
          message: 'Failure on CryptProtectData()',
        );
      }

      if (encryptedTextBlob.ref.pbData.address == NULL) {
        throw WindowsException(
          ERROR_OUTOFMEMORY,
          message: 'Failure on CryptProtectData()',
        );
      }

      try {
        final encryptedText = encryptedTextBlob.ref.pbData
            .asTypedList(encryptedTextBlob.ref.cbData);

        while (true) {
          try {
            await (await file.create(recursive: true))
                .writeAsBytes(encryptedText, flush: true);
            break;
          } catch (e) {
            debugPrint('File write failed, retrying... $e');
          }
        }
      } finally {
        if (encryptedTextBlob.ref.pbData.address != NULL) {
          LocalFree(encryptedTextBlob.ref.pbData);
        }
      }
    });
  }

  FutureOr<void> clear(Map<String, String> options) async {
    final file = File(await _getJsonFilePath());
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (e) {
        debugPrint('Deleting file failed. $e');
      }
    }
  }
}
