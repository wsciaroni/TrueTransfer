import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/transfer_queue.dart';
import '../models/smb_connection_info.dart';
import 'secure_storage.dart';

class StorageManager {
  static const String _fileName = 'transfer_queue.json';
  static const String _connectionKey = 'smb_connection_info';
  
  final Directory? baseDirectory;
  final SecureStorage secureStorage;

  StorageManager({
    this.baseDirectory,
    SecureStorage? secureStorage,
  }) : secureStorage = secureStorage ?? SecureStorageImpl();

  Future<File> get _localFile async {
    final directory = baseDirectory ?? await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, _fileName));
  }

  Future<void> saveQueue(TransferQueue queue) async {
    try {
      final file = await _localFile;
      final jsonString = jsonEncode(queue.toJson());
      await file.writeAsString(jsonString);
    } catch (e) {
      // Log error or rethrow
      print('Error saving queue: $e');
    }
  }

  Future<TransferQueue> loadQueue() async {
    try {
      final file = await _localFile;
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
        return TransferQueue.fromJson(jsonMap);
      }
    } catch (e) {
      print('Error loading queue: $e');
    }
    return TransferQueue(items: []);
  }

  Future<void> clearQueue() async {
    try {
      final file = await _localFile;
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('Error clearing queue file: $e');
    }
  }

  // Secure Connection Info Storage Methods
  Future<void> saveConnectionInfo(SmbConnectionInfo info) async {
    try {
      final jsonString = jsonEncode(info.toJson());
      await secureStorage.write(key: _connectionKey, value: jsonString);
    } catch (e) {
      print('Error saving connection info: $e');
    }
  }

  Future<SmbConnectionInfo?> loadConnectionInfo() async {
    try {
      final jsonString = await secureStorage.read(key: _connectionKey);
      if (jsonString != null) {
        final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
        return SmbConnectionInfo.fromJson(jsonMap);
      }
    } catch (e) {
      print('Error loading connection info: $e');
    }
    return null;
  }

  Future<void> clearConnectionInfo() async {
    try {
      await secureStorage.delete(key: _connectionKey);
    } catch (e) {
      print('Error clearing connection info: $e');
    }
  }
}
