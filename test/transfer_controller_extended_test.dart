import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_smb2/dart_smb2.dart';
import 'package:truetransfer/models/transfer_item.dart';
import 'package:truetransfer/models/transfer_queue.dart';
import 'package:truetransfer/models/smb_exceptions.dart';
import 'package:truetransfer/services/transfer_controller.dart';
import 'package:truetransfer/services/smb_service.dart';
import 'package:truetransfer/utils/storage_manager.dart';
import 'package:truetransfer/utils/secure_storage.dart';
import 'package:file_picker/file_picker.dart';

// ---------------------------------------------------------------------------
// Fake SMB service used across these tests
// ---------------------------------------------------------------------------
class FakeSmbService implements SmbService {
  @override
  bool isConnected = true;

  bool shouldFailConnect = false;
  bool shouldFailDirectory = false;

  final Map<String, Uint8List> files = {};
  final Set<String> dirs = {};

  // Optional list of Smb2DirEntry to return from listDirectory
  List<Smb2DirEntry> directoryListing = [];

  @override
  Future<void> connect({
    required String host,
    required String share,
    String? user,
    String? password,
    String? domain,
  }) async {
    if (shouldFailConnect) {
      throw SmbException(
        type: SmbErrorType.connectionFailed,
        message: 'Mock connection failure',
      );
    }
    isConnected = true;
  }

  @override
  Future<void> disconnect() async {
    isConnected = false;
  }

  @override
  Future<bool> exists(String path) async =>
      files.containsKey(path) || dirs.contains(path);

  @override
  Future<void> createDirectory(String path) async {
    if (shouldFailDirectory) throw Exception('mkdir failed');
    dirs.add(path);
  }

  @override
  Future<int> fileSize(String path) async => files[path]?.length ?? 0;

  @override
  Future<void> deleteFile(String path) async => files.remove(path);

  @override
  Future<void> rename(String oldPath, String newPath) async {
    if (files.containsKey(oldPath)) {
      files[newPath] = files.remove(oldPath)!;
    }
  }

  @override
  Future<void> writeFileRange(
    String path,
    Uint8List data, {
    int offset = 0,
  }) async {
    final current = files[path] ?? Uint8List(0);
    final newLen = (offset + data.length > current.length)
        ? offset + data.length
        : current.length;
    final updated = Uint8List(newLen)
      ..setRange(0, current.length, current)
      ..setRange(offset, offset + data.length, data);
    files[path] = updated;
  }

  @override
  Future<Uint8List> readFileRange(
    String path, {
    int offset = 0,
    required int length,
  }) async {
    final data = files[path]!;
    final end = (offset + length > data.length) ? data.length : offset + length;
    return Uint8List.sublistView(data, offset, end);
  }

  @override
  Future<List<Smb2DirEntry>> listDirectory(String path) async {
    return directoryListing;
  }
}

