import 'dart:convert';

import 'commands.g.dart';

final cliCommands = CommandCatalog.parse(embeddedCommandsJson);

enum ArgumentType { boolean, string }

final class CommandCatalog {
  CommandCatalog._(this.commonOptions, this.commands);

  factory CommandCatalog.parse(String source) {
    final root = _object(jsonDecode(source), r'$', {
      r'$schema',
      'commonOptions',
      'commands',
    });
    _text(root[r'$schema'], r'$.$schema');
    final common = _options(root['commonOptions'], 'commonOptions');
    final commands = <String, CommandDefinition>{};
    for (final value in _list(root['commands'], 'commands')) {
      final command = CommandDefinition._parse(value, common);
      if (commands.containsKey(command.name)) {
        throw FormatException('Duplicate command: ${command.name}.');
      }
      commands[command.name] = command;
    }
    if (commands.isEmpty) {
      throw const FormatException('commands must not be empty.');
    }
    return CommandCatalog._(common, Map.unmodifiable(commands));
  }

  final List<OptionDefinition> commonOptions;
  final Map<String, CommandDefinition> commands;
}

final class CommandDefinition {
  CommandDefinition._(this.name, this.help, this.positionals, this.options);

  factory CommandDefinition._parse(
    Object? value,
    List<OptionDefinition> common,
  ) {
    final fields = _object(value, 'command', {
      'name',
      'help',
      'positionals',
      'options',
    });
    final name = _name(fields['name'], 'command.name');
    final positionals = <PositionalDefinition>[];
    final names = {'command', 'options'};
    var optional = false;
    for (final value in _list(fields['positionals'], '$name.positionals')) {
      final positional = PositionalDefinition._parse(value);
      if (!names.add(positional.name)) {
        throw FormatException(
          'Duplicate or reserved positional: $name.${positional.name}.',
        );
      }
      if (optional && positional.required) {
        throw FormatException(
          'Required positionals must precede optional ones: $name.',
        );
      }
      optional = !positional.required;
      positionals.add(positional);
    }
    final options = _options(fields['options'], '$name.options');
    _uniqueOptions([...common, ...options], name);
    return CommandDefinition._(
      name,
      _text(fields['help'], '$name.help'),
      List.unmodifiable(positionals),
      options,
    );
  }

  final String name;
  final String help;
  final List<PositionalDefinition> positionals;
  final List<OptionDefinition> options;

  int get minimumPositionals => positionals.where((p) => p.required).length;
  int get maximumPositionals => positionals.length;
  String get usage => [
    name,
    for (final positional in positionals)
      positional.required ? '<${positional.name}>' : '[${positional.name}]',
  ].join(' ');
}

final class PositionalDefinition {
  PositionalDefinition._(this.name, this.required, this.help);

  factory PositionalDefinition._parse(Object? value) {
    final fields = _object(value, 'positional', {'name', 'required', 'help'});
    return PositionalDefinition._(
      _name(fields['name'], 'positional.name'),
      _boolean(fields['required'], 'positional.required'),
      _text(fields['help'], 'positional.help'),
    );
  }

  final String name;
  final bool required;
  final String help;
}

final class OptionDefinition {
  OptionDefinition._(
    this.name,
    this.type,
    this.abbr,
    this.help,
    this.defaultValue,
    this.allowed,
    this.negatable,
  );

