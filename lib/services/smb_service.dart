import 'dart:typed_data';

abstract class SmbService {
  Future<void> connect({
    required String host,
    required String share,
    String? user,
    String? password,
    String? domain,
  });

  Future<void> disconnect();

  Future<bool> exists(String path);

  Future<int> fileSize(String path);

  Future<void> deleteFile(String path);

  Future<void> rename(String oldPath, String newPath);

  Future<void> createDirectory(String path);

  Future<void> writeFileRange(String path, Uint8List data, {int offset = 0});

  Future<Uint8List> readFileRange(
    String path, {
    int offset = 0,
    required int length,
  });

  bool get isConnected;
}
