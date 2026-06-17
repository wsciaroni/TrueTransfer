import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/transfer_queue.dart';

class StorageManager {
  static const String _fileName = 'transfer_queue.json';
  final Directory? baseDirectory;

  StorageManager({this.baseDirectory});

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
}
