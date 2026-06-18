import 'package:flutter_test/flutter_test.dart';
import 'package:truetransfer/models/smb_exceptions.dart';
import 'package:truetransfer/models/smb_remote_entry.dart';
import 'package:truetransfer/models/transfer_item.dart';
import 'package:truetransfer/models/transfer_queue.dart';
import 'package:truetransfer/utils/secure_storage.dart';

void main() {
  // ---------------------------------------------------------------------------
  // SmbException
  // ---------------------------------------------------------------------------
  group('SmbException', () {
    test('toString returns formatted string with type and message', () {
      final ex = SmbException(
        type: SmbErrorType.connectionFailed,
        message: 'Cannot reach host',
      );
      expect(
        ex.toString(),
        'SmbException(connectionFailed): Cannot reach host',
      );
    });

    test('toString includes all SmbErrorType variants', () {
      for (final type in SmbErrorType.values) {
        final ex = SmbException(type: type, message: 'msg');
        expect(ex.toString(), contains(type.name));
      }
    });

    test('originalException field is stored', () {
      final original = Exception('root cause');
      final ex = SmbException(
        type: SmbErrorType.unknown,
        message: 'wrapped',
        originalException: original,
      );
      expect(ex.originalException, same(original));
    });
  });

  // ---------------------------------------------------------------------------
  // SmbRemoteEntry
  // ---------------------------------------------------------------------------
  group('SmbRemoteEntry', () {
    test('constructor stores all fields', () {
      final entry = SmbRemoteEntry(name: 'photos', isDirectory: true, size: 0);
      expect(entry.name, 'photos');
      expect(entry.isDirectory, isTrue);
      expect(entry.size, 0);
    });

    test('file entry is not a directory and has a size', () {
      final entry = SmbRemoteEntry(
        name: 'document.pdf',
        isDirectory: false,
        size: 4096,
      );
      expect(entry.isDirectory, isFalse);
      expect(entry.size, 4096);
    });
  });

  // ---------------------------------------------------------------------------
  // TransferItem — progress getter zero-guard
  // ---------------------------------------------------------------------------
  group('TransferItem.progress', () {
    test('returns 0.0 when fileSize is zero', () {
      final item = TransferItem(
        id: 'x',
        sourcePath: '/src',
        remotePath: '/dst',
        fileSize: 0,
        transferredBytes: 0,
      );
      expect(item.progress, 0.0);
    });

    test('returns correct fraction when fileSize > 0', () {
      final item = TransferItem(
        id: 'x',
        sourcePath: '/src',
        remotePath: '/dst',
        fileSize: 200,
        transferredBytes: 50,
      );
      expect(item.progress, closeTo(0.25, 0.0001));
    });
  });

  // ---------------------------------------------------------------------------
  // TransferItem — copyWith
  // ---------------------------------------------------------------------------
  group('TransferItem.copyWith', () {
    late TransferItem original;

    setUp(() {
      original = TransferItem(
        id: 'orig',
        sourcePath: '/src/orig.txt',
        remotePath: 'orig.txt',
        fileSize: 1000,
        remoteDirectory: 'backups',
        status: TransferStatus.pending,
        transferredBytes: 100,
        sourceHash: 'abc',
        remoteHash: 'def',
        errorMessage: 'some error',
        resumeOffset: 50,
      );
    });

    test('returns identical copy when no arguments given', () {
      final copy = original.copyWith();
      expect(copy.id, original.id);
      expect(copy.sourcePath, original.sourcePath);
      expect(copy.remotePath, original.remotePath);
      expect(copy.fileSize, original.fileSize);
      expect(copy.remoteDirectory, original.remoteDirectory);
      expect(copy.status, original.status);
      expect(copy.transferredBytes, original.transferredBytes);
      expect(copy.sourceHash, original.sourceHash);
      expect(copy.remoteHash, original.remoteHash);
      expect(copy.errorMessage, original.errorMessage);
      expect(copy.resumeOffset, original.resumeOffset);
    });

    test('overrides each field independently', () {
      final copy = original.copyWith(
        id: 'new-id',
        sourcePath: '/new/src',
        remotePath: 'new.txt',
        fileSize: 9999,
        remoteDirectory: 'archive',
        status: TransferStatus.completed,
        transferredBytes: 9999,
        sourceHash: 'sha-new',
        remoteHash: 'sha-remote-new',
        resumeOffset: 0,
        // Note: passing null for a nullable field keeps the original value
        // since copyWith uses "errorMessage ?? this.errorMessage"
      );

      expect(copy.id, 'new-id');
      expect(copy.sourcePath, '/new/src');
      expect(copy.remotePath, 'new.txt');
      expect(copy.fileSize, 9999);
      expect(copy.remoteDirectory, 'archive');
      expect(copy.status, TransferStatus.completed);
      expect(copy.transferredBytes, 9999);
      expect(copy.sourceHash, 'sha-new');
      expect(copy.remoteHash, 'sha-remote-new');
      // errorMessage not overridden because null is passed (keeps original)
      expect(copy.errorMessage, original.errorMessage);
      expect(copy.resumeOffset, 0);
    });

    test('original is not mutated', () {
      original.copyWith(id: 'changed');
      expect(original.id, 'orig');
    });
  });

  // ---------------------------------------------------------------------------
  // TransferQueue — add / remove / clear / overallProgress zero-guard
  // ---------------------------------------------------------------------------
  group('TransferQueue', () {
    TransferItem makeItem(String id, {int size = 100, int transferred = 0}) {
      return TransferItem(
        id: id,
        sourcePath: '/src/$id',
        remotePath: id,
        fileSize: size,
        transferredBytes: transferred,
      );
    }

    test('add appends an item', () {
      final queue = TransferQueue(items: []);
      queue.add(makeItem('a'));
      expect(queue.items.length, 1);
      expect(queue.items.first.id, 'a');
    });

    test('remove deletes item by id', () {
      final queue = TransferQueue(items: [makeItem('a'), makeItem('b')]);
      queue.remove('a');
      expect(queue.items.length, 1);
      expect(queue.items.first.id, 'b');
    });

    test('remove is a no-op when id not found', () {
      final queue = TransferQueue(items: [makeItem('a')]);
      queue.remove('nonexistent');
      expect(queue.items.length, 1);
    });

    test('clear removes all items', () {
      final queue = TransferQueue(
        items: [makeItem('a'), makeItem('b'), makeItem('c')],
      );
      queue.clear();
      expect(queue.items, isEmpty);
    });

    test('overallProgress returns 0.0 when totalBytes is zero', () {
      final queue = TransferQueue(items: []);
      expect(queue.overallProgress, 0.0);
    });

    test('overallProgress returns correct fraction', () {
      final q = TransferQueue(
        items: [makeItem('a', size: 100, transferred: 50)],
      );
      expect(q.overallProgress, closeTo(0.5, 0.0001));
    });

    test('fromJson with missing items key returns empty queue', () {
      final queue = TransferQueue.fromJson({});
      expect(queue.items, isEmpty);
    });

    test('fromJson with null items value returns empty queue', () {
      final queue = TransferQueue.fromJson({'items': null});
      expect(queue.items, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // FakeSecureStorage
  // ---------------------------------------------------------------------------
  group('FakeSecureStorage', () {
    late FakeSecureStorage storage;

    setUp(() {
      storage = FakeSecureStorage();
    });

    test('write then read returns the value', () async {
      await storage.write(key: 'k', value: 'v');
      expect(await storage.read(key: 'k'), 'v');
    });

    test('read returns null for missing key', () async {
      expect(await storage.read(key: 'missing'), isNull);
    });

    test('delete removes the key', () async {
      await storage.write(key: 'k', value: 'v');
      await storage.delete(key: 'k');
      expect(await storage.read(key: 'k'), isNull);
    });

    test('delete is a no-op on missing key', () async {
      // Should not throw
      await storage.delete(key: 'nonexistent');
      expect(await storage.read(key: 'nonexistent'), isNull);
    });

    test('multiple keys are independent', () async {
      await storage.write(key: 'a', value: '1');
      await storage.write(key: 'b', value: '2');
      expect(await storage.read(key: 'a'), '1');
      expect(await storage.read(key: 'b'), '2');
      await storage.delete(key: 'a');
      expect(await storage.read(key: 'a'), isNull);
      expect(await storage.read(key: 'b'), '2');
    });
  });
}
