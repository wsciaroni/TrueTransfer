enum TransferStatus {
  pending,
  transferring,
  verifying,
  completed,
  failed,
  paused,
  alreadyBackedUp,
}

class TransferItem {
  final String id;
  final String sourcePath;
  final String remotePath;
  final int fileSize;
  final String remoteDirectory;
  final String? sourceIdentifier;

  TransferStatus status;
  int transferredBytes;
  String? sourceHash;
  String? remoteHash;
  String? errorMessage;
  int resumeOffset; // Bytes successfully written so far

  TransferItem({
    required this.id,
    required this.sourcePath,
    required this.remotePath,
    required this.fileSize,
    this.remoteDirectory = '',
    this.sourceIdentifier,
    this.status = TransferStatus.pending,
    this.transferredBytes = 0,
    this.sourceHash,
    this.remoteHash,
    this.errorMessage,
    this.resumeOffset = 0,
  });

  double get progress {
    if (fileSize == 0) return 0.0;
    return transferredBytes / fileSize;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourcePath': sourcePath,
      'remotePath': remotePath,
      'fileSize': fileSize,
      'remoteDirectory': remoteDirectory,
      'sourceIdentifier': sourceIdentifier,
      'status': status.name,
      'transferredBytes': transferredBytes,
      'sourceHash': sourceHash,
      'remoteHash': remoteHash,
      'errorMessage': errorMessage,
      'resumeOffset': resumeOffset,
    };
  }

  factory TransferItem.fromJson(Map<String, dynamic> json) {
    return TransferItem(
      id: json['id'] as String,
      sourcePath: json['sourcePath'] as String,
      remotePath: json['remotePath'] as String,
      fileSize: json['fileSize'] as int,
      remoteDirectory: (json['remoteDirectory'] ?? '') as String,
      sourceIdentifier: json['sourceIdentifier'] as String?,
      status: TransferStatus.values.byName(json['status'] as String),
      transferredBytes: json['transferredBytes'] as int,
      sourceHash: json['sourceHash'] as String?,
      remoteHash: json['remoteHash'] as String?,
      errorMessage: json['errorMessage'] as String?,
      resumeOffset: (json['resumeOffset'] ?? 0) as int,
    );
  }

  TransferItem copyWith({
    String? id,
    String? sourcePath,
    String? remotePath,
    int? fileSize,
    String? remoteDirectory,
    String? sourceIdentifier,
    TransferStatus? status,
    int? transferredBytes,
    String? sourceHash,
    String? remoteHash,
    String? errorMessage,
    int? resumeOffset,
  }) {
    return TransferItem(
      id: id ?? this.id,
      sourcePath: sourcePath ?? this.sourcePath,
      remotePath: remotePath ?? this.remotePath,
      fileSize: fileSize ?? this.fileSize,
      remoteDirectory: remoteDirectory ?? this.remoteDirectory,
      sourceIdentifier: sourceIdentifier ?? this.sourceIdentifier,
      status: status ?? this.status,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      sourceHash: sourceHash ?? this.sourceHash,
      remoteHash: remoteHash ?? this.remoteHash,
      errorMessage: errorMessage ?? this.errorMessage,
      resumeOffset: resumeOffset ?? this.resumeOffset,
    );
  }
}