  factory OptionDefinition._parse(Object? value) {
    final fields = _object(value, 'option', {
      'name',
      'type',
      'abbr',
      'help',
      'default',
      'allowed',
      'negatable',
    });
    final name = _name(fields['name'], 'option.name');
    final type = switch (fields['type']) {
      'boolean' => ArgumentType.boolean,
      'string' => ArgumentType.string,
      _ => throw FormatException('Unsupported option type: $name.'),
    };
    final abbr = fields.containsKey('abbr')
        ? _text(fields['abbr'], '$name.abbr')
        : null;
    if (abbr != null && !RegExp(r'^[a-zA-Z0-9]$').hasMatch(abbr)) {
      throw FormatException('Expected a one-character abbreviation: $name.');
    }
    final help = fields.containsKey('help')
        ? _text(fields['help'], '$name.help')
        : null;
    final Object? defaultValue;
    final List<String>? allowed;
    final bool negatable;
    switch (type) {
      case ArgumentType.boolean:
        if (fields.containsKey('allowed')) {
          throw FormatException(
            'Boolean options cannot declare allowed values: $name.',
          );
        }
        defaultValue = fields.containsKey('default')
            ? _boolean(fields['default'], '$name.default')
            : false;
        allowed = null;
        negatable = fields.containsKey('negatable')
            ? _boolean(fields['negatable'], '$name.negatable')
            : true;
      case ArgumentType.string:
        if (fields.containsKey('negatable')) {
          throw FormatException('String options cannot be negatable: $name.');
        }
        defaultValue = fields.containsKey('default')
            ? _text(fields['default'], '$name.default', allowEmpty: true)
            : null;
        allowed = fields.containsKey('allowed')
            ? List.unmodifiable([
                for (final choice in _list(fields['allowed'], '$name.allowed'))
                  _text(choice, '$name.allowed'),
              ])
            : null;
        if (allowed != null &&
            (allowed.isEmpty || allowed.toSet().length != allowed.length)) {
          throw FormatException(
            'Expected distinct nonempty allowed values: $name.',
          );
        }
        if (allowed != null &&
            defaultValue != null &&
            !allowed.contains(defaultValue)) {
          throw FormatException('Default is not an allowed value: $name.');
        }
        negatable = false;
    }
    return OptionDefinition._(
      name,
      type,
      abbr,
      help,
      defaultValue,
      allowed,
      negatable,
    );
  }

  final String name;
  final ArgumentType type;
  final String? abbr;
  final String? help;
  final Object? defaultValue;
  final List<String>? allowed;
  final bool negatable;
}

List<OptionDefinition> _options(Object? value, String path) {
  final options = [
    for (final option in _list(value, path)) OptionDefinition._parse(option),
  ];
  _uniqueOptions(options, path);
  return List.unmodifiable(options);
}

void _uniqueOptions(List<OptionDefinition> options, String path) {
  final names = <String>{};
  final abbreviations = <String>{};
  for (final option in options) {
    if (!names.add(option.name) ||
        (option.negatable && !names.add('no-${option.name}'))) {
      throw FormatException(
        'Duplicate option or negation: $path.${option.name}.',
      );
    }
    if (option.abbr != null && !abbreviations.add(option.abbr!)) {
      throw FormatException('Duplicate abbreviation: $path.${option.abbr}.');
    }
  }
}

Map<String, dynamic> _object(Object? value, String path, Set<String> keys) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('Expected an object: $path.');
  }
  final unknown = value.keys.toSet().difference(keys);
  if (unknown.isNotEmpty) {
    throw FormatException('Unknown keys at $path: ${unknown.join(', ')}.');
  }
  return value;
}

List<dynamic> _list(Object? value, String path) {
  if (value is! List<dynamic>) {
    throw FormatException('Expected an array: $path.');
  }
  return value;
}

String _text(Object? value, String path, {bool allowEmpty = false}) {
  if (value is! String || (!allowEmpty && value.isEmpty)) {
    throw FormatException(
      'Expected a ${allowEmpty ? '' : 'nonempty '}string: $path.',
    );
  }
  return value;
}

String _name(Object? value, String path) {
  final name = _text(value, path);
  if (!RegExp(r'^[a-z][a-z0-9]*(-[a-z0-9]+)*$').hasMatch(name)) {
    throw FormatException('Invalid name: $path.');
  }
  return name;
}

bool _boolean(Object? value, String path) {
  if (value is! bool) throw FormatException('Expected a boolean: $path.');
  return value;
}
