import 'dart:typed_data';
import 'package:dart_smb2/dart_smb2.dart';
import 'smb_service.dart';
import '../models/smb_exceptions.dart';

class SmbPoolManager implements SmbService {
  static final SmbPoolManager _instance = SmbPoolManager._internal();
  factory SmbPoolManager() => _instance;
  SmbPoolManager._internal();

  Smb2Pool? _pool;
  bool _isConnected = false;

  @override
  bool get isConnected => _isConnected && _pool != null;

  @override
  Future<void> connect({
    required String host,
    required String share,
    String? user,
    String? password,
    String? domain,
  }) async {
    try {
      _pool = await Smb2Pool.connect(
        host: host,
        share: share,
        user: user,
        password: password,
        domain: domain,
        workers: 4,
        timeoutSeconds: 30,
      );
      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      throw _wrapException(e);
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      if (_pool != null) {
        await _pool!.disconnect();
      }
    } catch (e) {
      // Ignored during disconnect
    } finally {
      _pool = null;
      _isConnected = false;
    }
  }

  @override
  Future<bool> exists(String path) async {
    _ensureConnected();
    try {
      return await _pool!.exists(path);
    } catch (e) {
      throw _wrapException(e);
    }
  }

  @override
  Future<int> fileSize(String path) async {
    _ensureConnected();
    try {
      return await _pool!.fileSize(path);
    } catch (e) {
      throw _wrapException(e);
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    _ensureConnected();
    try {
      await _pool!.deleteFile(path);
    } catch (e) {
      throw _wrapException(e);
    }
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    _ensureConnected();
    try {
      await _pool!.rename(oldPath, newPath);
    } catch (e) {
      throw _wrapException(e);
    }
  }

  @override
  Future<void> createDirectory(String path) async {
    _ensureConnected();
    try {
      await _pool!.mkdir(path);
    } catch (e) {
      throw _wrapException(e);
    }
  }

  @override
  Future<void> writeFileRange(
    String path,
    Uint8List data, {
    int offset = 0,
  }) async {
    _ensureConnected();
    try {
      await _pool!.writeFileRange(path, data, offset: offset);
    } catch (e) {
      throw _wrapException(e);
    }
  }

  @override
  Future<Uint8List> readFileRange(
    String path, {
    int offset = 0,
    required int length,
  }) async {
    _ensureConnected();
    try {
      return await _pool!.readFileRange(path, offset: offset, length: length);
    } catch (e) {
      throw _wrapException(e);
    }
  }

  void _ensureConnected() {
    if (_pool == null || !_isConnected) {
      throw SmbException(
        type: SmbErrorType.connectionFailed,
        message: 'Not connected to SMB share.',
      );
    }
  }

  Exception _wrapException(dynamic e) {
    if (e is Smb2Exception) {
      final type = switch (e.type) {
        Smb2ErrorType.connection => SmbErrorType.connectionFailed,
        Smb2ErrorType.timeout => SmbErrorType.timeout,
        Smb2ErrorType.auth => SmbErrorType.accessDenied,
        Smb2ErrorType.accessDenied => SmbErrorType.accessDenied,
        Smb2ErrorType.fileNotFound => SmbErrorType.notFound,
        Smb2ErrorType.diskFull => SmbErrorType.diskFull,
        _ => SmbErrorType.unknown,
      };

      var mappedType = type;
      if (e.type == Smb2ErrorType.accessDenied &&
          (e.message.toLowerCase().contains('lock') ||
              e.message.toLowerCase().contains('sharing violation') ||
              e.message.toLowerCase().contains('locked'))) {
        mappedType = SmbErrorType.fileLocked;
      }

      return SmbException(
        type: mappedType,
        message: e.message,
        originalException: e,
      );
    }
    return SmbException(
      type: SmbErrorType.unknown,
      message: e.toString(),
      originalException: e,
    );
  }
}
