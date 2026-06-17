import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:truetransfer/models/transfer_item.dart';
import 'package:truetransfer/services/transfer_controller.dart';
import 'package:truetransfer/services/smb_service.dart';
import 'package:truetransfer/utils/storage_manager.dart';
import 'package:truetransfer/utils/secure_storage.dart';

class ConcurrencyFakeSmbService implements SmbService {
  @override
  bool isConnected = true;

  int activeTransfersCount = 0;
  int maxConcurrentTransfers = 0;

  @override
  Future<bool> exists(String path) async => false;

  @override
  Future<void> createDirectory(String path) async {}

  @override
  Future<void> writeFileRange(
    String path,
    Uint8List data, {
    int offset = 0,
  }) async {
    activeTransfersCount++;
    if (activeTransfersCount > maxConcurrentTransfers) {
      maxConcurrentTransfers = activeTransfersCount;
    }
    // Delay to allow concurrent operations to overlap
    await Future.delayed(const Duration(milliseconds: 50));
    activeTransfersCount--;
  }

  @override
  Future<int> fileSize(String path) async => 0;

  @override
  Future<void> deleteFile(String path) async {}

  @override
  Future<void> rename(String old, String newPath) async {}

  @override
  Future<Uint8List> readFileRange(
    String path, {
    int offset = 0,
    required int length,
  }) async {
    return Uint8List(length);
  }

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late StorageManager storageManager;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'truetransfer_controller_test',
    );
    storageManager = StorageManager(
      baseDirectory: tempDir,
      secureStorage: FakeSecureStorage(),
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('TransferController Tests', () {
    test(
      'updateItemDestination and updateAllDestinations should update models',
      () async {
        final controller = TransferController();
        controller.storageManager = storageManager;
        controller.queue.clear();

        final item1 = TransferItem(
          id: 'item1',
          sourcePath: 'src1',
          remotePath: 'dst1',
          fileSize: 100,
        );
        final item2 = TransferItem(
          id: 'item2',
          sourcePath: 'src2',
          remotePath: 'dst2',
          fileSize: 200,
        );

        controller.queue.add(item1);
        controller.queue.add(item2);

        // Verify initial states
        expect(controller.queue.items[0].remoteDirectory, '');
        expect(controller.queue.items[1].remoteDirectory, '');

        // Update individual destination
        bool notified = false;
        void listener() {
          notified = true;
        }

        controller.addListener(listener);

        await controller.updateItemDestination('item1', 'folderA');
        expect(controller.queue.items[0].remoteDirectory, 'folderA');
        expect(controller.queue.items[1].remoteDirectory, '');
        expect(notified, isTrue);

        // Reset notification flag and update all
        notified = false;
        await controller.updateAllDestinations('folderB');
        expect(controller.queue.items[0].remoteDirectory, 'folderB');
        expect(controller.queue.items[1].remoteDirectory, 'folderB');
        expect(notified, isTrue);

        controller.removeListener(listener);
      },
    );

    test(
      'deleteSource and parallelism settings should update and persist',
      () async {
        final controller = TransferController();
        controller.storageManager = storageManager;

        // Default values
        expect(controller.deleteSource, isTrue);
        expect(controller.parallelism, 1);

        // Change settings
        controller.deleteSource = false;
        controller.parallelism = 4;

        expect(controller.deleteSource, isFalse);
        expect(controller.parallelism, 4);

        // Re-initialize a new controller to verify persistence
        final newController = TransferController();
        newController.storageManager = storageManager;
        await newController.initialize();

        expect(newController.deleteSource, isFalse);
        expect(newController.parallelism, 4);
      },
    );

    test('concurrency limits are respected during queue execution', () async {
      final controller = TransferController();
      controller.storageManager = storageManager;
      final fakeSmb = ConcurrencyFakeSmbService();
      controller.smbPoolManager = fakeSmb;
      controller.queue.clear();

      // Create 3 temporary local files to transfer
      final f1 = File('${tempDir.path}/f1.txt')
        ..writeAsBytesSync(Uint8List(10));
      final f2 = File('${tempDir.path}/f2.txt')
        ..writeAsBytesSync(Uint8List(10));
      final f3 = File('${tempDir.path}/f3.txt')
        ..writeAsBytesSync(Uint8List(10));

      final item1 = TransferItem(
        id: 'i1',
        sourcePath: f1.path,
        remotePath: 'rf1.txt',
        fileSize: 10,
      );
      final item2 = TransferItem(
        id: 'i2',
        sourcePath: f2.path,
        remotePath: 'rf2.txt',
        fileSize: 10,
      );
      final item3 = TransferItem(
        id: 'i3',
        sourcePath: f3.path,
        remotePath: 'rf3.txt',
        fileSize: 10,
      );

      controller.queue.add(item1);
      controller.queue.add(item2);
      controller.queue.add(item3);

      // Set parallelism = 2
      controller.parallelism = 2;

      // Run transfer
      controller.startTransfer();

      // Wait for queue processing to complete
      while (controller.isTransferring) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Concurrency checks
      expect(fakeSmb.maxConcurrentTransfers, equals(2));
      expect(
        controller.queue.items.every(
          (i) => i.status == TransferStatus.completed,
        ),
        isTrue,
      );
    });
  });
}
