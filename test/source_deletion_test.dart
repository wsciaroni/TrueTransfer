import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:dart_smb2/dart_smb2.dart';
import 'package:truetransfer/services/smb_service.dart';
import 'package:truetransfer/services/smb_file_transfer.dart';

/// A minimal fake SMB service for source-deletion tests.
class DeletionTestSmbService implements SmbService {
  @override
  bool isConnected = true;

  final Map<String, Uint8List> files = {};
  final Set<String> directories = {};

  @override
  Future<void> connect({
    required String host,
    required String share,
    String? user,
    String? password,
    String? domain,
  }) async {
    isConnected = true;
  }

  @override
  Future<void> disconnect() async {
    isConnected = false;
  }

  @override
  Future<bool> exists(String path) async =>
      files.containsKey(path) || directories.contains(path);

  @override
  Future<void> createDirectory(String path) async {
    directories.add(path);
  }

  @override
  Future<int> fileSize(String path) async {
    if (!files.containsKey(path)) throw Exception('File not found: $path');
    return files[path]!.length;
  }

  @override
  Future<void> deleteFile(String path) async {
    files.remove(path);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    if (!files.containsKey(oldPath)) {
      throw Exception('File not found: $oldPath');
    }
    files[newPath] = files.remove(oldPath)!;
  }

  @override
  Future<void> writeFileRange(
    String path,
    Uint8List data, {
    int offset = 0,
  }) async {
    final currentData = files[path] ?? Uint8List(0);
    final newLength = offset + data.length > currentData.length
        ? offset + data.length
        : currentData.length;
    final updatedData = Uint8List(newLength);
    updatedData.setRange(0, currentData.length, currentData);
    updatedData.setRange(offset, offset + data.length, data);
    files[path] = updatedData;
  }

  @override
  Future<Uint8List> readFileRange(
    String path, {
    int offset = 0,
    required int length,
  }) async {
    if (!files.containsKey(path)) throw Exception('File not found: $path');
    final fileData = files[path]!;
    final actualLength = offset + length > fileData.length
        ? fileData.length - offset
        : length;
    if (actualLength <= 0) return Uint8List(0);
    return Uint8List.sublistView(fileData, offset, offset + actualLength);
  }

  @override
  Future<List<Smb2DirEntry>> listDirectory(String path) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late File localFile;
  late DeletionTestSmbService fakeSmb;
  late SmbFileTransfer fileTransfer;

  final String fileContent = 'Source deletion test content for TrueTransfer';
  final Uint8List fileBytes = Uint8List.fromList(fileContent.codeUnits);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('truetransfer_deletion_test');
    localFile = File('${tempDir.path}/source_file.txt');
    localFile.writeAsBytesSync(fileBytes);

    fakeSmb = DeletionTestSmbService()..isConnected = true;
    fileTransfer = SmbFileTransfer(fakeSmb);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Source File Deletion Tests', () {
    test(
      'deleteSource=true with no sourceIdentifier should delete local file',
      () async {
        // Pre-condition: local file exists
        expect(localFile.existsSync(), isTrue);

        await fileTransfer.transferFile(
          localPath: localFile.path,
          remotePath: 'backup/source_file.txt',
          onProgress: (transferred, total) {},
          checkCancelled: () => false,
          checkPaused: () => false,
          deleteSource: true,
          sourceIdentifier: null,
        );

        // Remote file should exist
        expect(fakeSmb.files.containsKey('backup/source_file.txt'), isTrue);
        // Local file MUST be deleted
        expect(localFile.existsSync(), isFalse);
      },
    );

    test(
      'deleteSource=true with content URI where native deletion FAILS should throw, not silently succeed',
      () async {
        // Simulate the Android MethodChannel returning false (deletion failed)
        const channel = MethodChannel('com.example.truetransfer/file_ops');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              // Simulate native side saying "I could not delete the file"
              return false;
            });

        try {
          // Pre-condition: local file exists
          expect(localFile.existsSync(), isTrue);

          // BUG DEMONSTRATION: transferFile completes without error even
          // though PlatformFileOps.deleteOriginalFile returned false.
          // The original source file (identified by the content URI)
          // was NOT deleted, but the code ignores the failure.
          //
          // After the fix, this should throw an exception indicating
          // that the source file could not be deleted.
          expect(
            () => fileTransfer.transferFile(
              localPath: localFile.path,
              remotePath: 'backup/source_file.txt',
              onProgress: (transferred, total) {},
              checkCancelled: () => false,
              checkPaused: () => false,
              deleteSource: true,
              sourceIdentifier: 'content://media/external/file/999',
            ),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                contains('delete'),
              ),
            ),
          );
        } finally {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        }
      },
    );

    test(
      'deleteSource=true with content URI where native deletion SUCCEEDS should delete local file',
      () async {
        // Simulate the Android MethodChannel returning true (deletion succeeded)
        const channel = MethodChannel('com.example.truetransfer/file_ops');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              return true;
            });

        try {
          expect(localFile.existsSync(), isTrue);

          await fileTransfer.transferFile(
            localPath: localFile.path,
            remotePath: 'backup/source_file.txt',
            onProgress: (transferred, total) {},
            checkCancelled: () => false,
            checkPaused: () => false,
            deleteSource: true,
            sourceIdentifier: 'content://media/external/file/999',
          );

          // Remote file should exist
          expect(fakeSmb.files.containsKey('backup/source_file.txt'), isTrue);
          // Local cached file should also be deleted
          expect(localFile.existsSync(), isFalse);
        } finally {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        }
      },
    );

    test(
      'deleteSource=true with content URI where MethodChannel throws should throw, not silently succeed',
      () async {
        // Simulate the Android MethodChannel throwing an error
        const channel = MethodChannel('com.example.truetransfer/file_ops');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              throw PlatformException(
                code: 'DELETE_FAILED',
                message: 'SecurityException: Permission denied',
              );
            });

        try {
          expect(localFile.existsSync(), isTrue);

          // After the fix, this should throw when native deletion fails
          expect(
            () => fileTransfer.transferFile(
              localPath: localFile.path,
              remotePath: 'backup/source_file.txt',
              onProgress: (transferred, total) {},
              checkCancelled: () => false,
              checkPaused: () => false,
              deleteSource: true,
              sourceIdentifier: 'content://media/external/file/999',
            ),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                contains('delete'),
              ),
            ),
          );
        } finally {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        }
      },
    );

    test(
      'deleteSource=false should preserve source file regardless of sourceIdentifier',
      () async {
        expect(localFile.existsSync(), isTrue);

        await fileTransfer.transferFile(
          localPath: localFile.path,
          remotePath: 'backup/source_file.txt',
          onProgress: (transferred, total) {},
          checkCancelled: () => false,
          checkPaused: () => false,
          deleteSource: false,
          sourceIdentifier: 'content://media/external/file/999',
        );

        // Remote file should exist
        expect(fakeSmb.files.containsKey('backup/source_file.txt'), isTrue);
        // Local file should still exist
        expect(localFile.existsSync(), isTrue);
      },
    );
  });
}
