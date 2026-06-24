// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

import 'package:http/http.dart' as http;

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

  static WindowsReleaseItem? fromJson(Map<String, dynamic> json) {
    final rawName = json['name'] ?? json['fileName'] ?? json['filename'];
    final rawUrl = json['url'] ?? json['downloadUrl'] ?? json['href'];
    if (rawName is! String || rawName.trim().isEmpty) return null;
    final name = rawName.trim();
    final url = rawUrl is String && rawUrl.trim().isNotEmpty
        ? rawUrl.trim()
        : '/releases/windows/$name';
    return WindowsReleaseItem(
      name: name,
      url: url,
      version: json['version'] is String ? json['version'] as String : null,
      build: _asInt(json['build']),
      sizeBytes: _asInt(json['size'] ?? json['sizeBytes']),
      sha256: json['sha256'] is String ? json['sha256'] as String : null,
      publishedAt: json['publishedAt'] is String
          ? DateTime.tryParse(json['publishedAt'] as String)
          : null,
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class WindowsReleaseCatalogService {
  Future<List<WindowsReleaseItem>> fetchReleases() async {
    final indexUri = Uri.base.resolve('/releases/windows/index.json');
    final indexResponse = await http.get(indexUri);
    if (indexResponse.statusCode >= 200 && indexResponse.statusCode < 300) {
      final decoded = jsonDecode(indexResponse.body);
      final rawItems = decoded is List
          ? decoded
          : decoded is Map<String, dynamic>
              ? decoded['releases']
              : null;
      if (rawItems is List) {
        final releases = rawItems
            .whereType<Map>()
            .map((item) => WindowsReleaseItem.fromJson(
                item.map((key, value) => MapEntry('$key', value))))
            .whereType<WindowsReleaseItem>()
            .toList();
        releases.sort((a, b) {
          final byDate = (b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
          return byDate != 0 ? byDate : b.name.compareTo(a.name);
        });
        return releases;
      }
    }

    final latestUri = Uri.base.resolve('/releases/latest.json');
    final latestResponse = await http.get(latestUri);
    if (latestResponse.statusCode < 200 || latestResponse.statusCode >= 300) {
      return const <WindowsReleaseItem>[];
    }
    final latest = jsonDecode(latestResponse.body);
    if (latest is! Map<String, dynamic>) return const <WindowsReleaseItem>[];
    final windows = latest['windows'];
    if (windows is! Map<String, dynamic>) return const <WindowsReleaseItem>[];
    final rawUrl = windows['url'];
    if (rawUrl is! String || rawUrl.trim().isEmpty) {
      return const <WindowsReleaseItem>[];
    }
    final uri = Uri.parse(rawUrl.trim());
    final name = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : 'VentioSetup-${latest['version'] ?? ''}-build${latest['build'] ?? ''}.exe';
    return [
      WindowsReleaseItem(
        name: name,
        url: rawUrl.trim(),
        version: latest['version'] is String ? latest['version'] as String : null,
        build: WindowsReleaseItem._asInt(latest['build']),
        sizeBytes: WindowsReleaseItem._asInt(windows['size']),
        sha256: windows['sha256'] is String ? windows['sha256'] as String : null,
      ),
    ];
  }

  void download(WindowsReleaseItem item) {
    final url = Uri.base.resolve(item.url).toString();
    html.AnchorElement(href: url)
      ..download = item.name
      ..target = '_self'
      ..click();
  }
}
