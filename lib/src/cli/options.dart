import 'package:args/args.dart';

import 'command_definitions.dart';

ArgParser cliParser({CommandCatalog? definitions}) {
  final catalog = definitions ?? cliCommands;
  final parser = ArgParser();
  _register(parser, catalog.commonOptions);
  for (final command in catalog.commands.values) {
    final child = ArgParser();
    _register(child, [...catalog.commonOptions, ...command.options]);
    parser.addCommand(command.name, child);
  }
  return parser;
}

void _register(ArgParser parser, List<OptionDefinition> options) {
  for (final option in options) {
    switch (option.type) {
      case ArgumentType.boolean:
        parser.addFlag(
          option.name,
          abbr: option.abbr,
          help: option.help,
          defaultsTo: option.defaultValue as bool,
          negatable: option.negatable,
        );
      case ArgumentType.string:
        parser.addOption(
          option.name,
          abbr: option.abbr,
          help: option.help,
          defaultsTo: option.defaultValue as String?,
          allowed: option.allowed,
        );
    }
  }
}

bool commonFlag(ArgResults args, String name) =>
    args.flag(name) || (args.command?.flag(name) ?? false);

final class CommandOptions {
  const CommandOptions({
    required this.command,
    required this.name,
    required this.dryRun,
    this.org = 'com.example',
    this.platforms = 'ios,android',
    this.output = '.',
    this.pub = true,
    this.projectDir = '.',
    this.state,
    this.recipe,
    this.lintProfile,
    this.route,
    this.scaffold = false,
  });

  final String command;
  final String name;
  final bool dryRun;
  final String org;
  final String platforms;
  final String output;
  final bool pub;
  final String projectDir;
  final String? state;
  final String? recipe;
  final String? lintProfile;
  final String? route;
  final bool scaffold;
}
