class Folder {
  const Folder({
    required this.path,
    required this.createdAt,
    this.parentPath,
  });

  final String path;
  final String? parentPath;
  final DateTime createdAt;

  String get name {
    final segments = path.split('/');
    return segments.isEmpty ? path : segments.last;
  }

  int get depth => path.split('/').length - 1;
}
