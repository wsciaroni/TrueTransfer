import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'smb_service.dart';
import '../utils/platform_file_ops.dart';

class SmbFileTransfer {
  final SmbService smbService;

  SmbFileTransfer(this.smbService);

  /// Transfers a local file to the remote SMB share with progress tracking,
  /// resumption support, integrity checks, and transactional source deletion.
  Future<void> transferFile({
    required String localPath,
    required String remotePath,
    required void Function(int transferredBytes, int totalBytes) onProgress,
    required bool Function() checkCancelled,
    required bool Function() checkPaused,
    int resumeOffset = 0,
    bool deleteSource = true,
    String? sourceIdentifier,
  }) async {
    final localFile = File(localPath);
    if (!await localFile.exists()) {
      throw Exception('Source file does not exist: $localPath');
    }
    final totalBytes = await localFile.length();

    // Ensure intermediate directories exist
    await _ensureParentDirectoriesExist(remotePath);

    final tempPath = '$remotePath.part';

    // 1. Determine resume offset
    int currentOffset = resumeOffset;
    if (currentOffset > 0) {
      if (await smbService.exists(tempPath)) {
        final remoteSize = await smbService.fileSize(tempPath);
        if (remoteSize < currentOffset) {
          currentOffset = remoteSize;
        }
      } else {
        currentOffset = 0;
      }
    }

    // 2. Stream file content in chunks using RandomAccessFile
    final raf = await localFile.open(mode: FileMode.read);
    try {
      if (currentOffset > 0) {
        await raf.setPosition(currentOffset);
      }
      final buffer = Uint8List(64 * 1024); // 64KB chunk buffer
      while (currentOffset < totalBytes) {
        if (checkCancelled()) {
          throw Exception('Transfer cancelled.');
        }
        if (checkPaused()) {
          throw Exception('Transfer paused.');
        }

        final bytesRead = await raf.readInto(buffer);
        if (bytesRead <= 0) break;

        final chunk = Uint8List.sublistView(buffer, 0, bytesRead);
        await smbService.writeFileRange(tempPath, chunk, offset: currentOffset);
        currentOffset += bytesRead;
        onProgress(currentOffset, totalBytes);
      }
    } finally {
      await raf.close();
    }

    // 3. Verify integrity
    // Calculate local SHA-256
    final localHash = await _calculateLocalHash(localFile);

    // Calculate remote SHA-256 of the .part file
    final remoteHash = await _calculateRemoteHash(tempPath, totalBytes);

    if (localHash != remoteHash) {
      // Cleanup remote part file since it is corrupt
      try {
        await smbService.deleteFile(tempPath);
      } catch (_) {}
      throw Exception('Hash mismatch! Source: $localHash, Remote: $remoteHash');
    }

    // 4. Atomic Rename
    if (await smbService.exists(remotePath)) {
      await smbService.deleteFile(remotePath);
    }
    await smbService.rename(tempPath, remotePath);

    // 5. Transactional Deletion
    if (deleteSource) {
      // First attempt to delete the original content URI if on Android/iOS
      await PlatformFileOps.deleteOriginalFile(sourceIdentifier);
      // Clean up the local cached file
      await localFile.delete();
    }
  }

  Future<String> _calculateLocalHash(File file) async {
    final sink = _HashSink();
    final output = sha256.startChunkedConversion(sink);
    final raf = await file.open(mode: FileMode.read);
    try {
      final buffer = Uint8List(64 * 1024); // 64KB buffer
      while (true) {
        final bytesRead = await raf.readInto(buffer);
        if (bytesRead <= 0) break;
        output.add(Uint8List.sublistView(buffer, 0, bytesRead));
      }
    } finally {
      await raf.close();
    }
    output.close();
    return sink.value?.toString() ?? '';
  }

  Future<String> _calculateRemoteHash(String path, int size) async {
    final sink = _HashSink();
    final output = sha256.startChunkedConversion(sink);
    const chunkSize = 1024 * 1024; // 1 MB chunks
    int offset = 0;
    while (offset < size) {
      final toRead = (size - offset) < chunkSize ? (size - offset) : chunkSize;
      final chunk = await smbService.readFileRange(
        path,
        offset: offset,
        length: toRead,
      );
      output.add(chunk);
      offset += chunk.length;
    }
    output.close();
    return sink.value?.toString() ?? '';
  }

  Future<void> _ensureParentDirectoriesExist(String remoteFilePath) async {
    final parts = remoteFilePath.split('/');
    if (parts.length <= 1) return;

    String currentPath = '';
    for (int i = 0; i < parts.length - 1; i++) {
      final part = parts[i];
      if (part.isEmpty) continue;
      currentPath = currentPath.isEmpty ? part : '$currentPath/$part';
      if (!await smbService.exists(currentPath)) {
        try {
          await smbService.createDirectory(currentPath);
        } catch (e) {
          // If another process created it concurrently, verify it exists
          if (!await smbService.exists(currentPath)) {
            rethrow;
          }
        }
      }
    }
  }
}

class _HashSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
