import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'names.dart';

const configFileName = 'flutter_forge.yaml';

/// Records compatibility, not a second inventory of routes or features.
final class ProjectConfig {
  ProjectConfig(this.name);

  final DartName name;

  String encode() => 'schema_version: 1\npackage: ${name.value}\n';

  static ProjectConfig read(String root) {
    final config = File(p.join(root, configFileName));
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!config.existsSync() || !pubspec.existsSync()) {
      throw const FormatException(
        'This is not a Flutter Forge project. Use create first, or select --project-dir.',
      );
    }
    final data = loadYaml(config.readAsStringSync());
    final pub = loadYaml(pubspec.readAsStringSync());
    if (data is! YamlMap ||
        data['schema_version'] != 1 ||
        data['package'] is! String) {
      throw const FormatException(
        'Unsupported or malformed flutter_forge.yaml. Expected schema_version: 1 and a package name.',
      );
    }
    final name = DartName.parse(data['package'] as String);
    if (pub is! YamlMap || pub['name'] != name.value) {
      throw const FormatException(
        'Project package name does not match flutter_forge.yaml.',
      );
    }
    final dependencies = pub['dependencies'];
    final flutter = dependencies is YamlMap ? dependencies['flutter'] : null;
    if (flutter is! YamlMap || flutter['sdk'] != 'flutter') {
      throw const FormatException(
        'pubspec.yaml must declare the Flutter SDK dependency.',
      );
    }
    return ProjectConfig(name);
  }
}
