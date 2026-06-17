enum SmbErrorType {
  connectionFailed,
  accessDenied,
  fileLocked,
  diskFull,
  timeout,
  notFound,
  unknown,
}

class SmbException implements Exception {
  final SmbErrorType type;
  final String message;
  final dynamic originalException;

  SmbException({
    required this.type,
    required this.message,
    this.originalException,
  });

  @override
  String toString() {
    return 'SmbException(${type.name}): $message';
  }
}
