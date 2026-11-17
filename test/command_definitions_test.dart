import 'dart:convert';
import 'dart:io';

import 'package:flutter_forge_cli/src/cli/command_definitions.dart';
import 'package:flutter_forge_cli/src/cli/commands.g.dart';
import 'package:flutter_forge_cli/src/cli/invocation_schema.dart';
import 'package:flutter_forge_cli/src/cli/options.dart';
import 'package:flutter_forge_cli/src/cli/runner.dart';
import 'package:flutter_forge_cli/src/project/profiles.dart';
import 'package:test/test.dart';

import '../tool/generate_commands.dart' as generator;
import 'support.dart';

Map<String, dynamic> sampleCatalog() => {
  r'$schema': 'commands.schema.json',
  'commonOptions': [
    {'name': 'verbose', 'type': 'boolean', 'abbr': 'v', 'negatable': false},
  ],
  'commands': [
    {
      'name': 'inspect',
      'help': 'Inspect a target.',
      'positionals': [
        {'name': 'target', 'required': true, 'help': 'Target path.'},
        {'name': 'label', 'required': false, 'help': 'Optional label.'},
      ],
      'options': [
        {
          'name': 'mode',
          'type': 'string',
          'abbr': 'm',
          'allowed': ['fast', 'full'],
          'default': 'fast',
        },
        {'name': 'cache', 'type': 'boolean', 'default': true},
      ],
    },
  ],
};

Map<String, dynamic> sampleCommand(Map<String, dynamic> root) =>
    (root['commands'] as List<dynamic>).single as Map<String, dynamic>;

List<dynamic> sampleOptions(Map<String, dynamic> root) =>
    sampleCommand(root)['options'] as List<dynamic>;

