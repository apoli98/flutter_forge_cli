import 'dart:io';

import 'package:path/path.dart' as p;

import '../project/names.dart';
import '../templates/infrastructure_templates.dart';
import '../templates/template_format.dart';
import 'generation_plan.dart';

/// Managed code generation uses fixed configs, not user-selected destinations.
/// This runs before writes even with --no-pub, so unsafe projects never register.
void checkCodegenOutputs(
  String root,
  DartName package, {
  Map<String, String> pending = const {},
}) {
  final resolved = canonicalRoot(root);
  final expected = formatTemplates(infrastructureFiles(package));
  for (final relative in [
    'l10n.yaml',
    'build.yaml',
    'tool/fix_localization_imports.dart',
  ]) {
    _checkPath(resolved, relative);
    if (!pending.containsKey(relative) &&
        FileSystemEntity.typeSync(
              p.join(resolved, relative),
              followLinks: false,
            ) !=
            FileSystemEntityType.file) {
      throw FileSystemException(
        'Managed codegen configuration must be a regular file',
        p.join(resolved, relative),
      );
    }
    final contents =
        pending[relative] ??
        File(p.join(resolved, relative)).readAsStringSync();
    if (contents != expected[relative]) {
      throw FileSystemException(
        'Managed codegen configuration is edited; refusing all writes and processes. Restore the generated configuration or run code generation manually',
        p.join(resolved, relative),
      );
    }
  }
  for (final entity in Directory(resolved).listSync(followLinks: false)) {
    final name = p.basename(entity.path);
    if ((name.startsWith('build.') &&
            name.endsWith('.yaml') &&
            name != 'build.yaml') ||
        name.endsWith('.build.yaml')) {
      throw FileSystemException(
        'Alternate build configurations are not supported by managed generation',
        entity.path,
      );
    }
  }
  for (final relative in [
    'lib',
    'test',
    'integration_test',
    'tool',
    'bin',
    'example',
    'benchmark',
    'web',
    'assets',
    '.dart_tool/build',
  ]) {
    _checkPath(resolved, relative);
    final directory = Directory(p.join(resolved, relative));
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (FileSystemEntity.typeSync(entity.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw FileSystemException(
          'Refusing a symbolic link in managed codegen inputs or outputs',
          entity.path,
        );
      }
    }
  }
  for (final relative in [
    'pubspec.yaml',
    'pubspec.lock',
    '.dart_tool/package_config.json',
    '.dart_tool/package_graph.json',
    '.flutter-plugins-dependencies',
  ]) {
    _checkPath(resolved, relative);
  }
  _checkLocalizationBuild(resolved);
}

void _checkLocalizationBuild(String root) {
  _checkPath(root, 'build');
  _checkPath(root, 'build/.last_build_id');
  final build = Directory(p.join(root, 'build'));
  if (!build.existsSync()) return;
  // Flutter's Environment hashes its configuration into build/<md5>/.
  // Do not traverse unrelated native output trees, which can contain links.
  for (final entity in build.listSync(followLinks: false)) {
    final name = p.basename(entity.path);
    if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(name)) continue;
    _checkPath(root, 'build/$name');
    for (final file in [
      'gen_l10n_inputs_and_outputs.json',
      'gen_localizations.d',
      'gen_localizations.stamp',
      '.filecache',
      'outputs.json',
    ]) {
      _checkPath(root, 'build/$name/$file');
    }
  }
}

void _checkPath(String root, String relative) {
  var current = root;
  for (final segment in relative.split('/')) {
    current = p.join(current, segment);
    if (FileSystemEntity.typeSync(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException(
        'Refusing a symbolic link in a codegen path',
        current,
      );
    }
  }
}
