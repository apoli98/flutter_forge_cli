import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'app_dependencies.dart';
import 'profiles.dart';

/// Missing direct declarations, not a claim about resolution or compatibility.
final class MissingDependencies {
  MissingDependencies(
    String root,
    Recipe recipe,
    LintProfile profile, {
    StateStyle state = StateStyle.cubit,
    bool infrastructure = false,
  }) {
    final pub = loadYaml(File(p.join(root, 'pubspec.yaml')).readAsStringSync());
    final dependencies = pub is YamlMap ? pub['dependencies'] : null;
    final devDependencies = pub is YamlMap ? pub['dev_dependencies'] : null;
    bool declared(Object? section, String name) {
      if (section is! YamlMap || !section.containsKey(name)) return false;
      if (name == 'flutter' ||
          name == 'flutter_test' ||
          name == 'flutter_localizations') {
        final value = section[name];
        return value is YamlMap && value['sdk'] == 'flutter';
      }
      return true;
    }

    runtime = {
      for (final entry in dependenciesFor(
        recipe,
        state: state,
        infrastructure: infrastructure,
      ).entries)
        if (!declared(dependencies, entry.key)) entry.key: entry.value,
    };
    development = {
      for (final entry in devDependenciesFor(
        profile,
        state: state,
        infrastructure: infrastructure,
      ).entries)
        if (!declared(devDependencies, entry.key) &&
            !declared(dependencies, entry.key))
          entry.key: entry.value,
    };
  }

  late final Map<String, String> runtime;
  late final Map<String, String> development;
  bool get isEmpty => runtime.isEmpty && development.isEmpty;

  List<String> get commands => [
    ..._commands(runtime, development: false),
    ..._commands(development, development: true),
  ];

  List<String> _commands(
    Map<String, String> entries, {
    required bool development,
  }) {
    final packages = Map<String, String>.of(entries)
      ..removeWhere((_, value) => value == '{sdk: flutter}');
    return [
      for (final entry in entries.entries.where(
        (entry) => entry.value == '{sdk: flutter}',
      ))
        'flutter pub add ${development ? '--dev ' : ''}${entry.key} --sdk flutter',
      if (packages.isNotEmpty) _command(packages, development: development),
    ];
  }

  Map<String, Object> toJson() => {
    'dependencies': runtime,
    'devDependencies': development,
    'commands': commands,
    'scope':
        'Direct pubspec declarations only; run pub get and analyze manually.',
  };

  String get instructions => isEmpty
      ? 'Required direct dependencies are declared; resolution was not run.'
      : 'Required dependencies are missing. In the project directory, run:\n'
            '${commands.join('\n')}\nThen run flutter pub get and flutter analyze. '
            'No dependency files were changed.';

  String _command(Map<String, String> entries, {required bool development}) =>
      'flutter pub add '
      '${entries.entries.map((entry) => "'${development ? 'dev:' : ''}${entry.key}@${entry.value}'").join(' ')}';
}
