import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:truetransfer/main.dart';
import 'package:truetransfer/services/transfer_controller.dart';
import 'package:truetransfer/services/smb_service.dart';
import 'package:truetransfer/utils/storage_manager.dart';
import 'package:truetransfer/utils/secure_storage.dart';

class IntegrationFakeSmbService implements SmbService {
  @override
  bool isConnected = false;

  final Map<String, Uint8List> files = {};

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
    return files.containsKey(path);
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
  Future<void> createDirectory(String path) async {}

  @override
  Future<void> writeFileRange(
    String path,
    Uint8List data, {
    int offset = 0,
  }) async {
    await Future.delayed(const Duration(milliseconds: 5));
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
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('End-to-End App Integration Tests', () {
    late Directory tempDir;
    late StorageManager storageManager;
    late IntegrationFakeSmbService fakeSmb;
    late TransferController controller;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync(
        'truetransfer_integration_test',
      );
      storageManager = StorageManager(
        baseDirectory: tempDir,
        secureStorage: FakeSecureStorage(),
      );
      fakeSmb = IntegrationFakeSmbService();

      controller = TransferController();
      controller.storageManager = storageManager;
      controller.smbPoolManager = fakeSmb;

      await controller.initialize();
      await controller.clearQueue();
      await controller.disconnectSMB();
      controller.host = null;
      controller.share = null;
      controller.username = null;
      controller.password = null;
      controller.domain = null;
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('Complete flow: Connect -> Queue -> Transfer -> Summary', (
      WidgetTester tester,
    ) async {
      // Start the application
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // --- 1. Connection Screen ---
      final hostFinder = find.ancestor(
        of: find.text('Host IP or Name'),
        matching: find.byType(TextFormField),
      );
      final shareFinder = find.ancestor(
        of: find.text('Share Name'),
        matching: find.byType(TextFormField),
      );

      expect(hostFinder, findsOneWidget);
      expect(shareFinder, findsOneWidget);

      // Input SMB details
      await tester.enterText(hostFinder, '192.168.1.100');
      await tester.enterText(shareFinder, 'SharedBackups');
      await tester.pumpAndSettle();

      final connectButton = find.text('Connect to Share');
      expect(connectButton, findsOneWidget);
      await tester.ensureVisible(connectButton);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(connectButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Verify connection state changed
      expect(find.text('Connected'), findsOneWidget);

      // --- 2. Queue Screen ---
      final queueTab = find.text('Queue');
      expect(queueTab, findsOneWidget);
      await tester.tap(queueTab);
      await tester.pumpAndSettle();

      // Inject a local file programmatically as native file picker is not interactive in headless tests
      final testFile = File('${tempDir.path}/integration_test_file.txt');
      testFile.writeAsStringSync('TrueTransfer Integration Test Content');
      final fileSize = testFile.lengthSync();

      await controller.addFilesToQueue([testFile.path]);
      await tester.pumpAndSettle();

      // Verify file is shown in queue list
      expect(find.text('integration_test_file.txt'), findsWidgets);

      // --- 3. Backup/Transfer Screen ---
      final backupTab = find.text('Backup');
      expect(backupTab, findsOneWidget);
      await tester.tap(backupTab);
      await tester.pumpAndSettle();

      final startBackupBtn = find.text('Start Backup');
      expect(startBackupBtn, findsOneWidget);

      // Programmatically start transfer to bypass OS-specific headless hit-testing issues
      controller.startTransfer();
      await tester.pump();

      // Wait a brief moment for the status to switch to transferring
      for (int i = 0; i < 20 && !controller.isTransferring; i++) {
        await tester.pump(const Duration(milliseconds: 5));
      }

      // Let the async transfer run and complete
      while (controller.isTransferring) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pumpAndSettle();

      // --- 4. Summary Screen ---
      final summaryTab = find.text('Summary');
      expect(summaryTab, findsOneWidget);
      await tester.tap(summaryTab);
      await tester.pumpAndSettle();

      expect(find.text('Backup Completed Successfully'), findsOneWidget);

      // Formatting helper formats 37 bytes as "37.0 B"
      expect(
        find.text('${fileSize.toDouble().toStringAsFixed(1)} B'),
        findsWidgets,
      );
    });
  });
}
