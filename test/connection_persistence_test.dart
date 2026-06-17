import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:truetransfer/models/smb_connection_info.dart';
import 'package:truetransfer/utils/secure_storage.dart';
import 'package:truetransfer/utils/storage_manager.dart';
import 'package:truetransfer/services/transfer_controller.dart';
import 'package:truetransfer/services/smb_service.dart';

class FakeSmbService implements SmbService {
  @override
  bool isConnected = false;

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
  Future<void> createDirectory(String path) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SmbConnectionInfo Model Tests', () {
    test('toJson and fromJson should serialize/deserialize correctly', () {
      final info = SmbConnectionInfo(
        host: '192.168.1.100',
        share: 'backups',
        username: 'user1',
        password: 'securePassword123',
        domain: 'WORKGROUP',
      );

      final json = info.toJson();
      final decoded = SmbConnectionInfo.fromJson(json);

      expect(decoded.host, '192.168.1.100');
      expect(decoded.share, 'backups');
      expect(decoded.username, 'user1');
      expect(decoded.password, 'securePassword123');
      expect(decoded.domain, 'WORKGROUP');
    });

    test('fromJson handles null optional fields', () {
      final json = {
        'host': '10.0.0.5',
        'share': 'public',
      };
      
      final decoded = SmbConnectionInfo.fromJson(json);
      expect(decoded.host, '10.0.0.5');
      expect(decoded.share, 'public');
      expect(decoded.username, isNull);
      expect(decoded.password, isNull);
      expect(decoded.domain, isNull);
    });
  });

  group('StorageManager Connection Persistence Tests', () {
    late Directory tempDir;
    late FakeSecureStorage fakeSecureStorage;
    late StorageManager storageManager;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('truetransfer_test_storage');
      fakeSecureStorage = FakeSecureStorage();
      storageManager = StorageManager(
        baseDirectory: tempDir,
        secureStorage: fakeSecureStorage,
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('should save and load connection info successfully', () async {
      final info = SmbConnectionInfo(
        host: '192.168.1.10',
        share: 'media',
        username: 'guest',
      );

      await storageManager.saveConnectionInfo(info);
      
      // Verify stored key in fake secure storage
      final storedVal = await fakeSecureStorage.read(key: 'smb_connection_info');
      expect(storedVal, isNotNull);

      final loadedInfo = await storageManager.loadConnectionInfo();
      expect(loadedInfo, isNotNull);
      expect(loadedInfo!.host, '192.168.1.10');
      expect(loadedInfo.share, 'media');
      expect(loadedInfo.username, 'guest');
      expect(loadedInfo.password, isNull);
    });

    test('should return null if no connection info is saved', () async {
      final loadedInfo = await storageManager.loadConnectionInfo();
      expect(loadedInfo, isNull);
    });

    test('should clear connection info successfully', () async {
      final info = SmbConnectionInfo(
        host: '192.168.1.10',
        share: 'media',
      );

      await storageManager.saveConnectionInfo(info);
      await storageManager.clearConnectionInfo();

      final loadedInfo = await storageManager.loadConnectionInfo();
      expect(loadedInfo, isNull);
    });
  });

  group('TransferController Credentials Integration Tests', () {
    late Directory tempDir;
    late FakeSecureStorage fakeSecureStorage;
    late StorageManager storageManager;
    late FakeSmbService fakeSmbService;
    late TransferController controller;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('truetransfer_test_controller');
      fakeSecureStorage = FakeSecureStorage();
      storageManager = StorageManager(
        baseDirectory: tempDir,
        secureStorage: fakeSecureStorage,
      );
      fakeSmbService = FakeSmbService();
      
      controller = TransferController();
      controller.storageManager = storageManager;
      controller.smbPoolManager = fakeSmbService;

      // Reset properties
      controller.host = null;
      controller.share = null;
      controller.username = null;
      controller.password = null;
      controller.domain = null;
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('initialize loads credentials into controller', () async {
      final info = SmbConnectionInfo(
        host: '192.168.1.15',
        share: 'backups',
        username: 'backup_user',
        password: 'pwd',
        domain: 'WORKGROUP',
      );
      await storageManager.saveConnectionInfo(info);

      await controller.initialize();

      expect(controller.host, '192.168.1.15');
      expect(controller.share, 'backups');
      expect(controller.username, 'backup_user');
      expect(controller.password, 'pwd');
      expect(controller.domain, 'WORKGROUP');
    });

    test('successful connectSMB saves credentials', () async {
      // Connect call
      final success = await controller.connectSMB(
        host: '10.0.0.10',
        share: 'secure',
        user: 'admin',
        password: 'password123',
        domain: 'MYDOM',
      );

      expect(success, isTrue);
      expect(controller.host, '10.0.0.10');
      expect(controller.share, 'secure');
      expect(controller.username, 'admin');
      expect(controller.password, 'password123');
      expect(controller.domain, 'MYDOM');

      // Verify they are persisted in secure storage
      final loadedInfo = await storageManager.loadConnectionInfo();
      expect(loadedInfo, isNotNull);
      expect(loadedInfo!.host, '10.0.0.10');
      expect(loadedInfo.share, 'secure');
      expect(loadedInfo.username, 'admin');
      expect(loadedInfo.password, 'password123');
      expect(loadedInfo.domain, 'MYDOM');
    });
  });
}
