import 'dart:io';

import 'package:flutter_forge_cli/src/cli/runner.dart';
import 'package:flutter_forge_cli/src/project/names.dart';
import 'package:flutter_forge_cli/src/templates/app_templates.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support.dart';

void main() {
  late Directory temp;
  late StringBuffer out;
  late StringBuffer err;
  late FakeToolchain flutter;

  Future<int> run(List<String> args) => runCli(
    args,
    output: out,
    error: err,
    workingDirectory: temp.path,
    toolchain: flutter,
  );

  setUp(() {
    temp = temporaryDirectory();
    out = StringBuffer();
    err = StringBuffer();
    flutter = FakeToolchain();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('help and version use flutter-forge without side effects', () async {
    for (final args in [
      <String>[],
      ['--help'],
      ['create', '--help'],
      ['feature', '-h'],
      ['--version'],
    ]) {
      expect(await run(args), 0);
    }
    expect(out.toString(), contains('--platforms'));
    expect(out.toString(), contains('--state'));
    expect(
      out.toString(),
      contains('Usage: flutter-forge <command> [options]'),
    );
    expect(out.toString(), contains('Usage: flutter-forge create <name>'));
    expect(out.toString(), contains('Usage: flutter-forge feature <name>'));
    expect(out.toString(), contains('flutter-forge 0.1.0'));
    expect(out.toString(), isNot(contains('flutter_forge')));
    expect(err.toString(), isEmpty);
    expect(flutter.calls, isEmpty);
    expect(temp.listSync(), isEmpty);
  });

  test(
    'usage and validation errors return 64 before writes or processes',
    () async {
      for (final args in [
        ['unknown'],
        ['create'],
        ['feature'],
        ['create', 'one', 'two'],
        ['create', '../escape'],
        ['create', 'class'],
        ['create', 'demo', '--org', 'invalid'],
        ['create', 'demo', '--platforms', 'web,web'],
        ['create', 'demo', '--platforms', 'watchos'],
        ['feature', 'orders', '--state', 'provider'],
        ['create', 'demo', '--overwrite'],
      ]) {
        expect(await run(args), 64, reason: '$args: $err');
      }
      expect(err.toString(), contains('Error:'));
      expect(err.toString(), contains('Use flutter-forge --help for usage.'));
      expect(err.toString(), isNot(contains('flutter_forge')));
      expect(flutter.calls, isEmpty);
      expect(temp.listSync(), isEmpty);
    },
  );

  test('create dry-run previews all templates but creates nothing', () async {
    expect(await run(['create', 'demo', '--dry-run']), 0);
    expect(out.toString(), contains('--empty --no-pub --project-name demo'));
    expect(out.toString(), contains('--platforms ios,android'));
    expect(out.toString(), contains('lib/features/home/home_route.dart'));
    expect(out.toString(), contains('test/widget_test.dart'));
    expect(flutter.calls, isEmpty);
    expect(temp.listSync(), isEmpty);
  });

  test(
    'create rejects every bundled dependency name before side effects',
    () async {
      final pubspec =
          loadYaml(appPlan(DartName.parse('demo')).files['pubspec.yaml']!)
              as YamlMap;
      final dependencyNames = [
        ...(pubspec['dependencies'] as YamlMap).keys.cast<String>(),
        ...(pubspec['dev_dependencies'] as YamlMap).keys.cast<String>(),
      ];
      expect(
        dependencyNames,
        containsAll([
          'flutter_bloc',
          'go_router',
          'material_ui',
          'bloc_test',
          'flutter_lints',
        ]),
      );
      for (final name in dependencyNames) {
        for (final flags in [
          <String>[],
          ['--dry-run'],
          ['--no-pub'],
          ['--dry-run', '--no-pub'],
        ]) {
          expect(
            await run(['create', name, ...flags]),
            64,
            reason: '$name $flags',
          );
          expect(err.toString(), contains(name));
          expect(flutter.calls, isEmpty);
          expect(temp.listSync(), isEmpty);
        }
      }
    },
  );

  test('dependency names remain valid feature names', () async {
    writeProject(temp.path);
    final pubspec = File(p.join(temp.path, 'pubspec.yaml')).readAsStringSync();
    for (final name in [
      'flutter_bloc',
      'go_router',
      'material_ui',
      'bloc_test',
      'flutter_lints',
    ]) {
      expect(await run(['feature', name]), 0, reason: name);
      expect(
        File(
          p.join(temp.path, 'lib/features/$name/${name}_route.dart'),
        ).existsSync(),
        isTrue,
      );
    }
    expect(File(p.join(temp.path, 'pubspec.yaml')).readAsStringSync(), pubspec);
    expect(err.toString(), isEmpty);
    expect(flutter.calls, isEmpty);
  });

  test(
    'create and feature reject digit-leading segments before side effects',
    () async {
      for (final name in ['order_1', 'http_2_client']) {
        for (final command in ['create', 'feature']) {
          for (final flags in [
            <String>[],
            ['--dry-run'],
          ]) {
            expect(
              await run([command, name, ...flags]),
              64,
              reason: '$command $name $flags',
            );
          }
        }
      }
      expect(flutter.calls, isEmpty);
      expect(temp.listSync(), isEmpty);
    },
  );

  test(
    'create delegates Flutter and overlays only known stock files',
    () async {
      final parent = Directory(p.join(temp.path, 'parent with space'))
        ..createSync();
      expect(
        await run([
          'create',
          'demo',
          '--output',
          parent.path,
          '--platforms',
          'web',
          '--org',
          'dev.example',
        ]),
        0,
      );
      final root = p.join(parent.path, 'demo');
      expect(flutter.calls, hasLength(2));
      expect(flutter.calls.first.args, [
        'create',
        '--empty',
        '--no-pub',
        '--project-name',
        'demo',
        '--org',
        'dev.example',
        '--platforms',
        'web',
        root,
      ]);
      expect(flutter.calls.first.cwd, parent.path);
      expect(flutter.calls.last.args, ['pub', 'get']);
      expect(flutter.calls.last.cwd, root);
      expect(
        File(p.join(root, 'web/index.html')).readAsStringSync(),
        'platform scaffold',
      );
      expect(
        File(p.join(root, 'flutter_forge.yaml')).readAsStringSync(),
        'schema_version: 1\npackage: demo\n',
      );
      expect(
        File(p.join(root, 'test/widget_test.dart')).readAsStringSync(),
        contains('Count: 1'),
      );
      expect(err.toString(), isEmpty);
    },
  );

  test(
    '--no-pub leaves a complete scaffold and explains the next step',
    () async {
      expect(await run(['create', 'demo', '--no-pub']), 0);
      expect(flutter.calls, hasLength(1));
      expect(out.toString(), contains('Dependencies not fetched'));
      expect(
        File(p.join(temp.path, 'demo/lib/app/router.dart')).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'create rejects existing files, directories and links even on dry-run',
    () async {
      writeFile(temp.path, 'demo', 'keep');
      Directory(p.join(temp.path, 'existing_dir')).createSync();
      final names = ['demo', 'existing_dir'];
      if (!Platform.isWindows) {
        Link(
          p.join(temp.path, 'dangling'),
        ).createSync(p.join(temp.path, 'absent'));
        Link(
          p.join(temp.path, 'alias'),
        ).createSync(p.join(temp.path, 'existing_dir'));
        names.addAll(['dangling', 'alias']);
      }
      for (final name in names) {
        expect(await run(['create', name, '--dry-run']), 1);
        expect(await run(['create', name]), 1);
      }
      expect(File(p.join(temp.path, 'demo')).readAsStringSync(), 'keep');
      expect(flutter.calls, isEmpty);
    },
  );

  test('missing output parent is rejected without creating it', () async {
    expect(
      await run(['create', 'demo', '--output', 'missing', '--dry-run']),
      1,
    );
    expect(temp.listSync(), isEmpty);
    expect(flutter.calls, isEmpty);
  });

  test(
    'Flutter missing before create reports no output, not partial success',
    () async {
      flutter.failBeforeOutput = true;
      expect(await run(['create', 'demo']), 1);
      expect(err.toString(), contains('No target output was created'));
      expect(temp.listSync(), isEmpty);
      expect(out.toString(), isNot(contains('Created')));
    },
  );

  test(
    'failed create preserves partial output without applying overlay',
    () async {
      flutter.failAt = 1;
      expect(await run(['create', 'demo']), 1);
      expect(flutter.calls, hasLength(1));
      expect(err.toString(), contains('Failed during flutter create'));
      expect(err.toString(), contains('Partial output remains'));
      expect(
        File(p.join(temp.path, 'demo/lib/main.dart')).readAsStringSync(),
        'stock main',
      );
      expect(
        File(p.join(temp.path, 'demo/flutter_forge.yaml')).existsSync(),
        isFalse,
      );
    },
  );

  test('failed pub get reports complete scaffold and retry command', () async {
    flutter.failAt = 2;
    expect(await run(['create', 'demo']), 1);
    expect(err.toString(), contains('Failed during flutter pub get'));
    expect(
      err.toString(),
      contains('Scaffold is complete. Retry flutter pub get'),
    );
    expect(
      File(p.join(temp.path, 'demo/flutter_forge.yaml')).existsSync(),
      isTrue,
    );
    expect(out.toString(), isNot(contains('Created demo')));
  });

  test(
    'unexpected fresh-scaffold collisions preflight before known replacements',
    () async {
      flutter.unexpectedCollision = true;
      expect(await run(['create', 'demo']), 1);
      expect(flutter.calls, hasLength(1));
      expect(err.toString(), contains('writing the app scaffold'));
      expect(
        File(p.join(temp.path, 'demo/lib/main.dart')).readAsStringSync(),
        'stock main',
      );
      expect(
        File(p.join(temp.path, 'demo/lib/app/router.dart')).readAsStringSync(),
        'unexpected content',
      );
    },
  );

  test('feature dry-run performs no writes or processes', () async {
    writeProject(temp.path);
    final before = snapshot(temp.path);
    expect(await run(['feature', 'order_history', '--dry-run']), 0);
    expect(
      out.toString(),
      contains(
        'orderHistoryRoute(createOrderHistoryCubit: OrderHistoryCubit.new)',
      ),
    );
    expect(
      out.toString(),
      contains('lib/features/order_history/order_history_route.dart'),
    );
    expect(snapshot(temp.path), before);
    expect(flutter.calls, isEmpty);
    expect(Directory(p.join(temp.path, 'lib')).existsSync(), isFalse);
    expect(Directory(p.join(temp.path, 'test')).existsSync(), isFalse);
  });

  for (final kind in ['cubit', 'bloc']) {
    test(
      'generates a $kind feature without modifying existing project files',
      () async {
        writeProject(temp.path);
        writeFile(temp.path, 'lib/app/router.dart', 'handwritten router');
        final before = snapshot(temp.path);
        expect(await run(['feature', 'order_history', '--state', kind]), 0);
        expect(out.toString(), contains('Generated, not registered'));
        expect(
          out.toString(),
          contains(
            "import '../features/order_history/order_history_route.dart';",
          ),
        );
        expect(
          File(
            p.join(
              temp.path,
              'lib/features/order_history/presentation/order_history_$kind.dart',
            ),
          ).existsSync(),
          isTrue,
        );
        expect(
          File(
            p.join(
              temp.path,
              'test/features/order_history/order_history_page_test.dart',
            ),
          ).existsSync(),
          isTrue,
        );
        for (final entry in before.entries) {
          expect(
            File(p.join(temp.path, entry.key)).readAsStringSync(),
            entry.value,
          );
        }
        expect(flutter.calls, isEmpty);
        final generated = snapshot(temp.path);
        expect(await run(['feature', 'order_history', '--state', kind]), 1);
        expect(snapshot(temp.path), generated);
      },
    );
  }

  test(
    'existing test directory blocks the whole feature before any writes',
    () async {
      writeProject(temp.path);
      Directory(
        p.join(temp.path, 'test/features/orders'),
      ).createSync(recursive: true);
      final before = snapshot(temp.path);
      expect(await run(['feature', 'orders']), 1);
      expect(
        Directory(p.join(temp.path, 'lib/features/orders')).existsSync(),
        isFalse,
      );
      expect(snapshot(temp.path), before);
    },
  );

  test(
    'unsupported projects, schema drift and malformed YAML fail cleanly',
    () async {
      expect(await run(['feature', 'orders']), 64);
      for (final config in [
        'schema_version: 2\npackage: demo\n',
        'schema_version: 1\npackage: wrong\n',
        '- not-a-map\n',
        '[broken yaml',
      ]) {
        writeProject(temp.path);
        writeFile(temp.path, 'flutter_forge.yaml', config);
        final before = snapshot(temp.path);
        expect(await run(['feature', 'orders']), 64);
        expect(snapshot(temp.path), before);
      }
      writeProject(temp.path);
      writeFile(temp.path, 'pubspec.yaml', 'name: demo\ndependencies: {}\n');
      expect(await run(['feature', 'orders']), 64);
      expect(flutter.calls, isEmpty);
    },
  );

  test(
    'feature refuses in-tree symlinks and accepts selected project aliases',
    () async {
      if (Platform.isWindows) return;
      final root = Directory(p.join(temp.path, 'project'))..createSync();
      writeProject(root.path);
      Link(p.join(temp.path, 'alias')).createSync(root.path);
      expect(await run(['feature', 'safe', '--project-dir', 'alias']), 0);
      final outside = Directory(p.join(temp.path, 'outside'))..createSync();
      Link(p.join(root.path, 'lib/features/escape')).createSync(outside.path);
      expect(await run(['feature', 'escape', '--project-dir', root.path]), 1);
      expect(outside.listSync(), isEmpty);
    },
  );
}
