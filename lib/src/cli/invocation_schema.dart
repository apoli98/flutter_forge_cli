import 'package:args/args.dart';

import 'command_definitions.dart';

const _discoveryOptions = {'help', 'version', 'schema'};

Map<String, Object?> invocationSchema(
  ArgParser parser, {
  String? command,
  CommandCatalog? definitions,
}) => {
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'title': 'Flutter Forge command invocation',
  'description':
      'Describes CLI arguments for discovery and validation, not JSON input. '
      'Runtime validation still checks names, reserved words, organizations, '
      'platforms, routes, project metadata, dependencies, and filesystem safety. '
      'Defaults are parser defaults only; inherited or detected values are not included.',
  'x-cli': {
    'executable': 'flutter-forge',
    'discoveryOptions': {
      for (final option in parser.options.values)
        if (_discoveryOptions.contains(option.name))
          option.name: _optionSchema(option),
    },
  },
  'oneOf': [
    for (final entry in parser.commands.entries)
      if (command == null || entry.key == command)
        _commandSchema(
          (definitions ?? cliCommands).commands[entry.key]!,
          entry.value,
        ),
  ],
};

Map<String, Object?> _commandSchema(
  CommandDefinition command,
  ArgParser parser,
) => {
  'type': 'object',
  'additionalProperties': false,
  'required': [
    'command',
    for (final positional in command.positionals)
      if (positional.required) positional.name,
  ],
  'properties': {
    'command': {'type': 'string', 'const': command.name},
    for (final (index, positional) in command.positionals.indexed)
      positional.name: {
        'type': 'string',
        'description': positional.help,
        'x-cli': {'position': index},
      },
    'options': {
      'type': 'object',
      'additionalProperties': false,
      'description':
          'Optional CLI arguments using their long names without --. '
          'Omit false nonnegatable flags; false negatable flags use --no-<name>. '
          'Discovery flags are documented separately in x-cli.discoveryOptions.',
      'properties': {
        for (final option in parser.options.values)
          if (!_discoveryOptions.contains(option.name))
            option.name: _optionSchema(option),
      },
      'if': {
        'required': ['interactive'],
        'properties': {
          'interactive': {'const': true},
        },
      },
      'then': {
        'properties': {
          'json': {'const': false},
          'no-interactive': {'const': false},
        },
      },
    },
  },
};

Map<String, Object?> _optionSchema(Option option) => {
  'type': option.isFlag
      ? 'boolean'
      : option.isMultiple
      ? 'array'
      : 'string',
  if (option.isMultiple)
    'items': {
      'type': 'string',
      if (option.allowed != null) 'enum': option.allowed,
    }
  else if (option.allowed != null)
    'enum': option.allowed,
  if (option.defaultsTo != null) 'default': option.defaultsTo,
  if (option.help != null) 'description': option.help,
  'x-cli': {
    'flag': '--${option.name}',
    if (option.abbr != null) 'abbr': option.abbr,
    if (option.isFlag) 'negatable': option.negatable,
    if (option.negatable == true) 'negatedFlag': '--no-${option.name}',
  },
};
