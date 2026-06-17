import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/transfer_item.dart';
import '../models/transfer_queue.dart';
import '../models/smb_exceptions.dart';
import 'smb_pool_manager.dart';
import 'smb_file_transfer.dart';
import '../utils/storage_manager.dart';
import '../models/smb_connection_info.dart';
import 'smb_service.dart';

class TransferController extends ChangeNotifier {
  static final TransferController _instance = TransferController._internal();
  factory TransferController() => _instance;
  TransferController._internal();

  StorageManager _storageManager = StorageManager();
  SmbService _smbPoolManager = SmbPoolManager();

  @visibleForTesting
  set storageManager(StorageManager manager) => _storageManager = manager;

  @visibleForTesting
  set smbPoolManager(SmbService manager) => _smbPoolManager = manager;

  TransferQueue queue = TransferQueue(items: []);
  
  // SMB Credentials & Info
  String? host;
  String? share;
  String? username;
  String? password;
  String? domain;

  bool _isConnecting = false;
  String? _connectionError;

  bool _isTransferring = false;
  bool _isPaused = false;
  bool _isCancelled = false;
  bool _isReconnecting = false;
  double _speedMBps = 0.0;
  int _totalBytesMoved = 0;
  int _totalStorageReclaimed = 0;

  // Getters
  bool get isConnected => _smbPoolManager.isConnected;
  bool get isConnecting => _isConnecting;
  String? get connectionError => _connectionError;
  bool get isTransferring => _isTransferring;
  bool get isPaused => _isPaused;
  bool get isReconnecting => _isReconnecting;
  double get speedMBps => _speedMBps;
  int get totalBytesMoved => _totalBytesMoved;
  int get totalStorageReclaimed => _totalStorageReclaimed;

  Future<void> initialize() async {
    queue = await _storageManager.loadQueue();
    // Count previously completed items towards metrics
    for (final item in queue.items) {
      if (item.status == TransferStatus.completed) {
        _totalBytesMoved += item.fileSize;
        _totalStorageReclaimed += item.fileSize;
      }
    }

    // Load saved SMB connection info
    final savedInfo = await _storageManager.loadConnectionInfo();
    if (savedInfo != null) {
      host = savedInfo.host;
      share = savedInfo.share;
      username = savedInfo.username;
      password = savedInfo.password;
      domain = savedInfo.domain;
    }

    notifyListeners();
  }

  Future<bool> connectSMB({
    required String host,
    required String share,
    String? user,
    String? password,
    String? domain,
  }) async {
    _isConnecting = true;
    _connectionError = null;
    notifyListeners();

    try {
      await _smbPoolManager.connect(
        host: host,
        share: share,
        user: user,
        password: password,
        domain: domain,
      );

      this.host = host;
      this.share = share;
      username = user;
      this.password = password;
      this.domain = domain;

      // Save connection info between sessions
      final info = SmbConnectionInfo(
        host: host,
        share: share,
        username: user,
        password: password,
        domain: domain,
      );
      await _storageManager.saveConnectionInfo(info);

      _isConnecting = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isConnecting = false;
      _connectionError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnectSMB() async {
    await _smbPoolManager.disconnect();
    notifyListeners();
  }

  Future<void> addFilesToQueue(List<String> filePaths) async {
    for (final path in filePaths) {
      final file = File(path);
      if (await file.exists()) {
        final size = await file.length();
        final name = p.basename(path);
        
        final item = TransferItem(
          id: '${DateTime.now().microsecondsSinceEpoch}_${path.hashCode}',
          sourcePath: path,
          remotePath: name, // Placed at root of share
          fileSize: size,
        );
        queue.add(item);
      }
    }
    await _storageManager.saveQueue(queue);
    notifyListeners();
  }

  Future<void> addFolderToQueue(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return;

    final List<File> files = [];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        files.add(entity);
      }
    }

    for (final file in files) {
      final size = await file.length();
      final relativePath = p.relative(file.path, from: dir.parent.path);
      final remotePath = relativePath.replaceAll('\\', '/');

      final item = TransferItem(
        id: '${DateTime.now().microsecondsSinceEpoch}_${file.path.hashCode}',
        sourcePath: file.path,
        remotePath: remotePath,
        fileSize: size,
      );
      queue.add(item);
    }
    await _storageManager.saveQueue(queue);
    notifyListeners();
  }

