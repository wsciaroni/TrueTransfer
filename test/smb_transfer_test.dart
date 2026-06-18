import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_smb2/dart_smb2.dart';
import 'package:truetransfer/services/smb_service.dart';
import 'package:truetransfer/services/smb_file_transfer.dart';

class FakeSmbService implements SmbService {
  @override
  bool isConnected = false;

  final Map<String, Uint8List> files = {};
  final Set<String> directories = {};

  bool failOperations = false;
  int operationFailureCount = 0;
  bool corruptOnRead = false;

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
  Future<bool> exists(String path) async {
    _maybeFail();
    return files.containsKey(path) || directories.contains(path);
  }

  @override
  Future<void> createDirectory(String path) async {
    _maybeFail();
    directories.add(path);
  }

  @override
  Future<int> fileSize(String path) async {
    _maybeFail();
    if (!files.containsKey(path)) throw Exception('File not found: $path');
    return files[path]!.length;
  }

  @override
  Future<void> deleteFile(String path) async {
    _maybeFail();
    files.remove(path);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    _maybeFail();
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
    _maybeFail();
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
    _maybeFail();
    if (!files.containsKey(path)) throw Exception('File not found: $path');
    if (corruptOnRead) {
      // Return modified bytes to force a hash mismatch
      return Uint8List.fromList(List.filled(length, 0xFF));
    }
    final fileData = files[path]!;
    final actualLength = offset + length > fileData.length
        ? fileData.length - offset
        : length;
    if (actualLength <= 0) return Uint8List(0);
    return Uint8List.sublistView(fileData, offset, offset + actualLength);
  }

  @override
  Future<List<Smb2DirEntry>> listDirectory(String path) async {
    _maybeFail();
    final List<Smb2DirEntry> results = [];
    final prefix = path.isEmpty ? '' : (path.endsWith('/') ? path : '$path/');

    // Find matching subdirectories in directories
    for (final dir in directories) {
      if (dir.startsWith(prefix) && dir != path) {
        final relative = dir.substring(prefix.length);
        final parts = relative.split('/');
        final name = parts.first;
        if (name.isNotEmpty && !results.any((e) => e.name == name)) {
          results.add(
            Smb2DirEntry(
              name: name,
              stat: Smb2Stat(
                type: Smb2FileType.directory,
                size: 0,
                modified: DateTime.now(),
                created: DateTime.now(),
              ),
            ),
          );
        }
      }
    }

    // Find matching files
    for (final filePath in files.keys) {
      if (filePath.startsWith(prefix)) {
        final relative = filePath.substring(prefix.length);
        final parts = relative.split('/');
        if (parts.length == 1) {
          final name = parts.first;
          if (name.isNotEmpty && !results.any((e) => e.name == name)) {
            results.add(
              Smb2DirEntry(
                name: name,
                stat: Smb2Stat(
                  type: Smb2FileType.file,
                  size: files[filePath]!.length,
                  modified: DateTime.now(),
                  created: DateTime.now(),
                ),
              ),
            );
          }
        }
      }
    }
    return results;
  }

  void _maybeFail() {
    if (failOperations && operationFailureCount > 0) {
      operationFailureCount--;
      throw Exception('Mock network timeout or socket error');
    }
  }
}

