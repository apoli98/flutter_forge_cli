import 'app_dependencies.dart';
import 'profiles.dart';

final _namePattern = RegExp(r'^[a-z][a-z0-9]*(?:_[a-z][a-z0-9]*)*$');

const _reserved = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'native',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
  'dart',
  'flutter',
  'test',
};

/// A name that is safe to use as a directory, Dart identifier, and package.
final class DartName {
  DartName.parse(this.value) {
    if (!_namePattern.hasMatch(value) || _reserved.contains(value)) {
      throw FormatException(
        'Invalid name "$value". Use a nonreserved snake_case name '
        'with each underscore-separated segment starting with a letter.',
      );
    }
  }

  final String value;
  String get memberName =>
      '${value.split('_').first}${className.substring(value.split('_').first.length)}';
  String get className => value
      .split('_')
      .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
      .join();
}

void validateAppName(
  DartName name, {
  Recipe recipe = Recipe.clean,
  LintProfile profile = LintProfile.veryGood,
  StateStyle state = StateStyle.cubit,
  bool infrastructure = false,
}) {
  // flutter_riverpod pins riverpod itself. The app cannot satisfy that package.
  if (state == StateStyle.riverpod && name.value == 'riverpod') {
    throw const FormatException(
      'App name "riverpod" conflicts with a required transitive dependency of '
      'flutter_riverpod. Choose a different package name.',
    );
  }
  if (dependenciesFor(
        recipe,
        state: state,
        infrastructure: infrastructure,
      ).containsKey(name.value) ||
      devDependenciesFor(
        profile,
        state: state,
        infrastructure: infrastructure,
      ).containsKey(name.value)) {
    throw FormatException(
      'App name "${name.value}" conflicts with a bundled direct dependency. '
      'Choose a different package name.',
    );
  }
}

void validateOrganization(String value) {
  final segments = value.split('.');
  if (segments.length < 2 ||
      segments.any(
        (s) =>
            !RegExp(r'^[a-z][a-z0-9]*$').hasMatch(s) || _reserved.contains(s),
      )) {
    throw const FormatException(
      'Organization must use reverse-domain notation, such as com.example.',
    );
  }
}

List<String> parsePlatforms(String value) {
  const supported = {'android', 'ios', 'web', 'macos', 'windows', 'linux'};
  final platforms = value.split(',');
  if (platforms.isEmpty ||
      platforms.any((p) => !supported.contains(p)) ||
      platforms.toSet().length != platforms.length) {
    throw const FormatException(
      'Choose unique comma-separated platforms: android,ios,web,macos,windows,linux.',
    );
  }
  return platforms;
}
