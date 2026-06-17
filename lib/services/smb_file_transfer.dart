import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'smb_service.dart';

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
  }) async {
    final localFile = File(localPath);
    if (!await localFile.exists()) {
      throw Exception('Source file does not exist: $localPath');
    }
    final totalBytes = await localFile.length();
    final tempPath = remotePath + '.part';

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

    // 2. Stream file content in chunks
    final inputStream = localFile.openRead(currentOffset);
    try {
      await for (final chunk in inputStream) {
        if (checkCancelled()) {
          throw Exception('Transfer cancelled.');
        }
        if (checkPaused()) {
          throw Exception('Transfer paused.');
        }

        final uint8Chunk = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        
        await smbService.writeFileRange(tempPath, uint8Chunk, offset: currentOffset);
        currentOffset += uint8Chunk.length;
        onProgress(currentOffset, totalBytes);
      }
    } catch (e) {
      // Preserve .part file for resume capacity, just rethrow
      rethrow;
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
    await localFile.delete();
  }

  Future<String> _calculateLocalHash(File file) async {
    final sink = _HashSink();
    final output = sha256.startChunkedConversion(sink);
    final input = file.openRead();
    await for (final chunk in input) {
      output.add(chunk);
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
      final chunk = await smbService.readFileRange(path, offset: offset, length: toRead);
      output.add(chunk);
      offset += chunk.length;
    }
    output.close();
    return sink.value?.toString() ?? '';
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