void main() {
  test('embedded JSON and deterministic generated file match the source', () {
    final source = File('lib/src/cli/commands.json').readAsStringSync();
    final generated = File('lib/src/cli/commands.g.dart').readAsStringSync();
    expect(embeddedCommandsJson, source);
    expect(generator.generateCommands(source), generated);
    expect(
      generator.generateCommands(source),
      generator.generateCommands(source),
    );
  });

  test(
    'embedding preserves interpolation, quotes, slashes, and newlines',
    () async {
      final temp = temporaryDirectory();
      addTearDown(() => temp.deleteSync(recursive: true));
      final source = jsonEncode({
        r'$schema': r'${notDart} and $alsoNotDart',
        'help': 'Quotes: " and \'\'\' and """. Slash: \\.\nNext line. 🙂',
      });
      final script = File('${temp.path}/embedded.dart')
        ..writeAsStringSync(
          '${generator.generateCommands(source)}\n'
          'void main() { print(embeddedCommandsJson); }\n',
        );
      final result = await Process.run(Platform.resolvedExecutable, [
        script.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, '$source\n');
    },
  );

  test(
    'arbitrary JSON commands build parsers and positional invocation fields',
    () {
      final definitions = CommandCatalog.parse(jsonEncode(sampleCatalog()));
      final parser = cliParser(definitions: definitions);
      final args = parser.parse([
        '-v',
        'inspect',
        'example',
        '-m',
        'full',
        '--no-cache',
      ]);
      expect(args.flag('verbose'), isTrue);
      expect(args.command!.rest, ['example']);
      expect(args.command!.option('mode'), 'full');
      expect(args.command!.flag('cache'), isFalse);
      final command = definitions.commands['inspect']!;
      expect(command.minimumPositionals, 1);
      expect(command.maximumPositionals, 2);
      expect(command.usage, 'inspect <target> [label]');
      final schema = invocationSchema(parser, definitions: definitions);
      final branch =
          (schema['oneOf'] as List<dynamic>).single as Map<String, Object?>;
      expect(branch['required'], ['command', 'target']);
      final properties = branch['properties'] as Map<String, Object?>;
      expect(properties.keys, ['command', 'target', 'label', 'options']);
      expect(properties['label'], {
        'type': 'string',
        'description': 'Optional label.',
        'x-cli': {'position': 1},
      });
      expect(
        parser.parse(['inspect', 'example']).command!.option('mode'),
        'fast',
      );
      expect(
        () => parser.parse(['inspect', '--mode', 'invalid']),
        throwsFormatException,
      );
    },
  );

  test('catalog options and defaults agree with every constructed parser', () {
    final parser = cliParser();
    for (final command in cliCommands.commands.values) {
      final child = parser.commands[command.name]!;
      final definitions = [...cliCommands.commonOptions, ...command.options];
      expect(child.options.keys, definitions.map((option) => option.name));
      for (final definition in definitions) {
        final option = child.options[definition.name]!;
        expect(option.isFlag, definition.type == ArgumentType.boolean);
        expect(option.defaultsTo, definition.defaultValue);
        expect(option.allowed, definition.allowed);
        expect(option.abbr, definition.abbr);
        expect(option.help, definition.help);
      }
      final defaults = parser.parse([command.name]).command!;
      expect(defaults.flag('pub'), isTrue);
      expect(
        defaults.option('recipe'),
        command.name == 'feature' ? null : 'clean',
      );
      expect(
        defaults.option('lint-profile'),
        command.name == 'feature' ? null : 'auto',
      );
      expect(defaults.option('state'), isNull);
      for (final name in ['state', 'recipe', 'lint-profile']) {
        expect(
          () => parser.parse([command.name, '--$name', 'invalid']),
          throwsFormatException,
        );
      }
    }
    final create = parser.parse(['create', 'demo']).command!;
    expect(create.option('org'), 'com.example');
    expect(create.option('platforms'), 'ios,android');
    expect(create.option('output'), '.');
    for (final command in ['feature', 'init']) {
      expect(parser.parse([command]).command!.option('project-dir'), '.');
    }
  });

  test('JSON domain choices match the runtime enums', () {
    for (final command in cliCommands.commands.values) {
      final options = {
        for (final option in command.options) option.name: option,
      };
      expect(
        options['state']!.allowed,
        StateStyle.values.map((state) => state.name),
      );
      expect(
        options['recipe']!.allowed,
        Recipe.values.map((recipe) => recipe.name),
      );
      expect(options['lint-profile']!.allowed, [
        'auto',
        ...LintProfile.values.map((profile) => profile.configName),
      ]);
    }
  });

  test(
    'common flags work before and after commands without token rewriting',
    () {
      final parser = cliParser();
      for (final command in cliCommands.commands.keys) {
        for (final option in cliCommands.commonOptions) {
          for (final before in [true, false]) {
            final flag = '--${option.name}';
            final args = parser.parse([
              if (before) flag,
              command,
              if (!before) flag,
            ]);
            expect(commonFlag(args, option.name), isTrue);
            final negated = 'no-${option.name}';
            if (parser.options.containsKey(negated)) {
              expect(
                commonFlag(parser.parse([command, '--$negated']), negated),
                isTrue,
              );
            } else {
              expect(
                () => parser.parse([command, '--$negated']),
                throwsFormatException,
              );
            }
          }
        }
        expect(commonFlag(parser.parse([command, '-h']), 'help'), isTrue);
        expect(
          parser.parse([command, '--no-pub']).command!.flag('pub'),
          isFalse,
        );
      }
      expect(parser.parse(['init']).command!.flag('scaffold'), isFalse);
      expect(
        parser.parse(['init', '--scaffold']).command!.flag('scaffold'),
        isTrue,
      );
      expect(
        () => parser.parse(['init', '--no-scaffold']),
        throwsFormatException,
      );
    },
  );

  test(
    'runner enforces catalog positional bounds before side effects',
    () async {
      final temp = temporaryDirectory();
      addTearDown(() => temp.deleteSync(recursive: true));
      final flutter = FakeToolchain();
      for (final command in cliCommands.commands.values) {
        final cases = [
          List.filled(command.maximumPositionals + 1, 'example'),
          if (command.minimumPositionals > 0)
            List.filled(command.minimumPositionals - 1, 'example'),
        ];
        for (final positionals in cases) {
          final err = StringBuffer();
          expect(
            await runCli(
              [command.name, ...positionals, '--no-interactive'],
              output: StringBuffer(),
              error: err,
              workingDirectory: temp.path,
              toolchain: flutter,
            ),
            64,
            reason: err.toString(),
          );
        }
      }
      expect(flutter.calls, isEmpty);
      expect(temp.listSync(), isEmpty);
    },
  );

  final invalid = <String, void Function(Map<String, dynamic>)>{
    'unknown root key': (root) => root['extra'] = true,
    'missing schema reference': (root) => root.remove(r'$schema'),
    'non-array common options': (root) =>
        root['commonOptions'] = <String, Object?>{},
    'empty commands': (root) => root['commands'] = <Object?>[],
    'duplicate command': (root) =>
        (root['commands'] as List<dynamic>).add(sampleCommand(root)),
    'unknown command key': (root) => sampleCommand(root)['extra'] = true,
    'invalid command name': (root) => sampleCommand(root)['name'] = '--bad',
    'missing command help': (root) => sampleCommand(root).remove('help'),
    'unknown positional key': (root) =>
        ((sampleCommand(root)['positionals'] as List<dynamic>).first
                as Map<String, dynamic>)['extra'] =
            true,
    'non-boolean required': (root) =>
        ((sampleCommand(root)['positionals'] as List<dynamic>).first
                as Map<String, dynamic>)['required'] =
            'true',
    'required after optional': (root) =>
        (sampleCommand(root)['positionals'] as List<dynamic>).add({
          'name': 'last',
          'required': true,
          'help': 'Last.',
        }),
    'duplicate positional': (root) =>
        (sampleCommand(root)['positionals'] as List<dynamic>).add({
          'name': 'target',
          'required': false,
          'help': 'Duplicate.',
        }),
    'reserved positional': (root) =>
        (sampleCommand(root)['positionals'] as List<dynamic>).add({
          'name': 'options',
          'required': false,
          'help': 'Reserved.',
        }),
    'unknown option key': (root) =>
        (sampleOptions(root).first as Map<String, dynamic>)['extra'] = true,
    'unsupported option type': (root) =>
        (sampleOptions(root).first as Map<String, dynamic>)['type'] = 'integer',
    'missing option type': (root) =>
        (sampleOptions(root).first as Map<String, dynamic>).remove('type'),
    'invalid abbreviation': (root) =>
        (sampleOptions(root).first as Map<String, dynamic>)['abbr'] = 'long',
    'invalid string default': (root) =>
        (sampleOptions(root).first as Map<String, dynamic>)['default'] = false,
    'null default': (root) =>
        (sampleOptions(root).first as Map<String, dynamic>)['default'] = null,
    'invalid enum default': (root) =>
        (sampleOptions(root).first as Map<String, dynamic>)['default'] =
            'unknown',
    'non-array enum': (root) =>
        (sampleOptions(root).first as Map<String, dynamic>)['allowed'] = 'fast',
    'empty enum': (root) =>
        (sampleOptions(root).first as Map<String, dynamic>)['allowed'] =
            <Object?>[],
    'duplicate enum value': (root) =>
        (sampleOptions(root).first as Map<String, dynamic>)['allowed'] = [
          'fast',
          'fast',
        ],
    'non-string enum value': (root) =>
        (sampleOptions(root).first as Map<String, dynamic>)['allowed'] = [true],
    'string negation': (root) =>
        (sampleOptions(root).first as Map<String, dynamic>)['negatable'] =
            false,
    'invalid flag default': (root) =>
        (sampleOptions(root).last as Map<String, dynamic>)['default'] = 'true',
    'flag enum': (root) =>
        (sampleOptions(root).last as Map<String, dynamic>)['allowed'] = [
          'true',
        ],
    'invalid negatable': (root) =>
        (sampleOptions(root).last as Map<String, dynamic>)['negatable'] =
            'false',
    'duplicate option': (root) =>
        sampleOptions(root).add(sampleOptions(root).first),
    'common option collision': (root) =>
        sampleOptions(root).add({'name': 'verbose', 'type': 'string'}),
    'abbreviation collision': (root) =>
        sampleOptions(root)
            .add({'name': 'another', 'type': 'string', 'abbr': 'v'}),
    'negated flag collision': (root) =>
        sampleOptions(root).add({'name': 'no-cache', 'type': 'string'}),
  };
  for (final entry in invalid.entries) {
    test('loader rejects ${entry.key}', () {
      final root =
          jsonDecode(jsonEncode(sampleCatalog())) as Map<String, dynamic>;
      entry.value(root);
      expect(
        () => CommandCatalog.parse(jsonEncode(root)),
        throwsFormatException,
      );
    });
  }
  for (final source in ['null', '[]', '{']) {
    test('loader rejects invalid JSON document $source', () {
      expect(() => CommandCatalog.parse(source), throwsFormatException);
    });
  }
}
