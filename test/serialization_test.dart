import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:truetransfer/models/transfer_item.dart';
import 'package:truetransfer/models/transfer_queue.dart';
import 'package:truetransfer/utils/storage_manager.dart';

void main() {
  group('TransferItem Serialization', () {
    test('toJson and fromJson should match', () {
      final item = TransferItem(
        id: '123',
        sourcePath: '/local/file.txt',
        remotePath: 'smb://host/share/file.txt',
        fileSize: 1024,
        status: TransferStatus.transferring,
        transferredBytes: 500,
        sourceHash: 'sha-src',
        remoteHash: 'sha-dst',
        errorMessage: 'Some error',
        resumeOffset: 256,
        remoteDirectory: 'backups/2026',
      );

      final json = item.toJson();
      final decoded = TransferItem.fromJson(json);

      expect(decoded.id, item.id);
      expect(decoded.sourcePath, item.sourcePath);
      expect(decoded.remotePath, item.remotePath);
      expect(decoded.fileSize, item.fileSize);
      expect(decoded.status, item.status);
      expect(decoded.transferredBytes, item.transferredBytes);
      expect(decoded.sourceHash, item.sourceHash);
      expect(decoded.remoteHash, item.remoteHash);
      expect(decoded.errorMessage, item.errorMessage);
      expect(decoded.resumeOffset, item.resumeOffset);
      expect(decoded.remoteDirectory, item.remoteDirectory);
    });
  });

  group('TransferQueue Serialization', () {
    test('toJson and fromJson should handle list of items', () {
      final item1 = TransferItem(
        id: '1',
        sourcePath: '/path1',
        remotePath: '/remote1',
        fileSize: 100,
      );
      final item2 = TransferItem(
        id: '2',
        sourcePath: '/path2',
        remotePath: '/remote2',
        fileSize: 200,
        status: TransferStatus.completed,
        transferredBytes: 200,
      );

      final queue = TransferQueue(items: [item1, item2]);

      expect(queue.totalBytes, 300);
      expect(queue.transferredBytes, 200);
      expect(queue.overallProgress, closeTo(200 / 300, 0.0001));

      final json = queue.toJson();
      final decoded = TransferQueue.fromJson(json);

      expect(decoded.items.length, 2);
      expect(decoded.items[0].id, '1');
      expect(decoded.items[1].id, '2');
      expect(decoded.totalBytes, 300);
    });
  });

  group('StorageManager Integration Test', () {
    late Directory tempDir;
    late StorageManager storageManager;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('truetransfer_test');
      storageManager = StorageManager(baseDirectory: tempDir);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('should save and load queue successfully', () async {
      final item = TransferItem(
        id: 'test_id',
        sourcePath: 'src',
        remotePath: 'dst',
        fileSize: 50,
      );
      final queue = TransferQueue(items: [item]);

      await storageManager.saveQueue(queue);
      final loadedQueue = await storageManager.loadQueue();

      expect(loadedQueue.items.length, 1);
      expect(loadedQueue.items[0].id, 'test_id');
      expect(loadedQueue.items[0].fileSize, 50);

      await storageManager.clearQueue();
      final clearedQueue = await storageManager.loadQueue();
      expect(clearedQueue.items, isEmpty);
    });
  });
}
