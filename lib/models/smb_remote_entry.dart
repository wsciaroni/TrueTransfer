class SmbRemoteEntry {
  final String name;
  final bool isDirectory;
  final int size;

  SmbRemoteEntry({
    required this.name,
    required this.isDirectory,
    required this.size,
  });
}
