import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'names.dart';
import 'managed_feature.dart';
import 'profiles.dart';
import 'route_path.dart';

const configFileName = 'flutter_forge.yaml';

/// Legacy compatibility metadata, or the schema-4 managed integration registry.
final class ProjectConfig {
  ProjectConfig(
    this.name, {
    this.recipe = Recipe.clean,
    this.lintProfile = LintProfile.veryGood,
    this.state = StateStyle.cubit,
    List<ManagedFeature>? features,
  }) : features = features == null ? null : List.unmodifiable(features);

  final DartName name;
  final Recipe recipe;
  final LintProfile lintProfile;
  final StateStyle state;
  final List<ManagedFeature>? features;
  bool get managed => features != null;

  String encode() =>
      'schema_version: ${managed ? 4 : 3}\npackage: ${name.value}\n'
      'recipe: ${recipe.name}\nlint_profile: ${lintProfile.configName}\n'
      'state: ${state.name}\n'
      '${managed ? 'features:\n${features!.map((feature) => '  - name: ${feature.name.value}\n    state: ${feature.state.name}\n    recipe: ${feature.recipe.name}\n    route: ${feature.route.value}\n').join()}' : ''}';

  static DartName readPackage(String root) {
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw const FormatException('Expected an existing Flutter pubspec.yaml.');
    }
    final pub = loadYaml(pubspec.readAsStringSync());
    if (pub is! YamlMap || pub['name'] is! String) {
      throw const FormatException('pubspec.yaml must declare a package name.');
    }
    final dependencies = pub['dependencies'];
    final flutter = dependencies is YamlMap ? dependencies['flutter'] : null;
    if (flutter is! YamlMap || flutter['sdk'] != 'flutter') {
      throw const FormatException(
        'pubspec.yaml must declare the Flutter SDK dependency.',
      );
    }
    return DartName.parse(pub['name'] as String);
  }

  static LintProfile resolveLint(String root, String value) {
    if (value != 'auto') return parseLintProfile(value);
    final options = File(p.join(root, 'analysis_options.yaml'));
    if (options.existsSync()) {
      final data = loadYaml(options.readAsStringSync());
      if (data is YamlMap &&
          data['include'] is String &&
          (data['include'] as String).startsWith(
            'package:very_good_analysis/',
          )) {
        return LintProfile.veryGood;
      }
    }
    return LintProfile.flutter;
  }

  static ProjectConfig read(String root) {
    final config = File(p.join(root, configFileName));
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!config.existsSync() || !pubspec.existsSync()) {
      throw const FormatException(
        'This is not a Flutter Forge project. Use create first, or select --project-dir.',
      );
    }
    final data = loadYaml(config.readAsStringSync());
    if (data is! YamlMap ||
        data['schema_version'] is! int ||
        ![1, 2, 3, 4].contains(data['schema_version']) ||
        data['package'] is! String) {
      throw const FormatException(
        'Unsupported or malformed flutter_forge.yaml. Expected schema_version: 1, 2, 3, or 4 and a package name.',
      );
    }
    final name = DartName.parse(data['package'] as String);
    if (readPackage(root).value != name.value) {
      throw const FormatException(
        'Project package name does not match flutter_forge.yaml.',
      );
    }
    if (data['schema_version'] == 1) {
      if (data.keys.any(
        (key) => !['schema_version', 'package'].contains(key),
      )) {
        throw const FormatException('Unexpected schema_version: 1 fields.');
      }
      return ProjectConfig(
        name,
        recipe: Recipe.counter,
        lintProfile: LintProfile.flutter,
      );
    }
    final version = data['schema_version'];
    if (data['recipe'] is! String ||
        !Recipe.values.any((recipe) => recipe.name == data['recipe']) ||
        !['flutter', 'very_good'].contains(data['lint_profile']) ||
        ((version == 3 || version == 4) &&
            !StateStyle.values.any((state) => state.name == data['state'])) ||
        data.keys.any(
          (key) => ![
            'schema_version',
            'package',
            'recipe',
            'lint_profile',
            if (version == 3 || version == 4) 'state',
            if (version == 4) 'features',
          ].contains(key),
        )) {
      throw FormatException(
        'Malformed schema_version: $version recipe, lint_profile, or state.',
      );
    }
    return ProjectConfig(
      name,
      recipe: Recipe.values.byName(data['recipe'] as String),
      lintProfile: parseLintProfile(data['lint_profile'] as String),
      state: version == 3 || version == 4
          ? StateStyle.values.byName(data['state'] as String)
          : StateStyle.cubit,
      features: version == 4 ? _readFeatures(data['features']) : null,
    );
  }

  static List<ManagedFeature> _readFeatures(Object? value) {
    if (value is! YamlList || value.isEmpty) {
      throw const FormatException(
        'Schema 4 requires a nonempty features registry.',
      );
    }
    final features = <ManagedFeature>[];
    final names = <String>{};
    final routes = <String>{};
    final symbols = <String>{};
    for (final entry in value) {
      if (entry is! YamlMap ||
          entry.length != 4 ||
          entry['name'] is! String ||
          entry['route'] is! String ||
          !StateStyle.values.any((state) => state.name == entry['state']) ||
          !Recipe.values.any((recipe) => recipe.name == entry['recipe'])) {
        throw const FormatException(
          'Malformed schema-4 feature registry entry.',
        );
      }
      final name = DartName.parse(entry['name'] as String);
      final route = RoutePath.parse(entry['route'] as String);
      final state = StateStyle.values.byName(entry['state'] as String);
      if (!names.add(name.value) ||
          !routes.add(route.value.toLowerCase()) ||
          !symbols.add('${name.className}${state.controllerSuffix}')) {
        throw const FormatException(
          'Duplicate managed feature name, symbol, or route.',
        );
      }
      features.add(
        ManagedFeature(
          name,
          state,
          Recipe.values.byName(entry['recipe'] as String),
          route,
        ),
      );
    }
    if (!routes.contains('/')) {
      throw const FormatException(
        'Managed registry must include the home route /.',
      );
    }
    return features;
  }
}