  Future<void> removeItemFromQueue(String id) async {
    queue.remove(id);
    await _storageManager.saveQueue(queue);
    notifyListeners();
  }

  Future<void> clearQueue() async {
    queue.clear();
    _totalBytesMoved = 0;
    _totalStorageReclaimed = 0;
    await _storageManager.clearQueue();
    notifyListeners();
  }

  void startTransfer() {
    if (!isConnected) return;
    _processQueue();
  }

  void pauseTransfer() {
    _isPaused = true;
    notifyListeners();
  }

  void resumeTransfer() {
    if (!isConnected) return;
    _isPaused = false;
    _processQueue();
  }

  void cancelTransfer() {
    _isCancelled = true;
    _isTransferring = false;
    _isPaused = false;
    notifyListeners();
  }

  Future<void> _processQueue() async {
    if (!isConnected) return;
    if (_isTransferring && !_isPaused) return;

    _isTransferring = true;
    _isPaused = false;
    _isCancelled = false;
    notifyListeners();

    while (_isTransferring && !_isPaused && !_isCancelled) {
      final nextItemIndex = queue.items.indexWhere(
        (item) => item.status == TransferStatus.pending || 
                  item.status == TransferStatus.failed || 
                  item.status == TransferStatus.paused
      );

      if (nextItemIndex == -1) {
        _isTransferring = false;
        notifyListeners();
        break;
      }

      final item = queue.items[nextItemIndex];
      item.status = TransferStatus.transferring;
      item.errorMessage = null;
      notifyListeners();

      final fileTransfer = SmbFileTransfer(_smbPoolManager);
      final stopwatch = Stopwatch()..start();

      try {
        await fileTransfer.transferFile(
          localPath: item.sourcePath,
          remotePath: item.remotePath,
          resumeOffset: item.resumeOffset,
          onProgress: (transferred, total) {
            item.transferredBytes = transferred;
            item.resumeOffset = transferred;

            final seconds = stopwatch.elapsedMilliseconds / 1000.0;
            if (seconds > 0) {
              final speedBytesPerSec = transferred / seconds;
              _speedMBps = speedBytesPerSec / (1024 * 1024);
            }

            _storageManager.saveQueue(queue);
            notifyListeners();
          },
          checkCancelled: () => _isCancelled,
          checkPaused: () => _isPaused,
        );

        item.status = TransferStatus.completed;
        _totalBytesMoved += item.fileSize;
        _totalStorageReclaimed += item.fileSize;
        await _storageManager.saveQueue(queue);
        notifyListeners();
      } catch (e) {
        if (_isCancelled) {
          item.status = TransferStatus.paused;
          _isTransferring = false;
        } else if (_isPaused) {
          item.status = TransferStatus.paused;
          _isTransferring = false;
        } else {
          item.status = TransferStatus.failed;
          item.errorMessage = e.toString();

          if (e is SmbException && (e.type == SmbErrorType.connectionFailed || e.type == SmbErrorType.timeout)) {
            _isReconnecting = true;
            notifyListeners();

            bool reconnected = false;
            for (int i = 0; i < 3; i++) {
              if (_isCancelled || _isPaused) break;
              await Future.delayed(const Duration(seconds: 5));
              try {
                await _smbPoolManager.connect(
                  host: host!,
                  share: share!,
                  user: username,
                  password: password,
                  domain: domain,
                );
                reconnected = true;
                break;
              } catch (_) {}
            }

            _isReconnecting = false;
            if (reconnected && !_isCancelled && !_isPaused) {
              continue; // Retry transfer of current file
            } else {
              _isTransferring = false;
            }
          } else {
            _isTransferring = false;
          }
        }
        await _storageManager.saveQueue(queue);
        notifyListeners();
        break;
      }
    }
  }
}
