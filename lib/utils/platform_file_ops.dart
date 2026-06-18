import 'package:flutter/services.dart';

class PlatformFileOps {
  static const MethodChannel _channel = MethodChannel(
    'com.example.truetransfer/file_ops',
  );

  /// Deletes the original file on Android if the identifier is a content URI.
  /// Returns true if successful, false otherwise.
  static Future<bool> deleteOriginalFile(String? identifier) async {
    if (identifier == null || identifier.isEmpty) {
      return false;
    }

    if (identifier.startsWith('content://')) {
      try {
        final result = await _channel.invokeMethod<bool>('deleteFileUri', {
          'uri': identifier,
        });
        return result ?? false;
      } catch (e) {
        // Log the failure, return false
        return false;
      }
    }

    return false;
  }
}