void main() {
  late Directory tempDir;
  late File localFile;
  late FakeSmbService fakeSmbService;
  late SmbFileTransfer fileTransfer;

  final String fileContent =
      'Hello, this is a test string to verify file integrity over SMB!';
  final Uint8List fileBytes = Uint8List.fromList(fileContent.codeUnits);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('truetransfer_smb_test');
    localFile = File('${tempDir.path}/test_file.txt');
    localFile.writeAsBytesSync(fileBytes);

    fakeSmbService = FakeSmbService()..isConnected = true;
    fileTransfer = SmbFileTransfer(fakeSmbService);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SmbFileTransfer Tests', () {
    test('Successful transactional transfer', () async {
      await fileTransfer.transferFile(
        localPath: localFile.path,
        remotePath: 'backup/test_file.txt',
        onProgress: (transferred, total) {},
        checkCancelled: () => false,
        checkPaused: () => false,
      );

      // Verify the final file exists on the remote
      expect(fakeSmbService.files.containsKey('backup/test_file.txt'), isTrue);
      // Verify its content matches
      expect(
        String.fromCharCodes(fakeSmbService.files['backup/test_file.txt']!),
        fileContent,
      );
      // Verify the temporary .part file is gone
      expect(
        fakeSmbService.files.containsKey('backup/test_file.txt.part'),
        isFalse,
      );
      // Verify local source file is deleted (transaction completed)
      expect(localFile.existsSync(), isFalse);
    });

    test(
      'Successful transfer with deleteSource: false preserves local source file',
      () async {
        await fileTransfer.transferFile(
          localPath: localFile.path,
          remotePath: 'backup/test_file.txt',
          onProgress: (transferred, total) {},
          checkCancelled: () => false,
          checkPaused: () => false,
          deleteSource: false,
        );

        // Verify the final file exists on the remote
        expect(
          fakeSmbService.files.containsKey('backup/test_file.txt'),
          isTrue,
        );
        // Verify local source file is NOT deleted
        expect(localFile.existsSync(), isTrue);
      },
    );

    test('Nested directory creation during transfer', () async {
      await fileTransfer.transferFile(
        localPath: localFile.path,
        remotePath: 'folder1/folder2/nested_file.txt',
        onProgress: (transferred, total) {},
        checkCancelled: () => false,
        checkPaused: () => false,
      );

      // Verify the directories were created on the remote
      expect(fakeSmbService.directories.contains('folder1'), isTrue);
      expect(fakeSmbService.directories.contains('folder1/folder2'), isTrue);

      // Verify the final file exists
      expect(
        fakeSmbService.files.containsKey('folder1/folder2/nested_file.txt'),
        isTrue,
      );
      expect(localFile.existsSync(), isFalse);
    });

    test(
      'Failed transfer due to hash mismatch preserves local file and cleans remote',
      () async {
        fakeSmbService.corruptOnRead = true;

        expect(
          () => fileTransfer.transferFile(
            localPath: localFile.path,
            remotePath: 'backup/test_file.txt',
            onProgress: (transferred, total) {},
            checkCancelled: () => false,
            checkPaused: () => false,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Hash mismatch'),
            ),
          ),
        );

        // Verify remote destination does not exist
        expect(
          fakeSmbService.files.containsKey('backup/test_file.txt'),
          isFalse,
        );
        // Verify remote temporary file was cleaned up
        expect(
          fakeSmbService.files.containsKey('backup/test_file.txt.part'),
          isFalse,
        );
        // Verify local file is NOT deleted
        expect(localFile.existsSync(), isTrue);
      },
    );

    test(
      'Cancelled transfer keeps .part file and local file for resuming',
      () async {
        final largeFile = File('${tempDir.path}/large_test_file.txt');
        largeFile.writeAsBytesSync(Uint8List(128 * 1024));

        int chunkCount = 0;
        await expectLater(
          fileTransfer.transferFile(
            localPath: largeFile.path,
            remotePath: 'backup/large_test_file.txt',
            onProgress: (transferred, total) {},
            checkCancelled: () {
              chunkCount++;
              return chunkCount > 1; // Cancel after first chunk is read/written
            },
            checkPaused: () => false,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Transfer cancelled'),
            ),
          ),
        );

        // Verify remote temporary file still exists
        expect(
          fakeSmbService.files.containsKey('backup/large_test_file.txt.part'),
          isTrue,
        );
        // Verify local file is NOT deleted
        expect(largeFile.existsSync(), isTrue);
      },
    );

    test('Resume transfer from offset', () async {
      // 1. Simulate a partial write of 20 bytes on the remote share
      final partialBytes = Uint8List.sublistView(fileBytes, 0, 20);
      fakeSmbService.files['backup/test_file.txt.part'] = partialBytes;

      // 2. Perform the transfer with resume offset of 20 bytes
      await fileTransfer.transferFile(
        localPath: localFile.path,
        remotePath: 'backup/test_file.txt',
        onProgress: (transferred, total) {},
        checkCancelled: () => false,
        checkPaused: () => false,
        resumeOffset: 20,
      );

      // Verify transaction succeeded
      expect(fakeSmbService.files.containsKey('backup/test_file.txt'), isTrue);
      expect(
        String.fromCharCodes(fakeSmbService.files['backup/test_file.txt']!),
        fileContent,
      );
      expect(localFile.existsSync(), isFalse);
    });
  });
}
