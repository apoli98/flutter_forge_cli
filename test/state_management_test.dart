import 'dart:convert';
import 'dart:io';

import 'package:flutter_forge_cli/src/cli/prompt.dart';
import 'package:flutter_forge_cli/src/cli/runner.dart';
import 'package:flutter_forge_cli/src/project/app_dependencies.dart';
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
  late FakeToolchain flutter;

  Future<int> run(List<String> args) => runCli(
    [...args, '--json'],
    workingDirectory: temp.path,
    output: out,
    error: StringBuffer(),
    toolchain: flutter,
  );
  Map<String, dynamic> data() =>
      (jsonDecode(out.toString()) as Map<String, dynamic>)['data']
          as Map<String, dynamic>;

  setUp(() {
    temp = temporaryDirectory();
    out = StringBuffer();
    flutter = FakeToolchain();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('backend exports cannot shadow valid generated notifier names', () {
    for (final selection in [
      (name: 'change', state: StateStyle.provider),
      (name: 'stream', state: StateStyle.riverpod),
    ]) {
      for (final recipe in Recipe.values) {
        final files = featureArtifact(
          DartName.parse('demo'),
          DartName.parse(selection.name),
          style: selection.state,
          recipe: recipe,
        ).plan.files;
        final controller =
            files['lib/features/${selection.name}/presentation/${selection.name}_${selection.state.name}.dart']!;
        expect(
          controller,
          contains(
            selection.state == StateStyle.provider
                ? 'class ChangeNotifier extends ui.ChangeNotifier'
                : 'class StreamNotifier extends state_management.Notifier<',
          ),
        );
        for (final source in files.values) {
          for (final backend in [
            'flutter_riverpod/flutter_riverpod',
            'provider/provider',
          ]) {
            if (source.contains("import 'package:$backend.dart'")) {
              expect(
                source,
                contains("import 'package:$backend.dart' as state_management;"),
              );
            }
          }
        }
      }
    }
  });

  test('Riverpod reserves its unavoidable transitive package name before side effects', () async {
    for (final dryRun in [true, false]) {
      out.clear();
      expect(
        await run([
          'create',
          'riverpod',
          '--state',
          'riverpod',
          if (dryRun) '--dry-run',
        ]),
        64,
      );
      final result = jsonDecode(out.toString()) as Map<String, dynamic>;
      expect(
        result['error']['message'],
        contains('required transitive dependency'),
      );
      expect(temp.listSync(), isEmpty);
      expect(flutter.calls, isEmpty);
    }
    for (final state in [
      StateStyle.cubit,
      StateStyle.bloc,
      StateStyle.provider,
    ]) {
      out.clear();
      expect(
        await run(['create', 'riverpod', '--state', state.name, '--dry-run']),
        0,
      );
    }
    expect(
      dependenciesFor(Recipe.clean, state: StateStyle.riverpod),
      isNot(contains('riverpod')),
    );
    expect(temp.listSync(), isEmpty);
    expect(flutter.calls, isEmpty);
  });

  test(
    'init and feature overrides reject a Riverpod transitive package collision',
    () async {
      final package = DartName.parse('riverpod');
      writeFile(
        temp.path,
        'pubspec.yaml',
        appPlan(package).files['pubspec.yaml']!,
      );
      final before = snapshot(temp.path);
      expect(await run(['init', '--state', 'riverpod', '--dry-run']), 64);
      expect(snapshot(temp.path), before);
      writeFile(temp.path, configFileName, ProjectConfig(package).encode());
      final adopted = snapshot(temp.path);
      out.clear();
      expect(await run(['feature', 'orders', '--state', 'riverpod']), 64);
      expect(snapshot(temp.path), adopted);
      expect(flutter.calls, isEmpty);
    },
  );

  test(
    'all commands reject unsupported states before prompts or writes',
    () async {
      for (final command in ['create', 'init', 'feature']) {
        out.clear();
        expect(
          await run([
            command,
            if (command != 'init') 'demo',
            '--state',
            'unsupported',
          ]),
          64,
        );
        expect(
          (jsonDecode(out.toString()) as Map<String, dynamic>)['error']['kind'],
          'usage',
        );
        expect(temp.listSync(), isEmpty);
        expect(flutter.calls, isEmpty);
      }
    },
  );

  for (final explicitState in [false, true]) {
    test(
      'wizard retries riverpod after backend selection (explicit: $explicitState)',
      () async {
        final answers = [
          'riverpod',
          if (!explicitState) 'riverpod',
          'counter',
          'flutter',
          'valid_app',
          'yes',
        ].iterator;
        expect(
          await runCli(
            [
              'create',
              '--org',
              'dev.acme',
              '--platforms',
              'ios,android',
              '--output',
              '.',
              '--no-pub',
              '--dry-run',
              if (explicitState) ...['--state', 'riverpod'],
            ],
            workingDirectory: temp.path,
            output: out,
            error: StringBuffer(),
            toolchain: flutter,
            promptInput: PromptInput(
              hasTerminal: true,
              readLine: () async => answers.moveNext() ? answers.current : null,
            ),
          ),
          0,
        );
        expect(out.toString(), contains('required transitive dependency'));
        expect(out.toString(), contains('flutter-forge create valid_app'));
        expect(
          out.toString(),
          isNot(contains('flutter-forge create riverpod')),
        );
        expect(temp.listSync(), isEmpty);
        expect(flutter.calls, isEmpty);
      },
    );
  }

  for (final selected in [StateStyle.cubit, StateStyle.provider]) {
    test('wizard validates dependency names after ${selected.name} resolves', () async {
      final answers = [
        'provider',
        selected.name,
        'counter',
        'flutter',
        if (selected == StateStyle.provider) 'valid_app',
        'yes',
      ].iterator;
      expect(
        await runCli(
          [
            'create',
            '--org',
            'dev.acme',
            '--platforms',
            'ios,android',
            '--output',
            '.',
            '--no-pub',
            '--dry-run',
          ],
          workingDirectory: temp.path,
          output: out,
          error: StringBuffer(),
          toolchain: flutter,
          promptInput: PromptInput(
            hasTerminal: true,
            readLine: () async => answers.moveNext() ? answers.current : null,
          ),
        ),
        0,
      );
      expect(
        out.toString(),
        contains(
          'flutter-forge create ${selected == StateStyle.provider ? 'valid_app' : 'provider'}',
        ),
      );
      expect(
        out.toString().contains('Invalid input:'),
        selected == StateStyle.provider,
      );
      expect(temp.listSync(), isEmpty);
      expect(flutter.calls, isEmpty);
    });
  }

  for (final state in StateStyle.values) {
    test(
      'create ${state.name} persists selection and generates native state',
      () async {
        expect(
          await run(['create', 'demo', '--state', state.name, '--no-pub']),
          0,
        );
        final root = p.join(temp.path, 'demo');
        expect(ProjectConfig.read(root).state, state);
        expect(data()['state'], state.name);
        expect(flutter.calls.single.args, contains('ios,android'));
        expect(
          File(
            p.join(
              root,
              'lib/features/home/presentation/home_${state.name}.dart',
            ),
          ).existsSync(),
          isTrue,
        );
        final source = File(
          p.join(
            root,
            'lib/features/home/presentation/home_${state.name}.dart',
          ),
        ).readAsStringSync();
        expect(
          source,
          contains(switch (state) {
            StateStyle.cubit => 'extends Cubit<HomeState>',
            StateStyle.bloc => 'extends Bloc<HomeEvent, HomeState>',
            StateStyle.riverpod =>
              'extends state_management.Notifier<HomeState>',
            StateStyle.provider => 'extends ui.ChangeNotifier',
          }),
        );
      },
    );

    test(
      'init ${state.name} only adds metadata; feature inherits without mutations',
      () async {
        final package = DartName.parse('demo');
        writeFile(
          temp.path,
          'pubspec.yaml',
          appPlan(package, state: state).files['pubspec.yaml']!,
        );
        writeFile(temp.path, 'lib/app/router.dart', 'user router');
        writeFile(temp.path, 'pubspec.lock', 'user lock');
        final before = snapshot(temp.path);
        expect(
          await run([
            'init',
            '--state',
            state.name,
            '--lint-profile',
            'very_good',
          ]),
          0,
        );
        expect(data()['state'], state.name);
        expect(snapshot(temp.path)..remove(configFileName), before);
        final adopted = snapshot(temp.path);
        out.clear();
        final answers = ['', 'yes'].iterator;
        expect(
          await runCli(
            [
              'feature',
              'orders',
              '--interactive',
              '--project-dir',
              '.',
              '--dry-run',
            ],
            workingDirectory: temp.path,
            output: out,
            error: StringBuffer(),
            toolchain: flutter,
            promptInput: PromptInput(
              hasTerminal: true,
              readLine: () async => answers.moveNext() ? answers.current : null,
            ),
          ),
          0,
        );
        expect(out.toString(), contains('--state ${state.name} --dry-run'));
        expect(snapshot(temp.path), adopted);
        out.clear();
        expect(await run(['feature', 'orders', '--dry-run']), 0);
        expect(data()['state'], state.name);
        expect(snapshot(temp.path), adopted);
        out.clear();
        expect(await run(['feature', 'orders']), 0);
        expect(data()['state'], state.name);
        expect(
          data()['wiring']['routeEntry'],
          contains('createOrders${state.controllerSuffix}'),
        );
        for (final entry in adopted.entries) {
          expect(
            File(p.join(temp.path, entry.key)).readAsStringSync(),
            entry.value,
          );
        }
        expect(flutter.calls, isEmpty);
      },
    );

    for (final recipe in Recipe.values) {
      test(
        '${state.name}/${recipe.name} only includes used dependencies and rejects their names',
        () async {
          final deps = dependenciesFor(recipe, state: state);
          final dev = devDependenciesFor(LintProfile.veryGood, state: state);
          expect(deps.containsKey('flutter_bloc'), state.usesBloc);
          expect(dev.containsKey('bloc_test'), state.usesBloc);
          expect(
            deps.containsKey('flutter_riverpod'),
            state == StateStyle.riverpod,
          );
          expect(deps.containsKey('provider'), state == StateStyle.provider);
          expect(deps.containsKey('fpdart'), recipe == Recipe.clean);
          for (final name in {...deps.keys, ...dev.keys}) {
            out.clear();
            expect(
              await run([
                'create',
                name,
                '--state',
                state.name,
                '--recipe',
                recipe.name,
                '--dry-run',
              ]),
              64,
              reason: name,
            );
          }
          for (final name
              in [
                'flutter_bloc',
                'bloc_test',
                'flutter_riverpod',
                'provider',
              ].where(
                (name) => !deps.containsKey(name) && !dev.containsKey(name),
              )) {
            out.clear();
            expect(
              await run([
                'create',
                name,
                '--state',
                state.name,
                '--recipe',
                recipe.name,
                '--dry-run',
              ]),
              0,
              reason: name,
            );
          }
          expect(temp.listSync(), isEmpty);
          expect(flutter.calls, isEmpty);
        },
      );
    }

    test('wizard confirms ${state.name} and persists selection', () async {
      final answers = [
        'dev.acme',
        'ios,android',
        '.',
        'no',
        state.name,
        'counter',
        'flutter',
        'yes',
      ].iterator;
      expect(
        await runCli(
          ['create', 'demo', '--interactive'],
          workingDirectory: temp.path,
          output: out,
          error: StringBuffer(),
          toolchain: flutter,
          promptInput: PromptInput(
            hasTerminal: true,
            readLine: () async => answers.moveNext() ? answers.current : null,
          ),
        ),
        0,
      );
      expect(
        out.toString(),
        contains('--state ${state.name} --recipe counter'),
      );
      expect(ProjectConfig.read(p.join(temp.path, 'demo')).state, state);
    });
  }

  test('every cross-backend override checks actual dependencies before writes', () async {
    final package = DartName.parse('demo');
    for (final project in StateStyle.values) {
      writeFile(
        temp.path,
        configFileName,
        ProjectConfig(package, state: project).encode(),
      );
      writeFile(
        temp.path,
        'pubspec.yaml',
        appPlan(package, state: project).files['pubspec.yaml']!,
      );
      writeFile(temp.path, 'lib/app/router.dart', 'user router');
      for (final feature in StateStyle.values.where(
        (state) => state != project,
      )) {
        final before = snapshot(temp.path);
        out.clear();
        final sameDeps = project.usesBloc && feature.usesBloc;
        expect(
          await run([
            'feature',
            'orders',
            '--state',
            feature.name,
            '--dry-run',
          ]),
          sameDeps ? 0 : 64,
        );
        expect(data()['state'], feature.name);
        if (!sameDeps) {
          expect(data()['missingDependencies']['commands'], isNotEmpty);
          out.clear();
          expect(await run(['feature', 'orders', '--state', feature.name]), 64);
        }
        expect(snapshot(temp.path), before);
      }
      // A consumer explicitly installs the override's direct dependencies.
      final deps = {
        for (final state in StateStyle.values)
          ...dependenciesFor(Recipe.clean, state: state),
      };
      final dev = {
        for (final state in StateStyle.values)
          ...devDependenciesFor(LintProfile.veryGood, state: state),
      };
      writeFile(
        temp.path,
        'pubspec.yaml',
        'name: demo\ndependencies:\n${deps.entries.map((e) => '  ${e.key}: ${e.value}').join('\n')}\ndev_dependencies:\n${dev.entries.map((e) => '  ${e.key}: ${e.value}').join('\n')}\n',
      );
      final before = snapshot(temp.path);
      out.clear();
      expect(
        await run([
          'feature',
          'override_${project.name}',
          '--state',
          StateStyle
              .values[(project.index + 1) % StateStyle.values.length]
              .name,
        ]),
        0,
      );
      for (final entry in before.entries) {
        expect(
          File(p.join(temp.path, entry.key)).readAsStringSync(),
          entry.value,
        );
      }
      expect(ProjectConfig.read(temp.path).state, project);
    }
  });

  test(
    'override dependency names cannot collide with the adopted package',
    () async {
      for (final selection in [
        (
          package: 'provider',
          project: StateStyle.cubit,
          feature: StateStyle.provider,
        ),
        (
          package: 'flutter_bloc',
          project: StateStyle.riverpod,
          feature: StateStyle.bloc,
        ),
        (
          package: 'flutter_riverpod',
          project: StateStyle.provider,
          feature: StateStyle.riverpod,
        ),
      ]) {
        final package = DartName.parse(selection.package);
        writeFile(
          temp.path,
          configFileName,
          ProjectConfig(package, state: selection.project).encode(),
        );
        writeFile(
          temp.path,
          'pubspec.yaml',
          appPlan(package, state: selection.project).files['pubspec.yaml']!,
        );
        final before = snapshot(temp.path);
        out.clear();
        expect(
          await run(['feature', 'orders', '--state', selection.feature.name]),
          64,
        );
        final result = jsonDecode(out.toString()) as Map<String, dynamic>;
        expect(
          result['error']['message'],
          contains('bundled direct dependency'),
        );
        expect(snapshot(temp.path), before);
      }
    },
  );

  test('schemas 1/2 preserve historical defaults; schema 3 round trips all choices strictly', () {
    writeProject(temp.path);
    for (final version in [1, 2]) {
      final yaml =
          'schema_version: $version\npackage: demo\n${version == 2 ? 'recipe: clean\nlint_profile: very_good\n' : ''}';
      writeFile(temp.path, configFileName, yaml);
      final config = ProjectConfig.read(temp.path);
      expect(config.state, StateStyle.cubit);
      expect(config.recipe, version == 1 ? Recipe.counter : Recipe.clean);
      expect(File(p.join(temp.path, configFileName)).readAsStringSync(), yaml);
      writeFile(temp.path, configFileName, '${yaml}state: bloc\n');
      expect(() => ProjectConfig.read(temp.path), throwsFormatException);
    }
    for (final state in StateStyle.values) {
      for (final recipe in Recipe.values) {
        for (final profile in LintProfile.values) {
          final yaml = ProjectConfig(
            DartName.parse('demo'),
            recipe: recipe,
            lintProfile: profile,
            state: state,
          ).encode();
          writeFile(temp.path, configFileName, yaml);
          final config = ProjectConfig.read(temp.path);
          expect(config.state, state);
          expect(config.recipe, recipe);
          expect(config.lintProfile, profile);
          expect(config.encode(), yaml);
        }
      }
    }
    const base =
        'schema_version: 3\npackage: demo\nrecipe: clean\nlint_profile: flutter\n';
    for (final invalid in [
      '',
      'state: invalid\n',
      'state: 1\n',
      'state: null\n',
      'state: [cubit]\n',
      'state: cubit\nextra: true\n',
    ]) {
      writeFile(temp.path, configFileName, '$base$invalid');
      expect(
        () => ProjectConfig.read(temp.path),
        throwsFormatException,
        reason: invalid,
      );
    }
    for (final invalid in [
      'schema_version: 4\npackage: demo\n',
      'schema_version: "3"\npackage: demo\n',
      'schema_version: true\npackage: demo\n',
      'schema_version: 1\npackage: different_package\n',
      '${base}state: cubit\nrecipe: counter\n',
    ]) {
      writeFile(temp.path, configFileName, invalid);
      expect(() => ProjectConfig.read(temp.path), throwsFormatException);
    }
  });
}
