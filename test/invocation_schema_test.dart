import 'dart:convert';
import 'dart:io';

import 'package:flutter_forge_cli/src/cli/invocation_schema.dart';
import 'package:flutter_forge_cli/src/cli/options.dart';
import 'package:flutter_forge_cli/src/cli/prompt.dart';
import 'package:flutter_forge_cli/src/cli/runner.dart';
import 'package:test/test.dart';

import 'support.dart';

Map<String, dynamic> object(Object? value) => value as Map<String, dynamic>;

List<Map<String, dynamic>> branches(Map<String, dynamic> schema) =>
    (schema['oneOf'] as List<dynamic>).cast<Map<String, dynamic>>();

Map<String, dynamic> optionProperties(Map<String, dynamic> branch) =>
    object(object(object(branch['properties'])['options'])['properties']);

void main() {
  late Directory temp;
  late StringBuffer out;
  late StringBuffer err;
  late FakeToolchain flutter;
  late int reads;

  Future<int> run(List<String> arguments, {bool terminal = true}) => runCli(
    arguments,
    output: out,
    error: err,
    workingDirectory: temp.path,
    toolchain: flutter,
    environment: const {},
    promptInput: PromptInput(
      hasTerminal: terminal,
      readLine: () async {
        reads++;
        throw StateError('Schema discovery must not prompt.');
      },
    ),
  );

  setUp(() {
    temp = temporaryDirectory();
    out = StringBuffer();
    err = StringBuffer();
    flutter = FakeToolchain();
    reads = 0;
  });
  tearDown(() => temp.deleteSync(recursive: true));

  for (final command in [null, ...cliParser().commands.keys]) {
    for (final json in [false, true]) {
      for (final terminal in [false, true]) {
        test(
          'schema command=$command json=$json terminal=$terminal has no side effects',
          () async {
            final arguments = [
              if (json) '--json',
              ?command,
              '--schema',
              '--interactive',
              '--no-interactive',
            ];
            expect(await run(arguments, terminal: terminal), 0);
            final result = object(jsonDecode(out.toString()));
            final schema = json
                ? object(object(result['data'])['schema'])
                : result;
            expect(schema, invocationSchema(cliParser(), command: command));
            expect(
              schema[r'$schema'],
              'https://json-schema.org/draft/2020-12/schema',
            );
            expect(branches(schema), hasLength(command == null ? 3 : 1));
            expect(out.toString().split('\n'), hasLength(2));
            expect(out.toString(), endsWith('\n'));
            if (json) {
              expect(result['schemaVersion'], 1);
              expect(result['success'], isTrue);
              expect(result['exitCode'], 0);
              expect(result['command'], command);
              expect(result['error'], isNull);
              expect(object(result['data']).keys, ['operation', 'schema']);
              expect(object(result['data'])['operation'], 'schema');
            }
            expect(reads, 0);
            expect(err.toString(), isEmpty);
            expect(flutter.calls, isEmpty);
            expect(temp.listSync(), isEmpty);
          },
        );
      }
    }
  }

  test('global schema flag restricts to the selected command', () async {
    expect(await run(['--schema', 'feature', '--json']), 0);
    final result = object(jsonDecode(out.toString()));
    expect(result['command'], 'feature');
    expect(
      object(object(result['data'])['schema']),
      invocationSchema(cliParser(), command: 'feature'),
    );
    expect(reads, 0);
    expect(flutter.calls, isEmpty);
    expect(temp.listSync(), isEmpty);
  });

  test('schema discovery still rejects unknown arguments', () async {
    expect(await run(['--schema', '--unknown', '--json']), 64);
    final result = object(jsonDecode(out.toString()));
    expect(result['success'], isFalse);
    expect(object(result['error'])['kind'], 'usage');
    expect(reads, 0);
    expect(flutter.calls, isEmpty);
    expect(temp.listSync(), isEmpty);
  });

  test('schema option is a common nonnegatable discovery flag', () {
    final parser = cliParser();
    for (final scope in [parser, ...parser.commands.values]) {
      final option = scope.options['schema']!;
      expect(option.isFlag, isTrue);
      expect(option.negatable, isFalse);
      expect(option.defaultsTo, isFalse);
    }
  });

  test('command shapes require their name and reject unknown fields', () {
    final schema = invocationSchema(cliParser());
    for (final branch in branches(schema)) {
      final properties = object(branch['properties']);
      final command = object(properties['command'])['const'];
      expect(branch['type'], 'object');
      expect(branch['additionalProperties'], isFalse);
      expect(branch['required'], ['command', if (command != 'init') 'name']);
      expect(properties.keys, [
        'command',
        if (command != 'init') 'name',
        'options',
      ]);
      if (command != 'init') {
        expect(object(properties['name'])['type'], 'string');
        expect(object(object(properties['name'])['x-cli'])['position'], 0);
      }
      expect(object(properties['options'])['type'], 'object');
      expect(object(properties['options'])['additionalProperties'], isFalse);
    }
  });

  test('option catalog and metadata align with every parser definition', () {
    final parser = cliParser();
    final schema = invocationSchema(parser);
    final discovery = object(object(schema['x-cli'])['discoveryOptions']);
    expect(discovery.keys, ['help', 'version', 'schema']);
    expect(object(object(discovery['help'])['x-cli'])['abbr'], 'h');
    for (final branch in branches(schema)) {
      final name = object(object(branch['properties'])['command'])['const'];
      final command = parser.commands[name]!;
      final properties = optionProperties(branch);
      expect(properties.keys, [
        for (final name in command.options.keys)
          if (!discovery.containsKey(name)) name,
      ]);
      for (final option in command.options.values) {
        final definition = object(
          discovery[option.name] ?? properties[option.name],
        );
        expect(definition['type'], option.isFlag ? 'boolean' : 'string');
        expect(definition['enum'], option.allowed);
        expect(definition['default'], option.defaultsTo);
        expect(
          definition.containsKey('default'),
          option.defaultsTo != null,
          reason: '$name --${option.name}',
        );
        expect(definition['description'], option.help);
        final metadata = object(definition['x-cli']);
        expect(metadata['flag'], '--${option.name}');
        expect(metadata['abbr'], option.abbr);
        expect(metadata['negatable'], option.isFlag ? option.negatable : null);
        expect(
          metadata['negatedFlag'],
          option.negatable == true ? '--no-${option.name}' : null,
        );
      }
    }
  });

  test('schema retains kebab-case names and boolean negation', () {
    final schema = invocationSchema(cliParser(), command: 'feature');
    final properties = optionProperties(branches(schema).single);
    expect(properties, contains('project-dir'));
    expect(properties, contains('lint-profile'));
    expect(properties, isNot(contains('projectDir')));
    expect(properties, isNot(contains('no-pub')));
    expect(object(properties['pub'])['type'], 'boolean');
    expect(object(properties['pub'])['default'], isTrue);
    expect(object(object(properties['pub'])['x-cli'])['negatable'], isTrue);
    expect(
      object(object(properties['pub'])['x-cli'])['negatedFlag'],
      '--no-pub',
    );
    for (final name in ['state', 'recipe', 'lint-profile', 'route']) {
      expect(object(properties[name]), isNot(contains('default')));
    }
    final options = object(
      object(branches(schema).single['properties'])['options'],
    );
    expect(options['if'], {
      'required': ['interactive'],
      'properties': {
        'interactive': {'const': true},
      },
    });
    expect(options['then'], {
      'properties': {
        'json': {'const': false},
        'no-interactive': {'const': false},
      },
    });
  });
}
