import 'dart:convert';
import 'dart:io';

import 'package:flutter_forge_cli/src/cli/runner.dart';
import 'package:flutter_forge_cli/src/project/names.dart';
import 'package:flutter_forge_cli/src/project/profiles.dart';
import 'package:flutter_forge_cli/src/project/project_config.dart';
import 'package:flutter_forge_cli/src/templates/app_templates.dart';
import 'package:flutter_forge_cli/src/templates/template_format.dart';
import 'package:flutter_forge_cli/src/templates/managed_feature_templates.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory temp;
  late StringBuffer out;
  late FakeToolchain flutter;

  Future<int> run(List<String> args) {
    out.clear();
    return runCli(
      [...args, '--json'],
      workingDirectory: temp.path,
      output: out,
      error: StringBuffer(),
      toolchain: flutter,
    );
  }

  Map<String, dynamic> data() =>
      (jsonDecode(out.toString()) as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
  setUp(() {
    temp = temporaryDirectory();
    out = StringBuffer();
    flutter = FakeToolchain();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('formatting managed long prefixed imports is idempotent', () {
    final files = appPlan(DartName.parse('a_very_long_application_name')).files;
    expect(formatTemplates(Map.of(files)), files);
  });

  test(
    'linked localization build marker cannot overwrite an external sentinel',
    () async {
      if (Platform.isWindows) return;
      expect(await run(['create', 'demo', '--no-pub']), 0);
      final root = p.join(temp.path, 'demo');
      final sentinel = File(p.join(temp.path, 'last_build_sentinel'))
        ..writeAsStringSync('00000000000000000000000000000000');
      Directory(p.join(root, 'build')).createSync();
      Link(p.join(root, 'build/.last_build_id')).createSync(sentinel.path);
      flutter.calls.clear();
      final before = snapshot(root);
      expect(
        await run(['feature', 'orders', '--project-dir', root]),
        1,
        reason: out.toString(),
      );
      expect(snapshot(root), before);
      expect(sentinel.readAsStringSync(), '00000000000000000000000000000000');
      expect(flutter.calls, isEmpty);
    },
  );

  test('localization build intermediates refuse linked roots hashes and files before writes', () async {
    if (Platform.isWindows) return;
    expect(await run(['create', 'demo', '--no-pub']), 0);
    final root = p.join(temp.path, 'demo');
    final external = Directory(p.join(temp.path, 'outside_build'))
      ..createSync();
    writeFile(external.path, 'keep', 'unchanged');
    const hash = '7b1d0000000000000000000000000000';
    flutter.calls.clear();
    for (final relative in [
      'build',
      'build/.last_build_id',
      'build/$hash',
      'build/$hash/gen_l10n_inputs_and_outputs.json',
      'build/$hash/gen_localizations.d',
      'build/$hash/.filecache',
      'build/$hash/gen_localizations.stamp',
      'build/$hash/outputs.json',
    ]) {
      final link = Link(p.join(root, relative));
      link.parent.createSync(recursive: true);
      link.createSync(external.path);
      final before = snapshot(root);
      final externalBefore = snapshot(external.path);
      expect(
        await run(['feature', 'orders', '--project-dir', root]),
        1,
        reason: out.toString(),
      );
      expect(snapshot(root), before);
      expect(snapshot(external.path), externalBefore);
      expect(flutter.calls, isEmpty);
      link.deleteSync();
    }
    Link(p.join(root, 'build/native_link')).createSync(external.path);
    expect(
      await run(['feature', 'orders', '--project-dir', root, '--dry-run']),
      0,
      reason: out.toString(),
    );
    expect(flutter.calls, isEmpty);
  });

  test('Freezed JSON annotation and converter names cannot shadow entities', () {
    for (final state in StateStyle.values) {
      for (final value in ['json_converter', 'nonempty_string_converter']) {
        final files = managedFeatureArtifact(
          DartName.parse('demo'),
          DartName.parse(value),
          style: state,
          recipe: Recipe.clean,
          routePath: '/$value',
        ).plan.files;
        final model =
            files['lib/features/$value/data/models/${value}_model.dart']!;
        expect(
          model.replaceAll(RegExp(r'\s+'), ' '),
          contains("domain/entities/$value.dart' as domain;"),
        );
        expect(
          model,
          contains('domain.${DartName.parse(value).className} toEntity()'),
        );
        expect(model, contains('class _NonemptyStringConverter'));
        if (state == StateStyle.riverpod) {
          final controller =
              files['lib/features/$value/presentation/${value}_riverpod.dart']!;
          expect(
            controller,
            contains('Use the route factory to provide this notifier.'),
          );
          expect(
            controller
                .split('\n')
                .where(
                  (line) =>
                      line.contains('StateError') ||
                      line.contains('Use the route factory'),
                )
                .every((line) => line.length <= 80),
            isTrue,
          );
        }
      }
    }
  });

  test(
    'managed codegen refuses redirected and linked outputs before every write',
    () async {
      if (Platform.isWindows) return;
      expect(await run(['create', 'demo', '--no-pub']), 0);
      final root = p.join(temp.path, 'demo');
      final external = Directory(p.join(temp.path, 'external'))..createSync();
      writeFile(
        external.path,
        'app_en.arb',
        '{"@@locale":"en","appTitle":"External"}',
      );
      final externalBefore = snapshot(external.path);
      final l10n = Directory(p.join(root, 'lib/l10n'));
      final saved = p.join(root, 'saved_l10n');
      l10n.renameSync(saved);
      Link(l10n.path).createSync(external.path);
      flutter.calls.clear();
      final before = snapshot(root);
      expect(
        await run(['feature', 'orders', '--project-dir', root]),
        1,
        reason: out.toString(),
      );
      expect(snapshot(root), before);
      expect(snapshot(external.path), externalBefore);
      expect(flutter.calls, isEmpty);
      Link(l10n.path).deleteSync();
      Directory(saved).renameSync(l10n.path);
      final generated = p.join(l10n.path, 'app_localizations.dart');
      Link(generated).createSync(p.join(external.path, 'untouched.dart'));
      final linked = snapshot(root);
      expect(
        await run(['feature', 'orders', '--project-dir', root]),
        1,
        reason: out.toString(),
      );
      expect(snapshot(root), linked);
      expect(
        File(p.join(external.path, 'untouched.dart')).existsSync(),
        isFalse,
      );
      expect(flutter.calls, isEmpty);
      Link(generated).deleteSync();
      final config = File(p.join(root, 'l10n.yaml'));
      config.writeAsStringSync(
        '${config.readAsStringSync()}output-dir: ../external\n',
      );
      final redirected = snapshot(root);
      expect(
        await run(['feature', 'orders', '--project-dir', root]),
        1,
        reason: out.toString(),
      );
      expect(snapshot(root), redirected);
      expect(snapshot(external.path), externalBefore);
      expect(flutter.calls, isEmpty);
    },
  );

  test(
    'managed codegen refuses edited build config and generated model symlinks',
    () async {
      expect(await run(['create', 'demo', '--no-pub']), 0);
      final root = p.join(temp.path, 'demo');
      final config = File(p.join(root, 'build.yaml'));
      final original = config.readAsStringSync();
      config.writeAsStringSync('$original\n# user build destination\n');
      flutter.calls.clear();
      final before = snapshot(root);
      expect(
        await run(['feature', 'orders', '--project-dir', root, '--no-pub']),
        1,
        reason: out.toString(),
      );
      expect(snapshot(root), before);
      expect(flutter.calls, isEmpty);
      config.writeAsStringSync(original);
      if (!Platform.isWindows) {
        Link(p.join(root, 'lib/features/home/data/models/home_model.g.dart'))
            .createSync(p.join(temp.path, 'external.g.dart'));
        final linked = snapshot(root);
        expect(
          await run(['feature', 'orders', '--project-dir', root]),
          1,
          reason: out.toString(),
        );
        expect(snapshot(root), linked);
        expect(
          File(p.join(temp.path, 'external.g.dart')).existsSync(),
          isFalse,
        );
        expect(flutter.calls, isEmpty);
      }
    },
  );

  test('managed config and import bridge links are rejected before reads or writes', () async {
    if (Platform.isWindows) return;
    expect(await run(['create', 'demo', '--no-pub']), 0);
    final root = p.join(temp.path, 'demo');
    flutter.calls.clear();
    for (final relative in [
      'l10n.yaml',
      'build.yaml',
      'tool/fix_localization_imports.dart',
    ]) {
      final file = File(p.join(root, relative));
      final saved = File('${file.path}.saved');
      file.renameSync(saved.path);
      final link = Link(file.path)..createSync(saved.path);
      final before = snapshot(root);
      expect(
        await run(['feature', 'orders', '--project-dir', root, '--dry-run']),
        1,
        reason: out.toString(),
      );
      expect(snapshot(root), before);
      expect(flutter.calls, isEmpty);
      link.deleteSync();
      saved.renameSync(file.path);
      final contents = file.readAsStringSync();
      file.writeAsStringSync('$contents\n# edited\n');
      final edited = snapshot(root);
      expect(
        await run(['feature', 'orders', '--project-dir', root, '--no-pub']),
        1,
        reason: out.toString(),
      );
      expect(snapshot(root), edited);
      expect(flutter.calls, isEmpty);
      file.writeAsStringSync(contents);
    }
  });

  test(
    'managed codegen rejects override configs and linked default source roots',
    () async {
      expect(await run(['create', 'demo', '--no-pub']), 0);
      final root = p.join(temp.path, 'demo');
      flutter.calls.clear();
      for (final path in ['build.custom.yaml', 'custom.build.yaml']) {
        final file = File(p.join(root, path))
          ..writeAsStringSync('targets: {}\n');
        final before = snapshot(root);
        expect(
          await run(['feature', 'orders', '--project-dir', root]),
          1,
          reason: out.toString(),
        );
        expect(snapshot(root), before);
        expect(flutter.calls, isEmpty);
        file.deleteSync();
      }
      if (!Platform.isWindows) {
        final external = Directory(p.join(temp.path, 'external'))..createSync();
        for (final path in [
          'integration_test',
          'bin',
          'example',
          'benchmark',
          '.dart_tool',
          'lib/l10n/app_localizations_es.dart',
        ]) {
          final link = Link(p.join(root, path));
          link.parent.createSync(recursive: true);
          link.createSync(external.path);
          final before = snapshot(root);
          expect(
            await run(['feature', 'orders', '--project-dir', root]),
            1,
            reason: out.toString(),
          );
          expect(snapshot(root), before);
          expect(external.listSync(), isEmpty);
          expect(flutter.calls, isEmpty);
          link.deleteSync();
        }
      }
    },
  );

  test(
    'managed runtime/codegen dependency names are rejected before processes',
    () async {
      for (final name in [
        'dio',
        'get_it',
        'freezed',
        'freezed_annotation',
        'json_annotation',
        'json_serializable',
        'build_runner',
        'flutter_localizations',
        'intl',
        'cupertino_ui',
      ]) {
        expect(await run(['create', name, '--dry-run']), 64, reason: name);
        expect(temp.listSync(), isEmpty);
        expect(flutter.calls, isEmpty);
      }
    },
  );

  for (final state in StateStyle.values) {
    test('${state.name} managed create/feature owns only registry, router and DI', () async {
      expect(
        await run(['create', 'demo', '--state', state.name, '--no-pub']),
        0,
      );
      final root = p.join(temp.path, 'demo');
      final before = snapshot(root);
      expect(ProjectConfig.read(root).managed, isTrue);
      expect(data()['requiredCommands'], hasLength(4));
      flutter.calls.clear();
      expect(
        await run(['feature', 'orders', '--project-dir', root, '--dry-run']),
        0,
      );
      expect(snapshot(root), before);
      expect(flutter.calls, isEmpty);
      expect(data()['registrationStatus'], 'planned');
      expect(data()['registered'], isFalse);
      expect(
        await run(['feature', 'orders', '--project-dir', root, '--no-pub']),
        0,
      );
      expect(data()['registered'], isTrue);
      expect(
        data()['updatedFiles'],
        unorderedEquals([
          'lib/app/router.dart',
          'lib/app/dependencies.dart',
          configFileName,
        ]),
      );
      final after = snapshot(root);
      for (final entry in before.entries.where(
        (entry) =>
            !(data()['updatedFiles'] as List<dynamic>).contains(entry.key),
      )) {
        expect(after[entry.key], entry.value, reason: entry.key);
      }
      expect(after['lib/app/router.dart'], contains('ordersRoute('));
      expect(
        after['lib/app/dependencies.dart'],
        matches(
          'registerFactory<feature[0-9]+\\.Orders${state.controllerSuffix}>',
        ),
      );
      expect(
        after['lib/features/orders/data/datasources/local_orders_datasource.dart'],
        contains('Orders local starter'),
      );
      for (final entry in after.entries.where(
        (entry) => entry.key.startsWith('lib/features/'),
      )) {
        expect(
          entry.value,
          isNot(contains('package:get_it/')),
          reason: entry.key,
        );
      }
      expect(
        ProjectConfig.read(root).features!.map((feature) => feature.name.value),
        ['home', 'orders'],
      );
      expect(flutter.calls, isEmpty);
    });
  }

  test(
    'managed default invokes all code generation; no-pub reports commands',
    () async {
      expect(await run(['create', 'demo']), 0);
      expect(flutter.calls.map((call) => call.args.first), [
        'create',
        'pub',
        'gen-l10n',
        'pub',
        'pub',
      ]);
      flutter.calls.clear();
      expect(await run(['feature', 'orders', '--project-dir', 'demo']), 0);
      expect(flutter.calls.map((call) => call.args), [
        ['pub', 'get'],
        ['gen-l10n'],
        ['pub', 'run', 'tool/fix_localization_imports.dart'],
        ['pub', 'run', 'build_runner', 'build'],
      ]);
      expect(data()['codeGeneration'], 'complete');
    },
  );

  test(
    'managed counter state/event codegen preserves native notifier integers',
    () async {
      for (final state in StateStyle.values) {
        final name = 'counter_${state.name}';
        expect(
          await run([
            'create',
            name,
            '--recipe',
            'counter',
            '--state',
            state.name,
            '--no-pub',
          ]),
          0,
        );
        final root = p.join(temp.path, name);
        final source = snapshot(root);
        if (state.usesBloc) {
          expect(
            source['lib/features/home/presentation/home_state.dart'],
            contains('@freezed'),
          );
          expect(
            source['lib/features/home/presentation/home_state.dart'],
            contains("part 'home_state.freezed.dart'"),
          );
        } else {
          expect(
            source['lib/features/home/presentation/home_${state.name}.dart'],
            contains(
              state == StateStyle.riverpod ? 'Notifier<int>' : 'int _state = 0',
            ),
          );
        }
        expect(
          source['lib/app/dependencies.dart'],
          contains('Home${state.controllerSuffix}.new'),
        );
        if (state == StateStyle.bloc) {
          expect(
            source['lib/features/home/presentation/home_event.dart'],
            contains('@freezed'),
          );
        }
        expect(source['lib/core/network/api_client.dart'], isNotNull);
        expect(source['l10n.yaml'], isNotNull);
        expect(source['assets/images/.gitkeep'], '');
      }
    },
  );

  test('managed generation process failures keep registration and actionable stage', () async {
    flutter.failAt = 3;
    expect(await run(['create', 'demo']), 1);
    expect(data()['failedStage'], 'flutter gen-l10n');
    expect(data()['retryArguments'], ['flutter', 'gen-l10n']);
    expect(data()['scaffoldComplete'], isTrue);
    final root = p.join(temp.path, 'demo');
    expect(ProjectConfig.read(root).managed, isTrue);
    flutter.failAt = flutter.calls.length + 2;
    expect(await run(['feature', 'orders', '--project-dir', root]), 1);
    expect(data()['registered'], isTrue);
    expect(data()['partialOutput'], isTrue);
    expect(data()['failedStage'], 'flutter gen-l10n');
    expect(ProjectConfig.read(root).features!.last.name.value, 'orders');
  });

  test(
    'every integration edit, deletion or collision refuses all writes',
    () async {
      expect(await run(['create', 'demo', '--no-pub']), 0);
      final root = p.join(temp.path, 'demo');
      for (final path in [
        'lib/app/router.dart',
        'lib/app/dependencies.dart',
        configFileName,
      ]) {
        final original = File(p.join(root, path)).readAsStringSync();
        writeFile(
          root,
          path,
          '$original\n${path == configFileName ? '#' : '//'} user edit\n',
        );
        final before = snapshot(root);
        expect(
          await run(['feature', 'orders', '--project-dir', root, '--no-pub']),
          1,
          reason: out.toString(),
        );
        expect(snapshot(root), before);
        writeFile(root, path, original);
      }
      writeFile(root, 'test/features/orders/owned.dart', 'user test');
      final before = snapshot(root);
      expect(
        await run(['feature', 'orders', '--project-dir', root, '--dry-run']),
        1,
      );
      expect(snapshot(root), before);
    },
  );

  test(
    'duplicate route/name and symlink preflight precedes writes and processes',
    () async {
      expect(await run(['create', 'demo', '--no-pub']), 0);
      final root = p.join(temp.path, 'demo');
      final before = snapshot(root);
      flutter.calls.clear();
      for (final args in [
        ['home'],
        ['orders', '--route', '/'],
      ]) {
        expect(await run(['feature', ...args, '--project-dir', root]), 64);
        expect(snapshot(root), before);
      }
      if (!Platform.isWindows) {
        final target = File(p.join(root, 'lib/app/router.dart'));
        final contents = target.readAsStringSync();
        target.renameSync(p.join(root, 'saved_router.dart'));
        Link(target.path).createSync(p.join(root, 'saved_router.dart'));
        expect(await run(['feature', 'orders', '--project-dir', root]), 1);
        expect(
          File(p.join(root, 'saved_router.dart')).readAsStringSync(),
          contents,
        );
        expect(
          Directory(p.join(root, 'lib/features/orders')).existsSync(),
          isFalse,
        );
      }
      expect(flutter.calls, isEmpty);
    },
  );

  test(
    'managed dependencies checked before any registration or feature write',
    () async {
      expect(await run(['create', 'demo', '--no-pub']), 0);
      final root = p.join(temp.path, 'demo');
      final pub = File(p.join(root, 'pubspec.yaml'));
      pub.writeAsStringSync(
        pub.readAsStringSync().replaceAll(
          RegExp(r'^  freezed_annotation:.*\n', multiLine: true),
          '',
        ),
      );
      final before = snapshot(root);
      flutter.calls.clear();
      expect(await run(['feature', 'orders', '--project-dir', root]), 64);
      expect(
        data()['missingDependencies']['dependencies'],
        contains('freezed_annotation'),
      );
      expect(snapshot(root), before);
      expect(flutter.calls, isEmpty);
    },
  );

  test('scaffold codegen preflight refuses linked source roots before writing metadata', () async {
    if (Platform.isWindows) return;
    writeFile(
      temp.path,
      'pubspec.yaml',
      appPlan(DartName.parse('demo')).files['pubspec.yaml']!,
    );
    final external = Directory(p.join(temp.path, 'outside'))..createSync();
    Link(p.join(temp.path, 'integration_test')).createSync(external.path);
    final before = snapshot(temp.path);
    expect(
      await run([
        'init',
        '--scaffold',
        '--no-pub',
        '--lint-profile',
        'very_good',
      ]),
      1,
      reason: out.toString(),
    );
    expect(snapshot(temp.path), before);
    expect(external.listSync(), isEmpty);
    expect(flutter.calls, isEmpty);
  });

  test('scaffold adoption keeps existing source/pubspec and refuses occupied app files', () async {
    writeFile(
      temp.path,
      'pubspec.yaml',
      appPlan(DartName.parse('demo')).files['pubspec.yaml']!,
    );
    writeFile(temp.path, 'lib/main.dart', 'user entrypoint');
    writeFile(
      temp.path,
      'analysis_options.yaml',
      'include: package:very_good_analysis/analysis_options.yaml\n',
    );
    final before = snapshot(temp.path);
    expect(await run(['init', '--scaffold', '--dry-run']), 0);
    expect(snapshot(temp.path), before);
    expect(flutter.calls, isEmpty);
    writeFile(temp.path, 'lib/app/router.dart', 'user router');
    final occupied = snapshot(temp.path);
    expect(await run(['init', '--scaffold', '--no-pub']), 1);
    expect(snapshot(temp.path), occupied);
    File(p.join(temp.path, 'lib/app/router.dart'))
        .renameSync(p.join(temp.path, 'user_router.dart'));
    expect(await run(['init', '--scaffold', '--no-pub']), 0);
    for (final entry in before.entries) {
      expect(
        File(p.join(temp.path, entry.key)).readAsStringSync(),
        entry.value,
      );
    }
    expect(File(p.join(temp.path, 'lib/main_forge.dart')).existsSync(), isTrue);
    expect(ProjectConfig.read(temp.path).managed, isTrue);
  });

  test('malformed schema4 entries and missing integration files refuse all writes', () async {
    expect(await run(['create', 'demo', '--no-pub']), 0);
    final root = p.join(temp.path, 'demo');
    final metadata = File(p.join(root, configFileName));
    final original = metadata.readAsStringSync();
    for (final invalid in [
      original.replaceFirst('    route: /', '    route: /\n    unknown: true'),
      '$original  - name: duplicate\n    state: cubit\n    recipe: clean\n    route: /\n',
      original.replaceFirst('    route: /', '    route: /missing_home'),
      original.replaceFirst('    state: cubit', '    state: unknown'),
    ]) {
      metadata.writeAsStringSync(invalid);
      final before = snapshot(root);
      expect(await run(['feature', 'orders', '--project-dir', root]), 64);
      expect(snapshot(root), before);
    }
    metadata.writeAsStringSync(original);
    File(p.join(root, 'lib/app/dependencies.dart'))
        .renameSync(p.join(root, 'saved_dependencies.dart'));
    final before = snapshot(root);
    expect(await run(['feature', 'orders', '--project-dir', root]), 1);
    expect(snapshot(root), before);
  });

  test('scaffold dependency/settings errors never mutate', () async {
    writeFile(
      temp.path,
      'pubspec.yaml',
      'name: demo\ndependencies:\n  flutter: {sdk: flutter}\n',
    );
    final before = snapshot(temp.path);
    expect(await run(['init', '--scaffold']), 64);
    expect(snapshot(temp.path), before);
    writeFile(
      temp.path,
      'pubspec.yaml',
      appPlan(DartName.parse('demo')).files['pubspec.yaml']!
          .replaceFirst('  generate: true', '  generate: false'),
    );
    final settings = snapshot(temp.path);
    expect(await run(['init', '--scaffold']), 64);
    expect(snapshot(temp.path), settings);
    expect(flutter.calls, isEmpty);
  });
}