// ---------------------------------------------------------------------------
// Helper to build a Smb2DirEntry with a given name and type
// ---------------------------------------------------------------------------
Smb2DirEntry _dirEntry(String name, {bool isDir = true}) {
  return Smb2DirEntry(
    name: name,
    stat: Smb2Stat(
      type: isDir ? Smb2FileType.directory : Smb2FileType.file,
      size: 0,
      modified: DateTime.now(),
      created: DateTime.now(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StorageManager storageManager;
  late FakeSmbService fakeSmbService;
  late TransferController controller;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('truetransfer_ext_test');
    storageManager = StorageManager(
      baseDirectory: tempDir,
      secureStorage: FakeSecureStorage(),
    );
    fakeSmbService = FakeSmbService();

    controller = TransferController();
    controller.storageManager = storageManager;
    controller.smbPoolManager = fakeSmbService;

    // Reset singleton state (including metrics)
    await controller.clearQueue();
    controller.host = null;
    controller.share = null;
    controller.username = null;
    controller.password = null;
    controller.domain = null;
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // -------------------------------------------------------------------------
  // initialize — metrics accumulation from persisted completed items
  // -------------------------------------------------------------------------
  group('initialize with completed items', () {
    test('accumulates totalBytesMoved and totalStorageReclaimed', () async {
      // Save a queue with one completed item
      final completed = TransferItem(
        id: 'done',
        sourcePath: '/src/done.txt',
        remotePath: 'done.txt',
        fileSize: 500,
        status: TransferStatus.completed,
        transferredBytes: 500,
      );
      final pending = TransferItem(
        id: 'todo',
        sourcePath: '/src/todo.txt',
        remotePath: 'todo.txt',
        fileSize: 200,
      );
      await storageManager.saveQueue(
        TransferQueue(items: [completed, pending]),
      );

      await controller.initialize();

      expect(controller.totalBytesMoved, 500);
      expect(controller.totalStorageReclaimed, 500);
    });

    test('does not accumulate for pending items', () async {
      final pending = TransferItem(
        id: 'todo',
        sourcePath: '/src/todo.txt',
        remotePath: 'todo.txt',
        fileSize: 200,
      );
      await storageManager.saveQueue(TransferQueue(items: [pending]));

      await controller.initialize();

      expect(controller.totalBytesMoved, 0);
      expect(controller.totalStorageReclaimed, 0);
    });
  });

  // -------------------------------------------------------------------------
  // connectSMB failure path
  // -------------------------------------------------------------------------
  group('connectSMB failure', () {
    test('returns false and sets connectionError on failure', () async {
      fakeSmbService.shouldFailConnect = true;
      final result = await controller.connectSMB(
        host: 'bad-host',
        share: 'share',
      );

      expect(result, isFalse);
      expect(controller.connectionError, isNotNull);
      expect(controller.isConnecting, isFalse);
    });

    test('notifies listeners on failure', () async {
      fakeSmbService.shouldFailConnect = true;
      bool notified = false;
      controller.addListener(() => notified = true);

      await controller.connectSMB(host: 'bad', share: 'share');

      expect(notified, isTrue);
      controller.removeListener(() => notified = true);
    });
  });

  // -------------------------------------------------------------------------
  // disconnectSMB
  // -------------------------------------------------------------------------
  group('disconnectSMB', () {
    test('disconnects the pool manager and notifies listeners', () async {
      bool notified = false;
      controller.addListener(() => notified = true);

      await controller.disconnectSMB();

      expect(fakeSmbService.isConnected, isFalse);
      expect(notified, isTrue);
      controller.removeListener(() => notified = true);
    });
  });

  // -------------------------------------------------------------------------
  // addFilesToQueue
  // -------------------------------------------------------------------------
  group('addFilesToQueue', () {
    test('adds existing files to the queue', () async {
      final f1 = File('${tempDir.path}/a.txt')..writeAsBytesSync(Uint8List(42));
      final f2 = File('${tempDir.path}/b.txt')..writeAsBytesSync(Uint8List(10));

      controller.queue.clear();
      await controller.addFilesToQueue([f1.path, f2.path]);

      expect(controller.queue.items.length, 2);
      expect(
        controller.queue.items.any((i) => i.sourcePath == f1.path),
        isTrue,
      );
      expect(
        controller.queue.items.any((i) => i.sourcePath == f2.path),
        isTrue,
      );
    });

    test('skips non-existent files', () async {
      controller.queue.clear();
      await controller.addFilesToQueue(['/does/not/exist.txt']);
      expect(controller.queue.items, isEmpty);
    });

    test('sets remotePath to basename and correct fileSize', () async {
      final f = File('${tempDir.path}/hello.txt')
        ..writeAsBytesSync(Uint8List(100));
      controller.queue.clear();
      await controller.addFilesToQueue([f.path]);

      final item = controller.queue.items.first;
      expect(item.remotePath, 'hello.txt');
      expect(item.fileSize, 100);
    });

    test('notifies listeners after adding', () async {
      final f = File('${tempDir.path}/c.txt')..writeAsBytesSync(Uint8List(1));
      bool notified = false;
      controller.addListener(() => notified = true);
      controller.queue.clear();

      await controller.addFilesToQueue([f.path]);

      expect(notified, isTrue);
      controller.removeListener(() => notified = true);
    });

    test(
      'updates isAddingToQueue, addingTotal, and addingCompleted during execution',
      () async {
        final f1 = File('${tempDir.path}/a.txt')
          ..writeAsBytesSync(Uint8List(42));
        final f2 = File('${tempDir.path}/b.txt')
          ..writeAsBytesSync(Uint8List(10));
        controller.queue.clear();

        final states = <Map<String, dynamic>>[];
        void listener() {
          states.add({
            'isAdding': controller.isAddingToQueue,
            'total': controller.addingTotal,
            'completed': controller.addingCompleted,
          });
        }

        controller.addListener(listener);

        await controller.addFilesToQueue([f1.path, f2.path]);

        controller.removeListener(listener);
        expect(controller.isAddingToQueue, isFalse);
        expect(
          states.any((s) => s['isAdding'] == true && s['total'] == 2),
          isTrue,
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // addPlatformFilesToQueue
  // -------------------------------------------------------------------------
  group('addPlatformFilesToQueue', () {
    test('adds PlatformFiles to the queue and updates progress', () async {
      final f1 = File('${tempDir.path}/pf1.txt')
        ..writeAsBytesSync(Uint8List(50));
      final f2 = File('${tempDir.path}/pf2.txt')
        ..writeAsBytesSync(Uint8List(30));
      final pf1 = PlatformFile(name: 'pf1.txt', size: 50, path: f1.path);
      final pf2 = PlatformFile(name: 'pf2.txt', size: 30, path: f2.path);

      controller.queue.clear();
      final states = <Map<String, dynamic>>[];
      void listener() {
        states.add({
          'isAdding': controller.isAddingToQueue,
          'total': controller.addingTotal,
          'completed': controller.addingCompleted,
        });
      }

      controller.addListener(listener);

      await controller.addPlatformFilesToQueue([pf1, pf2]);

      controller.removeListener(listener);
      expect(controller.queue.items.length, 2);
      expect(controller.queue.items[0].remotePath, 'pf1.txt');
      expect(controller.queue.items[0].fileSize, 50);
      expect(controller.queue.items[1].remotePath, 'pf2.txt');
      expect(controller.queue.items[1].fileSize, 30);
      expect(controller.isAddingToQueue, isFalse);
      expect(
        states.any((s) => s['isAdding'] == true && s['total'] == 2),
        isTrue,
      );
    });

    test('setAddingToQueue updates status and notifies listeners', () {
      bool notified = false;
      controller.addListener(() => notified = true);

      controller.setAddingToQueue(true, total: 10, completed: 3);

      expect(controller.isAddingToQueue, isTrue);
      expect(controller.addingTotal, 10);
      expect(controller.addingCompleted, 3);
      expect(notified, isTrue);
      controller.removeListener(() => notified = true);
    });
  });

  // -------------------------------------------------------------------------
  // addFolderToQueue
  // -------------------------------------------------------------------------
  group('addFolderToQueue', () {
    test('returns early and does nothing for non-existent folder', () async {
      controller.queue.clear();
      await controller.addFolderToQueue('/no/such/folder');
      expect(controller.queue.items, isEmpty);
    });

    test('adds all files recursively from a folder', () async {
      final subDir = Directory('${tempDir.path}/myFolder/sub')
        ..createSync(recursive: true);
      File('${tempDir.path}/myFolder/root.txt').writeAsBytesSync(Uint8List(10));
      File('${subDir.path}/nested.txt').writeAsBytesSync(Uint8List(20));

      controller.queue.clear();
      await controller.addFolderToQueue('${tempDir.path}/myFolder');

      expect(controller.queue.items.length, 2);
      // Remote paths should use forward slashes
      final remotePaths = controller.queue.items
          .map((i) => i.remotePath)
          .toList();
      expect(remotePaths.any((p) => p.contains('root.txt')), isTrue);
      expect(remotePaths.any((p) => p.contains('nested.txt')), isTrue);
      expect(remotePaths.every((p) => !p.contains(r'\')), isTrue);
    });

    test('notifies listeners after adding', () async {
      Directory('${tempDir.path}/emptyFolder').createSync();
      bool notified = false;
      controller.addListener(() => notified = true);
      controller.queue.clear();

      await controller.addFolderToQueue('${tempDir.path}/emptyFolder');

      expect(notified, isTrue);
      controller.removeListener(() => notified = true);
    });

    test('updates progress during folder import', () async {
      final subDir = Directory('${tempDir.path}/myProgressFolder/sub')
        ..createSync(recursive: true);
      File(
        '${tempDir.path}/myProgressFolder/root.txt',
      ).writeAsBytesSync(Uint8List(10));
      File('${subDir.path}/nested.txt').writeAsBytesSync(Uint8List(20));

      controller.queue.clear();
      final states = <Map<String, dynamic>>[];
      void listener() {
        states.add({
          'isAdding': controller.isAddingToQueue,
          'total': controller.addingTotal,
          'completed': controller.addingCompleted,
        });
      }

      controller.addListener(listener);

      await controller.addFolderToQueue('${tempDir.path}/myProgressFolder');

      controller.removeListener(listener);
      expect(controller.isAddingToQueue, isFalse);
      expect(
        states.any((s) => s['isAdding'] == true && s['total'] == 2),
        isTrue,
      );
    });
  });

  // -------------------------------------------------------------------------
  // removeItemFromQueue
  // -------------------------------------------------------------------------
  group('removeItemFromQueue', () {
    test('removes item by id and notifies listeners', () async {
      controller.queue.clear();
      controller.queue.add(
        TransferItem(id: 'x', sourcePath: 's', remotePath: 'r', fileSize: 1),
      );

      bool notified = false;
      controller.addListener(() => notified = true);

      await controller.removeItemFromQueue('x');

      expect(controller.queue.items, isEmpty);
      expect(notified, isTrue);
      controller.removeListener(() => notified = true);
    });

    test('is a no-op when id not found', () async {
      controller.queue.clear();
      controller.queue.add(
        TransferItem(id: 'y', sourcePath: 's', remotePath: 'r', fileSize: 1),
      );

      await controller.removeItemFromQueue('nonexistent');
      expect(controller.queue.items.length, 1);
    });
  });

  // -------------------------------------------------------------------------
  // clearQueue
  // -------------------------------------------------------------------------
  group('clearQueue', () {
    test('empties the queue and resets byte counters', () async {
      controller.queue.add(
        TransferItem(
          id: 'z',
          sourcePath: 's',
          remotePath: 'r',
          fileSize: 100,
          status: TransferStatus.completed,
          transferredBytes: 100,
        ),
      );
      await controller.initialize(); // accumulates bytes
      controller.queue.add(
        TransferItem(
          id: 'z2',
          sourcePath: 's2',
          remotePath: 'r2',
          fileSize: 50,
        ),
      );

      bool notified = false;
      controller.addListener(() => notified = true);

      await controller.clearQueue();

      expect(controller.queue.items, isEmpty);
      expect(controller.totalBytesMoved, 0);
      expect(controller.totalStorageReclaimed, 0);
      expect(notified, isTrue);
      controller.removeListener(() => notified = true);
    });
  });

  // -------------------------------------------------------------------------
  // listRemoteSubdirectories
  // -------------------------------------------------------------------------
  group('listRemoteSubdirectories', () {
    test('returns empty list when not connected', () async {
      fakeSmbService.isConnected = false;
      final result = await controller.listRemoteSubdirectories('/');
      expect(result, isEmpty);
    });

    test('returns only directory names when connected', () async {
      fakeSmbService.directoryListing = [
        _dirEntry('photos', isDir: true),
        _dirEntry('video.mp4', isDir: false),
        _dirEntry('docs', isDir: true),
      ];

      final result = await controller.listRemoteSubdirectories('/');
      expect(result, containsAll(['photos', 'docs']));
      expect(result, isNot(contains('video.mp4')));
    });
  });

  // -------------------------------------------------------------------------
  // createRemoteDirectory
  // -------------------------------------------------------------------------
  group('createRemoteDirectory', () {
    test('does nothing when not connected', () async {
      fakeSmbService.isConnected = false;
      // Should not throw
      await controller.createRemoteDirectory('new_folder');
      expect(fakeSmbService.dirs, isEmpty);
    });

    test('creates directory via pool manager when connected', () async {
      await controller.createRemoteDirectory('my_folder');
      expect(fakeSmbService.dirs, contains('my_folder'));
    });
  });

  // -------------------------------------------------------------------------
  // pauseTransfer
  // -------------------------------------------------------------------------
  group('pauseTransfer', () {
    test('sets isPaused and notifies listeners', () {
      bool notified = false;
      controller.addListener(() => notified = true);

      controller.pauseTransfer();

      expect(controller.isPaused, isTrue);
      expect(notified, isTrue);
      controller.removeListener(() => notified = true);
    });
  });

  // -------------------------------------------------------------------------
  // cancelTransfer
  // -------------------------------------------------------------------------
  group('cancelTransfer', () {
    test('sets state flags and notifies listeners', () {
      bool notified = false;
      controller.addListener(() => notified = true);

      controller.cancelTransfer();

      expect(controller.isTransferring, isFalse);
      expect(controller.isPaused, isFalse);
      expect(notified, isTrue);
      controller.removeListener(() => notified = true);
    });
  });

  // -------------------------------------------------------------------------
  // resumeTransfer — not connected guard
  // -------------------------------------------------------------------------
  group('resumeTransfer not connected', () {
    test('does nothing when not connected', () async {
      fakeSmbService.isConnected = false;
      controller.pauseTransfer();
      // Should not throw and should not start a transfer
      controller.resumeTransfer();
      expect(controller.isTransferring, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // _runWorker — error branches
  // -------------------------------------------------------------------------
  group('_runWorker error branches', () {
    test(
      'cancelled transfer sets item to paused or completed status',
      () async {
        // Use a large file so we have time to cancel mid-transfer
        final localFile = File('${tempDir.path}/cancel_test.txt')
          ..writeAsBytesSync(Uint8List(128 * 1024)); // 128 KB

        controller.queue.clear();
        controller.queue.add(
          TransferItem(
            id: 'c1',
            sourcePath: localFile.path,
            remotePath: 'cancel_test.txt',
            fileSize: 128 * 1024,
          ),
        );

        // Start transfer then immediately cancel
        controller.startTransfer();
        await Future.delayed(const Duration(milliseconds: 5));
        controller.cancelTransfer();

        // Wait for the worker loop to exit
        await Future.delayed(const Duration(milliseconds: 200));

        // After cancel, the item should be paused or completed (never failed)
        final item = controller.queue.items.first;
        expect(
          item.status == TransferStatus.paused ||
              item.status == TransferStatus.completed,
          isTrue,
          reason: 'Expected paused or completed, got ${item.status}',
        );
        expect(controller.isTransferring, isFalse);
      },
    );

    test('generic error marks item as failed and stops transferring', () async {
      // Provide a file that doesn't exist on disk — transfer will fail
      controller.queue.clear();
      controller.queue.add(
        TransferItem(
          id: 'fail1',
          sourcePath: '/nonexistent/file.txt',
          remotePath: 'file.txt',
          fileSize: 100,
        ),
      );

      controller.startTransfer();

      // Wait for processing
      while (controller.isTransferring) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      final item = controller.queue.items.first;
      expect(item.status, TransferStatus.failed);
      expect(item.errorMessage, isNotNull);
      expect(controller.isTransferring, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // _runWorker — worker exits when queue is empty
  // -------------------------------------------------------------------------
  group('_runWorker empty queue', () {
    test('startTransfer does nothing on empty queue', () async {
      controller.queue.clear();
      controller.startTransfer();

      await Future.delayed(const Duration(milliseconds: 50));
    });
  });

  group('Duplicate file controller tests', () {
    test(
      'skipped backup because of matching checksum sets status alreadyBackedUp and updates reclaimed metric',
      () async {
        final localFile = File('${tempDir.path}/dup_test.txt')
          ..writeAsBytesSync(Uint8List.fromList('checksum_match'.codeUnits));
        final size = localFile.lengthSync();

        fakeSmbService.files['dup_test.txt'] = Uint8List.fromList(
          'checksum_match'.codeUnits,
        );

        controller.queue.clear();
        controller.queue.add(
          TransferItem(
            id: 'dup1',
            sourcePath: localFile.path,
            remotePath: 'dup_test.txt',
            fileSize: size,
          ),
        );

        controller.host = 'localhost';
        controller.share = 'share';
        fakeSmbService.isConnected = true;
        controller.deleteSource = true;

        controller.startTransfer();

        while (controller.isTransferring) {
          await Future.delayed(const Duration(milliseconds: 10));
        }

        final item = controller.queue.items.first;
        expect(item.status, TransferStatus.alreadyBackedUp);
        expect(item.transferredBytes, size);
        expect(controller.totalBytesMoved, 0);
        expect(controller.totalStorageReclaimed, size);
        expect(localFile.existsSync(), isFalse);
      },
    );

    test(
      'initialize loads metrics correctly for alreadyBackedUp files',
      () async {
        final item = TransferItem(
          id: 'dup2',
          sourcePath: '/src/dup.txt',
          remotePath: 'dup.txt',
          fileSize: 300,
          status: TransferStatus.alreadyBackedUp,
          transferredBytes: 300,
        );

        await storageManager.saveQueue(TransferQueue(items: [item]));

        final newController = TransferController();
        newController.storageManager = storageManager;
        newController.smbPoolManager = fakeSmbService;

        await newController.initialize();

        expect(newController.totalBytesMoved, 0);
        expect(newController.totalStorageReclaimed, 300);
      },
    );
  });
}
