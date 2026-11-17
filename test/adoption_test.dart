import 'dart:convert';
import 'dart:io';

import 'package:flutter_forge_cli/src/cli/prompt.dart';
import 'package:flutter_forge_cli/src/cli/runner.dart';
import 'package:flutter_forge_cli/src/project/names.dart';
import 'package:flutter_forge_cli/src/project/profiles.dart';
import 'package:flutter_forge_cli/src/project/project_config.dart';
import 'package:flutter_forge_cli/src/templates/app_templates.dart';
import 'package:flutter_forge_cli/src/templates/feature_templates.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory temp;
  late StringBuffer out;
  late StringBuffer err;
  late FakeToolchain flutter;
  late int reads;

  Future<int> run(List<String> args, {List<String> answers = const []}) {
    var index = 0;
    return runCli(
      args,
      workingDirectory: temp.path,
      output: out,
      error: err,
      toolchain: flutter,
      environment: const {},
      promptInput: PromptInput(
        hasTerminal: true,
        readLine: () async {
          reads++;
          return index < answers.length ? answers[index++] : null;
        },
      ),
    );
  }

  Map<String, dynamic> result() =>
      jsonDecode(out.toString()) as Map<String, dynamic>;

  void existing({bool complete = false, String? include}) {
    writeFile(
      temp.path,
      'pubspec.yaml',
      complete
          ? appPlan(DartName.parse('existing_app')).files['pubspec.yaml']!
          : 'name: existing_app\ndependencies:\n  flutter:\n    sdk: flutter\n',
    );
    writeFile(temp.path, 'lib/app/router.dart', 'user router: do not change');
    writeFile(temp.path, 'lib/core/di.dart', 'user DI: do not change');
    writeFile(temp.path, 'pubspec.lock', 'user dependency lock');
    if (include != null) {
      writeFile(temp.path, 'analysis_options.yaml', 'include: $include\n');
    }
  }

  setUp(() {
    temp = temporaryDirectory();
    out = StringBuffer();
    err = StringBuffer();
    flutter = FakeToolchain();
    reads = 0;
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test(
    'init derives pubspec name and adopts only metadata with warnings',
    () async {
      existing(
        include: 'package:very_good_analysis/analysis_options.11.0.0.yaml',
      );
      final before = snapshot(temp.path);
      expect(await run(['init', '--project-dir', '.', '--json']), 0);
      final after = snapshot(temp.path)..remove(configFileName);
      expect(after, before);
      final config = ProjectConfig.read(temp.path);
      expect(config.name.value, 'existing_app');
      expect(config.recipe, Recipe.clean);
      expect(config.lintProfile, LintProfile.veryGood);
      final data = result()['data'];
      expect(data['generatedFiles'], [configFileName]);
      expect(
        data['missingDependencies']['devDependencies'],
        contains('bloc_test'),
      );
      expect(data['missingDependencies']['dependencies'], contains('fpdart'));
      expect(
        data['missingDependencies']['commands'],
        contains(
          "flutter pub add 'dev:bloc_test@^10.0.0' 'dev:very_good_analysis@^11.0.0'",
        ),
      );
      expect(
        data['missingDependencies']['commands'],
        contains('flutter pub add --dev flutter_test --sdk flutter'),
      );
      expect(data['warnings'], hasLength(1));
      expect(reads, 0);
      expect(flutter.calls, isEmpty);
      out.clear();
      final adopted = snapshot(temp.path);
      expect(await run(['init', '--json']), 1);
      expect(result()['error']['kind'], 'filesystem');
      expect(snapshot(temp.path), adopted);
    },
  );

  test(
    'init dry-run and explicit profile leave every existing file unchanged',
    () async {
      existing(include: 'package:very_good_analysis/analysis_options.yaml');
      final before = snapshot(temp.path);
      expect(
        await run([
          'init',
          '--recipe',
          'counter',
          '--lint-profile',
          'flutter',
          '--json',
          '--dry-run',
        ]),
        0,
      );
      expect(result()['data']['lintProfile'], 'flutter');
      expect(result()['data']['recipe'], 'counter');
      expect(result()['data']['plannedFiles'], [configFileName]);
      expect(snapshot(temp.path), before);
      expect(flutter.calls, isEmpty);
      expect(reads, 0);
    },
  );

  test(
    'init refuses positional names, non-Flutter and malformed pubspecs',
    () async {
      for (final content in [
        'name: guessed_from_folder\ndependencies: {}\n',
        'dependencies:\n  flutter: {sdk: flutter}\n',
        'name: BadName\ndependencies:\n  flutter: {sdk: flutter}\n',
        'name: [broken',
        'name: demo\ndependencies:\n  flutter: ^1.0.0\n',
      ]) {
        writeFile(temp.path, 'pubspec.yaml', content);
        final before = snapshot(temp.path);
        out.clear();
        expect(await run(['init', '--json']), 64, reason: content);
        expect(result()['success'], isFalse);
        expect(snapshot(temp.path), before);
      }
      out.clear();
      expect(await run(['init', 'unwanted', '--json']), 64);
      expect(reads, 0);
      expect(flutter.calls, isEmpty);
    },
  );

  test(
    'init rejects a dangling metadata symlink without changing its target',
    () async {
      existing();
      final target = p.join(temp.path, 'external_metadata');
      Link(p.join(temp.path, configFileName)).createSync(target);
      expect(await run(['init', '--json']), 1);
      expect(File(target).existsSync(), isFalse);
      expect(Link(p.join(temp.path, configFileName)).targetSync(), target);
      expect(flutter.calls, isEmpty);
    },
  );

  test(
    'feature missing dependencies refuses all writes after successful init',
    () async {
      existing();
      expect(await run(['init', '--json']), 0);
      final before = snapshot(temp.path);
      out.clear();
      expect(await run(['feature', 'orders', '--json']), 64);
      final data = result()['data'];
      expect(
        data['missingDependencies']['devDependencies'],
        contains('bloc_test'),
      );
      expect(data['missingDependencies']['dependencies'], contains('fpdart'));
      expect(snapshot(temp.path), before);
      expect(flutter.calls, isEmpty);
    },
  );

  test(
    'interactive chooser includes name-free init and preserves cancellation',
    () async {
      existing();
      final before = snapshot(temp.path);
      expect(
        await run([], answers: ['3', '.', 'cubit', 'clean', 'auto', 'no']),
        130,
      );
      expect(snapshot(temp.path), before);
      expect(out.toString(), contains('flutter-forge init --project-dir'));
      out.clear();
      expect(
        await run(
          ['init', '--interactive'],
          answers: ['.', 'cubit', 'counter', 'flutter', 'yes'],
        ),
        0,
      );
      expect(ProjectConfig.read(temp.path).recipe, Recipe.counter);
      expect(flutter.calls, isEmpty);
    },
  );

  test(
    'schema v1 retains counter/flutter and metadata is never rewritten',
    () async {
      writeProject(temp.path);
      final before = File(p.join(temp.path, configFileName)).readAsStringSync();
      final config = ProjectConfig.read(temp.path);
      expect(config.recipe, Recipe.counter);
      expect(config.lintProfile, LintProfile.flutter);
      expect(
        await run([
          'feature',
          'orders',
          '--json',
          '--route',
          '/account/orders',
        ]),
        0,
      );
      expect(result()['data']['wiring']['location'], '/account/orders');
      expect(
        result()['data']['wiring']['routeEntry'],
        'ordersRoute(createOrdersCubit: OrdersCubit.new),',
      );
      expect(
        File(p.join(temp.path, configFileName)).readAsStringSync(),
        before,
      );
    },
  );

  test(
    'current schema round trips; invalid and cross-schema fields are refused',
    () {
      existing();
      for (final recipe in Recipe.values) {
        for (final profile in LintProfile.values) {
          writeFile(
            temp.path,
            configFileName,
            ProjectConfig(
              DartName.parse('existing_app'),
              recipe: recipe,
              lintProfile: profile,
            ).encode(),
          );
          final config = ProjectConfig.read(temp.path);
          expect(config.recipe, recipe);
          expect(config.lintProfile, profile);
        }
      }
      for (final content in [
        'schema_version: 1\npackage: existing_app\nrecipe: clean\n',
        'schema_version: 2\npackage: existing_app\n',
        'schema_version: 2\npackage: existing_app\nrecipe: magic\nlint_profile: flutter\n',
        'schema_version: 2\npackage: existing_app\nrecipe: clean\nlint_profile: auto\n',
        'schema_version: 3\npackage: existing_app\n',
        'schema_version: 1.0\npackage: existing_app\n',
      ]) {
        writeFile(temp.path, configFileName, content);
        expect(() => ProjectConfig.read(temp.path), throwsFormatException);
      }
    },
  );

  test(
    'clean feature structured and text wiring share exact constructor chain',
    () async {
      existing(complete: true);
      expect(await run(['init', '--lint-profile', 'very_good', '--json']), 0);
      final before = snapshot(temp.path);
      for (final style in ['cubit', 'bloc']) {
        out.clear();
        expect(
          await run([
            'feature',
            'orders_$style',
            '--state',
            style,
            '--route',
            '/account/orders_$style',
            '--json',
          ]),
          0,
        );
        final wiring = result()['data']['wiring'];
        expect(wiring['imports'], hasLength(5));
        expect(wiring['text'], contains(wiring['routeEntry']));
        for (final import in wiring['imports'] as List<dynamic>) {
          expect(wiring['text'], contains(import));
        }
        expect(wiring['requiredParameter'], contains('Datasource'));
        expect(wiring['location'], '/account/orders_$style');
        expect(wiring['text'], contains('Check route uniqueness manually'));
      }
      for (final entry in before.entries) {
        expect(
          File(p.join(temp.path, entry.key)).readAsStringSync(),
          entry.value,
        );
      }
      expect(flutter.calls, isEmpty);
    },
  );

  test(
    'invalid route overrides fail before all writes and do not prompt',
    () async {
      writeProject(temp.path);
      final before = snapshot(temp.path);
      for (final route in [
        'relative',
        '/:id',
        '/a?b',
        '/a#b',
        '/a%20b',
        '/a\\b',
        "/a'b",
        '/a\$b',
        '/a/../b',
        '//a',
        '/a/',
      ]) {
        out.clear();
        expect(
          await run(['feature', 'orders', '--json', '--route', route]),
          64,
          reason: route,
        );
        expect(result()['error']['message'], contains('absolute static path'));
        expect(snapshot(temp.path), before);
      }
      expect(reads, 0);
    },
  );

  test(
    'dependency inventory excludes unused recipe and profile dependencies',
    () async {
      for (final name in ['fpdart', 'very_good_analysis']) {
        out.clear();
        expect(
          await run([
            'create',
            name,
            '--recipe',
            'counter',
            '--lint-profile',
            'flutter',
            '--dry-run',
            '--json',
          ]),
          0,
        );
      }
      out.clear();
      expect(await run(['create', 'flutter_lints', '--dry-run', '--json']), 0);
      expect(flutter.calls, isEmpty);
      expect(temp.listSync(), isEmpty);
    },
  );

  test('clean apps and features use fpdart', () {
    final package = DartName.parse('example_app');
    final pubspec = appPlan(package).files['pubspec.yaml']!;
    expect(pubspec, contains('fpdart: ^1.2.0'));
    expect(pubspec, isNot(contains('dartz:')));
    for (final style in StateStyle.values) {
      final artifact = featureArtifact(
        package,
        DartName.parse('orders'),
        recipe: Recipe.clean,
        style: style,
      );
      final sources = artifact.plan.files.values.join('\n');
      expect(sources, contains('package:fpdart/fpdart.dart'));
      expect(sources, isNot(contains('package:dartz/')));
    }
  });

  test('all generated local imports use the validated package name', () {
    final package = DartName.parse('real_package');
    for (final recipe in Recipe.values) {
      final artifact = featureArtifact(
        package,
        DartName.parse('orders'),
        recipe: recipe,
      );
      for (final source in artifact.plan.files.values) {
        final imports = RegExp(
          r"^import '([^']+)';",
          multiLine: true,
        ).allMatches(source);
        for (final import in imports) {
          expect(import[1], anyOf(startsWith('package:'), startsWith('dart:')));
        }
      }
    }
  });
}
