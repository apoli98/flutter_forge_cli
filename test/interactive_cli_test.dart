import 'dart:convert';
import 'dart:io';

import 'package:flutter_forge_cli/src/cli/prompt.dart';
import 'package:flutter_forge_cli/src/cli/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory temp;
  late StringBuffer out;
  late StringBuffer err;
  late FakeToolchain flutter;
  late int reads;

  Future<int> run(
    List<String> args, {
    List<String> answers = const [],
    bool terminal = true,
    Map<String, String> environment = const {},
  }) {
    var index = 0;
    return runCli(
      args,
      output: out,
      error: err,
      workingDirectory: temp.path,
      toolchain: flutter,
      environment: environment,
      promptInput: PromptInput(
        hasTerminal: terminal,
        readLine: () async {
          reads++;
          return index < answers.length ? answers[index++] : null;
        },
      ),
    );
  }

  Map<String, dynamic> result() =>
      jsonDecode(out.toString()) as Map<String, dynamic>;

  setUp(() {
    temp = temporaryDirectory();
    out = StringBuffer();
    err = StringBuffer();
    flutter = FakeToolchain();
    reads = 0;
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('TTY no-args chooser collects create defaults and confirms', () async {
    expect(await run([], answers: ['', 'demo', '', '', '', '2', 'yes']), 0);
    expect(flutter.calls, hasLength(1));
    expect(out.toString(), contains('Resolved command:'));
    expect(out.toString(), contains('--no-pub'));
    expect(
      File(p.join(temp.path, 'demo/flutter_forge.yaml')).existsSync(),
      isTrue,
    );
  });

  test('TTY chooser can select feature', () async {
    writeProject(temp.path);
    expect(await run([], answers: ['2', 'orders', '', '2', '2']), 0);
    expect(
      out.toString(),
      contains('Generated, not registered: orders (bloc)'),
    );
    expect(flutter.calls, isEmpty);
  });

  test('missing create name preserves every supplied option', () async {
    expect(
      await run(
        [
          '--dry-run',
          'create',
          '--org',
          'dev.acme',
          '--platforms',
          'web',
          '--output',
          temp.path,
          '--no-pub',
        ],
        answers: ['demo', '2'],
      ),
      0,
    );
    expect(reads, 2);
    expect(out.toString(), contains('--org \'dev.acme\' --platforms \'web\''));
    expect(out.toString(), contains('--no-pub --dry-run'));
    expect(flutter.calls, isEmpty);
    expect(temp.listSync(), isEmpty);
  });

  test(
    'explicit feature wizard keeps supplied state and project directory',
    () async {
      writeProject(temp.path);
      expect(
        await run(
          [
            '--interactive',
            'feature',
            'orders',
            '--project-dir',
            temp.path,
            '--state',
            'bloc',
            '--dry-run',
          ],
          answers: ['yes'],
        ),
        0,
      );
      expect(reads, 1);
      expect(out.toString(), contains('--state bloc --dry-run'));
      expect(out.toString(), contains('createOrdersBloc: OrdersBloc.new'));
    },
  );

  test('explicit wizard collects omitted options even with a name', () async {
    expect(
      await run(
        ['create', 'demo', '--interactive', '--dry-run'],
        answers: ['dev.acme', 'web', '', 'no', 'yes'],
      ),
      0,
    );
    expect(reads, 5);
    expect(out.toString(), contains('--org dev.acme --platforms web'));
    expect(flutter.calls, isEmpty);
  });

  test('invalid app names, org, platforms, paths, selectors retry', () async {
    expect(
      await run(
        ['create', '--dry-run'],
        answers: [
          'class',
          'order_1',
          'flutter_bloc',
          'demo',
          'invalid',
          'dev.acme',
          'web,web',
          'watchos',
          'web',
          'missing',
          '',
          'bogus',
          '2',
          'yes',
        ],
      ),
      0,
    );
    expect(out.toString(), contains('bundled direct dependency'));
    expect(out.toString(), contains('reverse-domain'));
    expect(out.toString(), contains('unique comma-separated'));
    expect(out.toString(), contains('existing directory'));
    expect(out.toString(), contains('Choose 1-2'));
    expect(temp.listSync(), isEmpty);
    expect(flutter.calls, isEmpty);
  });

  test('feature project path and state selection retry', () async {
    writeProject(temp.path);
    expect(
      await run(
        ['feature', '--dry-run'],
        answers: [
          '../escape',
          'go_router',
          'missing',
          '',
          'provider',
          'bloc',
          'yes',
        ],
      ),
      0,
    );
    expect(out.toString(), contains('not a Flutter Forge project'));
    expect(out.toString(), contains('Choose 1-2 (cubit, bloc)'));
    expect(out.toString(), contains('createGoRouterBloc: GoRouterBloc.new'));
    expect(flutter.calls, isEmpty);
  });

  for (final answers in [
    <String>[],
    ['demo'],
    ['demo', '', '', '', '', 'no'],
    ['demo', '', '', '', '', ''],
    ['demo', '', '', '', ''],
  ]) {
    test('EOF or decline cancels without side effects: $answers', () async {
      expect(await run(['create'], answers: answers), 130);
      expect(temp.listSync(), isEmpty);
      expect(flutter.calls, isEmpty);
      expect(err.toString(), contains('Cancelled'));
    });
  }

  test('feature cancellation leaves the project untouched', () async {
    writeProject(temp.path);
    final before = snapshot(temp.path);
    expect(await run(['feature'], answers: ['orders', '', '', 'no']), 130);
    expect(snapshot(temp.path), before);
    expect(flutter.calls, isEmpty);
  });

  test('wizard still preflights all collisions before generation', () async {
    writeProject(temp.path);
    writeFile(temp.path, 'test/features/orders/keep.txt', 'keep');
    final before = snapshot(temp.path);
    expect(await run(['feature'], answers: ['orders', '', '', 'yes']), 1);
    expect(snapshot(temp.path), before);
    expect(flutter.calls, isEmpty);
  });

  test('fully specified commands never prompt on a terminal', () async {
    expect(await run(['create', 'demo', '--dry-run']), 0);
    writeProject(temp.path);
    expect(await run(['feature', 'orders', '--dry-run']), 0);
    expect(reads, 0);
  });

  test('nonTTY and CI missing names fail immediately', () async {
    for (final command in ['create', 'feature']) {
      expect(await run([command], terminal: false), 64);
      for (final ci in ['true', '1', 'yes', 'github']) {
        expect(await run([command], environment: {'CI': ci}), 64);
      }
    }
    expect(reads, 0);
    expect(err.toString(), contains('Missing positional <name>'));
    expect(temp.listSync(), isEmpty);
  });

  test('no-args nonTTY and CI retain help fallback', () async {
    expect(await run([], terminal: false), 0);
    expect(await run([], environment: {'CI': 'true'}), 0);
    expect(reads, 0);
    expect(out.toString(), contains('Usage: flutter-forge'));
  });

  test('false and zero CI values allow automatic interaction', () async {
    for (final ci in ['', 'false', '0', 'FALSE']) {
      expect(await run(['create'], environment: {'CI': ci}), 130);
    }
    expect(reads, 4);
  });

  test('--interactive requires TTY but explicitly overrides CI', () async {
    expect(await run(['--interactive', 'create'], terminal: false), 64);
    expect(err.toString(), contains('requires terminal stdin and stdout'));
    expect(reads, 0);
    expect(
      await run(['create', '--interactive'], environment: {'CI': 'true'}),
      130,
    );
    expect(reads, 1);
  });

  test(
    '--no-interactive and --json always suppress automatic prompting',
    () async {
      for (final args in [
        ['--no-interactive'],
        ['create', '--no-interactive'],
        ['--no-interactive', 'feature'],
        ['--json', 'create'],
      ]) {
        out.clear();
        expect(await run(args), 64);
      }
      expect(
        result()['error']['message'],
        contains('Missing positional <name>'),
      );
      expect(reads, 0);
    },
  );

  test(
    'help and version bypass wizard, even explicit nonTTY requests',
    () async {
      for (final args in [
        ['--interactive', '--help'],
        ['create', '--interactive', '--help'],
        ['--interactive', 'feature', '--version'],
      ]) {
        expect(await run(args, terminal: false), 0);
      }
      expect(reads, 0);
      expect(flutter.calls, isEmpty);
    },
  );

  test('unknown flags and invalid positional counts never prompt', () async {
    for (final args in [
      ['--interactive', 'unknown'],
      ['create', '--wat'],
      ['--interactive', 'create', 'one', 'two'],
      ['create', '--state', 'bloc'],
    ]) {
      expect(await run(args), 64);
    }
    expect(reads, 0);
    expect(flutter.calls, isEmpty);
  });

  test('common flags work before or after commands', () async {
    for (final args in [
      ['--json', '--no-interactive', '--dry-run', 'create', 'demo'],
      ['create', 'demo', '--json', '--no-interactive', '--dry-run'],
      ['--no-interactive', 'create', 'demo', '--json', '--dry-run'],
    ]) {
      out.clear();
      expect(await run(args), 0);
      expect(result()['data']['plannedFiles'], contains('lib/main.dart'));
      expect(result()['data']['dryRun'], isTrue);
    }
    expect(reads, 0);
    expect(temp.listSync(), isEmpty);
  });

  test(
    'explicit interactive and no-interactive conflict in either order',
    () async {
      for (final args in [
        ['--interactive', '--no-interactive', 'create', 'demo'],
        ['--no-interactive', '--interactive', 'create', 'demo'],
        ['--interactive', 'create', 'demo', '--no-interactive'],
        ['--no-interactive', 'create', 'demo', '--interactive'],
      ]) {
        expect(await run(args), 64);
      }
      expect(reads, 0);
      expect(flutter.calls, isEmpty);
      expect(temp.listSync(), isEmpty);
    },
  );

  test(
    'invalid explicit values fail rather than being prompted over',
    () async {
      expect(
        await run(['create', 'demo', '--interactive', '--org', 'invalid']),
        64,
      );
      writeProject(temp.path);
      expect(
        await run([
          'feature',
          'orders',
          '--interactive',
          '--project-dir',
          'missing',
        ]),
        64,
      );
      expect(reads, 0);
      expect(flutter.calls, isEmpty);
    },
  );

  test('JSON success reports structured create results', () async {
    expect(await run(['create', 'demo', '--json', '--no-pub']), 0);
    expect(result(), containsPair('schemaVersion', 1));
    expect(result(), containsPair('success', true));
    expect(result(), containsPair('exitCode', 0));
    expect(result(), containsPair('command', 'create'));
    expect(result()['error'], isNull);
    final data = result()['data'];
    expect(data['name'], 'demo');
    expect(data['target'], p.join(temp.path, 'demo'));
    expect(data['pub'], isFalse);
    expect(data['generatedFiles'], contains('lib/app/router.dart'));
    expect(data['plannedFiles'], isNull);
    expect(err.toString(), isEmpty);
    expect(reads, 0);
  });

  test(
    'JSON feature dryrun and success expose wiring without registration',
    () async {
      writeProject(temp.path);
      final before = snapshot(temp.path);
      expect(
        await run([
          'feature',
          'orders',
          '--state',
          'bloc',
          '--json',
          '--dry-run',
        ]),
        0,
      );
      expect(snapshot(temp.path), before);
      final data = result()['data'];
      expect(data['projectRoot'], temp.path);
      expect(data['state'], 'bloc');
      expect(data['registered'], isFalse);
      expect(data['wiring']['imports'], hasLength(2));
      expect(
        data['wiring']['routeEntry'],
        'ordersRoute(createOrdersBloc: OrdersBloc.new),',
      );
      expect(
        data['plannedFiles'],
        contains('lib/features/orders/orders_route.dart'),
      );
      out.clear();
      expect(await run(['--json', 'feature', 'orders', '--state', 'bloc']), 0);
      expect(result()['data']['generatedFiles'], data['plannedFiles']);
      expect(err.toString(), isEmpty);
      expect(reads, 0);
    },
  );

  test('JSON help and version are single objects', () async {
    for (final args in [
      ['--json', '--help'],
      ['create', '--json', '--help'],
      ['--json', '--version'],
      ['feature', '--version', '--json'],
    ]) {
      out.clear();
      expect(await run(args), 0);
      expect(result()['error'], isNull);
      expect(result()['data']['version'], version);
      expect(result()['data']['operation'], anyOf('help', 'version'));
    }
    expect(reads, 0);
    expect(err.toString(), isEmpty);
  });

  test('JSON parse errors and interactive conflict are structured', () async {
    for (final args in [
      ['--json', 'create'],
      ['--json', 'unknown'],
      ['create', 'demo', '--json', '--wat'],
      ['--json', '--interactive', 'create', 'demo'],
      ['--interactive', 'create', 'demo', '--json'],
      ['--json', 'feature', 'orders', '--state', 'invalid'],
    ]) {
      out.clear();
      expect(await run(args), 64);
      expect(result()['success'], isFalse);
      expect(result()['exitCode'], 64);
      expect(result()['error']['kind'], 'usage');
      expect(result()['error']['message'], isNotEmpty);
    }
    expect(err.toString(), isEmpty);
    expect(reads, 0);
    expect(flutter.calls, isEmpty);
  });

  test('JSON filesystem collision is structured', () async {
    Directory(p.join(temp.path, 'demo')).createSync();
    expect(await run(['--json', 'create', 'demo']), 1);
    expect(result()['error']['kind'], 'filesystem');
    expect(result()['data']['target'], p.join(temp.path, 'demo'));
    expect(flutter.calls, isEmpty);
  });

  test('JSON Flutter failures report stage and partial output', () async {
    flutter.failAt = 2;
    expect(await run(['create', 'demo', '--json']), 1);
    final data = result()['data'];
    expect(data['failedStage'], 'flutter pub get');
    expect(data['partialOutput'], isTrue);
    expect(data['scaffoldComplete'], isTrue);
    expect(data['retryArguments'], ['flutter', 'pub', 'get']);
    expect(result()['error']['kind'], 'process');
    expect(err.toString(), isEmpty);
    expect(result()['success'], isFalse);
  });

  test(
    'JSON failure before Flutter output does not claim partial output',
    () async {
      flutter.failBeforeOutput = true;
      expect(await run(['--json', 'create', 'demo']), 1);
      expect(result()['data']['partialOutput'], isFalse);
      expect(result()['data']['scaffoldComplete'], isFalse);
      expect(temp.listSync(), isEmpty);
    },
  );

  test('real subprocess logs stay on stderr in JSON mode', () async {
    if (Platform.isWindows) return;
    final fakeBin = Directory(p.join(temp.path, 'bin'))..createSync();
    final fakeFlutter = File(p.join(fakeBin.path, 'flutter'));
    fakeFlutter.writeAsStringSync(
      '#!/bin/sh\necho stdout-log\necho stderr-log >&2\nexit 7\n',
    );
    expect(
      (await Process.run('/bin/chmod', ['+x', fakeFlutter.path])).exitCode,
      0,
    );
    final process = await Process.run(
      Platform.resolvedExecutable,
      [
        p.absolute('bin/flutter_forge.dart'),
        '--json',
        'create',
        'demo',
        '--output',
        temp.path,
      ],
      environment: {'PATH': fakeBin.path},
    );
    expect(process.exitCode, 1);
    final object = jsonDecode(process.stdout as String) as Map<String, dynamic>;
    expect(object['error']['kind'], 'process');
    expect(object['data']['partialOutput'], isFalse);
    expect(process.stderr, contains('stdout-log'));
    expect(process.stderr, contains('stderr-log'));
    expect(Directory(p.join(temp.path, 'demo')).existsSync(), isFalse);
  });
}
