import 'package:dart_style/dart_style.dart';

/// Generated source has the same formatting and import order in every profile.
Map<String, String> formatTemplates(Map<String, String> files) => {
  for (final entry in files.entries)
    entry.key: entry.key.endsWith('.dart') ? _format(entry.value) : entry.value,
};

String _format(String source) {
  // Dart 3.14's concise declarations satisfy current Very Good Analysis.
  source = source.replaceAllMapped(
    RegExp(r'^(  )(const )?([A-Z][A-Za-z0-9_]*)\(', multiLine: true),
    (match) => '${match[1]}${match[2] ?? ''}new(',
  );
  source = source.replaceAllMapped(
    RegExp(r'^(  factory )[A-Z][A-Za-z0-9_]*\.', multiLine: true),
    (match) => match[1]!,
  );
  source = source
      .split('\n')
      .expand((line) {
        if (!line.startsWith('/// ') || line.length <= 80) return [line];
        final lines = <String>[];
        var remaining = line.substring(4);
        while (remaining.length > 76) {
          final end = remaining.lastIndexOf(' ', 76);
          if (end < 1) break;
          lines.add('/// ${remaining.substring(0, end)}');
          remaining = remaining.substring(end + 1);
        }
        return [...lines, '/// $remaining'];
      })
      .join('\n');
  final imports = RegExp(r"^import '[^']+'(?:\s+as \w+)?;", multiLine: true);
  final matches =
      imports
          .allMatches(source)
          .map((m) => m[0]!.replaceAll(RegExp(r'\s+'), ' '))
          .toList()
        ..sort();
  if (matches.isNotEmpty) {
    final dart = matches.where((line) => line.startsWith("import 'dart:"));
    final packages = matches.where((line) => !line.startsWith("import 'dart:"));
    source = [
      if (dart.isNotEmpty) dart.join('\n'),
      if (packages.isNotEmpty) packages.join('\n'),
      source.replaceAll(imports, '').trim(),
    ].join('\n\n');
  }
  return DartFormatter(languageVersion: DartFormatter.latestLanguageVersion)
      .format(source);
}
