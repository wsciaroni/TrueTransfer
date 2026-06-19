import 'package:flutter/services.dart';

class PlatformFileOps {
  static const MethodChannel _channel = MethodChannel(
    'com.example.truetransfer/file_ops',
  );

  /// Deletes the original file on Android if the identifier is a content URI.
  ///
  /// Returns `true` if the file was successfully deleted or if there is no
  /// content URI to delete (i.e. identifier is null or not a content:// URI).
  /// Throws an [Exception] if the native deletion was attempted but failed,
  /// so that the caller can report the failure to the user.
  static Future<bool> deleteOriginalFile(String? identifier) async {
    if (identifier == null || identifier.isEmpty) {
      // No content URI to delete — caller should handle local file deletion.
      return false;
    }

    if (identifier.startsWith('content://')) {
      try {
        final result = await _channel.invokeMethod<bool>('deleteFileUri', {
          'uri': identifier,
        });
        if (result == true) {
          return true;
        }
        throw Exception(
          'Failed to delete source file via content resolver: $identifier',
        );
      } catch (e) {
        if (e is Exception &&
            e.toString().contains('Failed to delete source file')) {
          rethrow;
        }
        throw Exception('Failed to delete source file: $identifier — $e');
      }
    }

    return false;
  }
}
