import 'dart:io';
import 'dart:typed_data';

Future<List<ByteData>?> loadSystemPdfFontPairBytes() async {
  final candidates = <List<String>>[];

  if (Platform.isWindows) {
    final windowsDirectory =
        Platform.environment['WINDIR'] ?? Platform.environment['SystemRoot'];
    if (windowsDirectory != null && windowsDirectory.trim().isNotEmpty) {
      final fonts = '$windowsDirectory\\Fonts';
      candidates.addAll(<List<String>>[
        <String>['$fonts\\tahoma.ttf', '$fonts\\tahomabd.ttf'],
        <String>['$fonts\\arial.ttf', '$fonts\\arialbd.ttf'],
        <String>['$fonts\\segoeui.ttf', '$fonts\\segoeuib.ttf'],
      ]);
    }
  } else if (Platform.isLinux) {
    candidates.addAll(<List<String>>[
      <String>[
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
        '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
      ],
      <String>[
        '/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf',
        '/usr/share/fonts/truetype/noto/NotoSansArabic-Bold.ttf',
      ],
    ]);
  } else if (Platform.isAndroid) {
    candidates.addAll(<List<String>>[
      <String>[
        '/system/fonts/NotoSansArabic-Regular.ttf',
        '/system/fonts/NotoSansArabic-Bold.ttf',
      ],
      <String>[
        '/system/fonts/NotoNaskhArabic-Regular.ttf',
        '/system/fonts/NotoNaskhArabic-Bold.ttf',
      ],
    ]);
  }

  for (final pair in candidates) {
    final regular = File(pair[0]);
    final bold = File(pair[1]);
    if (!await regular.exists() || !await bold.exists()) continue;
    try {
      final regularBytes = await regular.readAsBytes();
      final boldBytes = await bold.readAsBytes();
      return <ByteData>[
        ByteData.sublistView(regularBytes),
        ByteData.sublistView(boldBytes),
      ];
    } catch (_) {
      // Try the next pair.
    }
  }
  return null;
}
