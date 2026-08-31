class WindowsReleaseItem {
  const WindowsReleaseItem({
    required this.name,
    required this.url,
    this.version,
    this.build,
    this.sizeBytes,
    this.sha256,
    this.publishedAt,
  });

  final String name;
  final String url;
  final String? version;
  final int? build;
  final int? sizeBytes;
  final String? sha256;
  final DateTime? publishedAt;
}

class WindowsReleaseCatalogService {
  Future<List<WindowsReleaseItem>> fetchReleases() async =>
      const <WindowsReleaseItem>[];

  void download(WindowsReleaseItem item) {}
}
