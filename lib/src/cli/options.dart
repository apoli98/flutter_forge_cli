import 'package:args/args.dart';

ArgParser cliParser() {
  final parser = ArgParser();
  _common(parser);
  final create = ArgParser();
  _common(create);
  create
    ..addOption(
      'org',
      defaultsTo: 'com.example',
      help: 'Reverse-domain organization.',
    )
    ..addOption(
      'platforms',
      defaultsTo: 'ios,android',
      help: 'Comma-separated Flutter platforms.',
    )
    ..addOption(
      'output',
      defaultsTo: '.',
      help: 'Existing parent directory of the new app.',
    )
    ..addFlag(
      'pub',
      defaultsTo: true,
      help: 'Run flutter pub get after generation.',
    );
  parser.addCommand('create', create);
  final feature = ArgParser();
  _common(feature);
  feature
    ..addOption(
      'project-dir',
      defaultsTo: '.',
      help: 'Flutter Forge project directory.',
    )
    ..addOption('state', defaultsTo: 'cubit', allowed: ['cubit', 'bloc']);
  parser.addCommand('feature', feature);
  return parser;
}

void _common(ArgParser parser) {
  parser
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.')
    ..addFlag('version', negatable: false, help: 'Show CLI version.')
    ..addFlag(
      'interactive',
      negatable: false,
      help:
          'Collect omitted values in a terminal wizard; --no-interactive disables prompts.',
    )
    ..addFlag(
      'no-interactive',
      negatable: false,
      help: 'Never prompt for input.',
    )
    ..addFlag(
      'json',
      negatable: false,
      help: 'Emit one structured JSON result; never prompt.',
    )
    ..addFlag(
      'dry-run',
      negatable: false,
      help: 'Validate and preview without writes or processes.',
    );
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
    this.state = 'cubit',
  });

  final String command;
  final String name;
  final bool dryRun;
  final String org;
  final String platforms;
  final String output;
  final bool pub;
  final String projectDir;
  final String state;
}
