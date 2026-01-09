class CleanResult {
  final List<String> paths;
  final double totalSizeMB;
  final int totalFiles;

  CleanResult({
    required this.paths,
    required this.totalSizeMB,
    required this.totalFiles,
  });
}
