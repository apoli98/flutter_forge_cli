import 'dart:io';

import 'package:path/path.dart' as p;

/// Complete file contents keyed by portable relative path.
final class GenerationPlan {
  GenerationPlan(
    Map<String, String> files, {
    List<String> absentDirectories = const [],
  }) : files = Map.unmodifiable(files),
       absentDirectories = List.unmodifiable(absentDirectories) {
    for (final path in [...files.keys, ...absentDirectories]) {
      if (path.isEmpty ||
          path.contains('\\') ||
          p.posix.isAbsolute(path) ||
          path.split('/').any((s) => s.isEmpty || s == '.' || s == '..') ||
          path.contains(':')) {
        throw FormatException('Unsafe generated path: $path');
      }
    }
    for (final path in files.keys) {
      if (files.keys.any((other) => other.startsWith('$path/'))) {
        throw FormatException('Generated file is also a parent: $path');
      }
    }
  }

  final Map<String, String> files;
  final List<String> absentDirectories;
}

/// Resolves user-selected root aliases, but never links inside the output tree.
String canonicalRoot(String root) {
  var ancestor = p.normalize(p.absolute(root));
  final suffix = <String>[];
  while (FileSystemEntity.typeSync(ancestor, followLinks: false) ==
      FileSystemEntityType.notFound) {
    suffix.insert(0, p.basename(ancestor));
    ancestor = p.dirname(ancestor);
  }
  return p.joinAll([Directory(ancestor).resolveSymbolicLinksSync(), ...suffix]);
}

final class FileWriter {
  static const _freshScaffoldFiles = {
    'lib/main.dart',
    'pubspec.yaml',
    'test/widget_test.dart',
    'analysis_options.yaml',
  };

  void check(String root, GenerationPlan plan) => _check(root, plan, const {});

  /// Validate every owned replacement and every new path before any write.
  /// Expected contents come from the typed registry renderer, not path metadata.
  void checkManaged(
    String root,
    GenerationPlan plan,
    Map<String, String> expected,
  ) {
    if (expected.keys.any((path) => !plan.files.containsKey(path))) {
      throw ArgumentError('Every managed replacement must be in the plan.');
    }
    _check(root, plan, expected.keys.toSet());
    for (final entry in expected.entries) {
      final file = File(p.join(canonicalRoot(root), entry.key));
      if (!file.existsSync() || file.readAsStringSync() != entry.value) {
        throw FileSystemException(
          'Forge-managed file is missing or edited; refusing all writes. Restore its generated contents or register manually',
          file.path,
        );
      }
    }
  }

  void writeManaged(
    String root,
    GenerationPlan plan,
    Map<String, String> expected,
  ) {
    checkManaged(root, plan, expected);
    _write(root, plan, expected.keys.toSet());
  }

  void _check(String root, GenerationPlan plan, Set<String> replacements) {
    final absoluteRoot = canonicalRoot(root);
    for (final relative in [...plan.absentDirectories, ...plan.files.keys]) {
      var current = absoluteRoot;
      final rootType = FileSystemEntity.typeSync(current, followLinks: false);
      if (rootType != FileSystemEntityType.notFound &&
          rootType != FileSystemEntityType.directory) {
        throw FileSystemException('Output root is not a directory', current);
      }
      final segments = relative.split('/');
      for (var i = 0; i < segments.length; i++) {
        current = p.join(current, segments[i]);
        final type = FileSystemEntity.typeSync(current, followLinks: false);
        if (type == FileSystemEntityType.link) {
          throw FileSystemException(
            'Refusing an in-tree symbolic link',
            current,
          );
        }
        final last = i == segments.length - 1;
        if (!last &&
            type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.directory) {
          throw FileSystemException(
            'Output parent is not a directory',
            current,
          );
        }
        if (last && type != FileSystemEntityType.notFound) {
          if (!replacements.contains(relative) ||
              type != FileSystemEntityType.file) {
            throw FileSystemException('Refusing existing output', current);
          }
        }
      }
    }
  }

  void write(String root, GenerationPlan plan) => _write(root, plan, const {});

  /// Only for the successful `flutter create` in a previously absent target.
  /// There is intentionally no general-purpose overwrite option.
  void writeFreshApp(String root, GenerationPlan plan) =>
      _write(root, plan, _freshScaffoldFiles);

  void _write(String root, GenerationPlan plan, Set<String> replacements) {
    final resolved = canonicalRoot(root);
    _check(resolved, plan, replacements);
    for (final entry in plan.files.entries) {
      final file = File(p.joinAll([resolved, ...entry.key.split('/')]));
      file.parent.createSync(recursive: true);
      if (!replacements.contains(entry.key)) {
        file.createSync(exclusive: true);
      }
      file.writeAsStringSync(entry.value);
    }
  }
}
